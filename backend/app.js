import express from "express";
import { trace } from "@opentelemetry/api";
import multer from "multer";
import mysql from "mysql2/promise";
import { pinoHttp } from "pino-http";

import { upload, getFileUrl, usingS3, uploadsDir } from "./uploads.js";
import { validateNoteText } from "./validation.js";
import { logger } from "./logger.js";

// A pool keeps a few connections to the database open, and shares them
// between requests.
const db = mysql.createPool({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
});

// Creates the app's own spans, as well as the ones OpenTelemetry makes for
// Express and MySQL
const tracer = trace.getTracer("notes-api");

const app = express();

// Logs one line for every request, once its response has been sent
app.use(
  pinoHttp({
    logger,
    customLogLevel: (req, res, err) => {
      if (err || res.statusCode >= 500) return "error";
      if (res.statusCode >= 400) return "warn";
      return "info";
    },
    customSuccessMessage: (req, res) =>
      `${req.method} ${req.url.split("?")[0]} ${res.statusCode}`,
    customErrorMessage: (req, res) =>
      `${req.method} ${req.url.split("?")[0]} ${res.statusCode}`,
    serializers: {
      req: (req) => ({ method: req.method, path: req.url.split("?")[0] }),
      res: (res) => ({ status_code: res.statusCode }),
    },
  }),
);

app.use(express.static("dist"));

// With local storage the uploaded files are sitting on this machine, so this
// server has to serve them. In S3 mode nothing is stored here to serve.
if (!usingS3) {
  app.use("/uploads", express.static(uploadsDir));
}

app.get("/api/notes", async (req, res) => {
  // Retrieve all notes from the database.
  const results = await db.query(
    "SELECT id, body AS text, attachment FROM notes ORDER BY id",
  );
  const notes = results[0];

  // A note stores the name of its file, not a link to it, because an S3 link
  // expires. So the link is worked out fresh every time the notes are sent.
  const withUrls = await tracer.startActiveSpan(
    "add file links",
    async (span) => {
      span.setAttribute("notes.count", notes.length);

      try {
        return await Promise.all(
          notes.map(async (note) => {
            if (!note.attachment) return note;

            return { ...note, url: await getFileUrl(note.attachment) };
          }),
        );
      } finally {
        // A span has to be ended, or it's never sent
        span.end();
      }
    },
  );

  res.json(withUrls);
});

// upload.single("file") runs before this handler. By the time the handler is
// reached the file has already been saved, and req.file describes where it is stored
app.post("/api/notes", upload.single("file"), async (req, res) => {
  const error = validateNoteText(req.body.text);

  if (error) {
    return res.status(400).json({ error });
  }

  const note = {
    text: req.body.text,
    // multer-s3 calls it "key", diskStorage "filename".
    file: req.file ? req.file.key || req.file.filename : null,
  };

  const [result] = await db.execute(
    "INSERT INTO notes (body, attachment) VALUES (?, ?)",
    [note.text, note.file],
  );

  req.log.info({ note_id: result.insertId }, "Saved a note");
  trace.getActiveSpan()?.setAttribute("note.id", result.insertId);

  res.status(201).json({
    id: result.insertId,
    text: note.text,
    attachment: note.file,
  });
});

// Errors from multer, such as a file over the size limit, are passed on to
// here. Without this, Express answers every one of them with a 500.
app.use((err, req, res, next) => {
  if (err instanceof multer.MulterError && err.code === "LIMIT_FILE_SIZE") {
    return res.status(413).json({ error: "Files must be 5 MB or smaller" });
  }

  next(err);
});

// Any other error. The details go in the log, and the user gets a message
// that doesn't reveal anything about how the app works.
app.use((err, req, res, next) => {
  if (res.headersSent) return next(err);

  // pino-http adds res.err to the log line for this request
  res.err = err;
  res.status(500).json({ error: "Something went wrong" });
});

export default app;
