import "dotenv/config";
import express from "express";
import mysql from "mysql2/promise";

import { upload, getFileUrl, usingS3, uploadsDir } from "./uploads.js";

const port = process.env.PORT || 8080;

const db = await mysql.createPool({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
});

const app = express();

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
  const withUrls = await Promise.all(
    notes.map(async (note) => {
      if (!note.attachment) return note;

      return { ...note, url: await getFileUrl(note.attachment) };
    }),
  );

  res.json(withUrls);
});

// upload.single("file") runs before this handler. By the time the handler is
// reached the file has already been saved, and req.file describes where it is stored
app.post("/api/notes", upload.single("file"), async (req, res) => {
  const note = {
    text: req.body.text,
    // multer-s3 calls it "key", diskStorage "filename".
    file: req.file ? req.file.key || req.file.filename : null,
  };

  const [result] = await db.execute(
    "INSERT INTO notes (body, attachment) VALUES (?, ?)",
    [note.text, note.file],
  );

  res.status(201).json({
    id: result.insertId,
    text: note.text,
    attachment: note.file,
  });
});

app.listen(port, () => {
  console.log(`Listening on http://localhost:${port}`);
  console.log(
    `Storing uploaded files ${usingS3 ? "in S3" : "in backend/uploads"}`,
  );
});
