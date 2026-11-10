import express from "express";

import { getInstanceName } from "./instance-name.js";
import { validateNoteText } from "./validation.js";
import { upload, getFileUrl, usingS3, uploadsDir } from "./uploads.js";

// The name this copy of the app reports. On ECS this is the task ID.
const instanceName = await getInstanceName();

// The notes are kept in memory, in this array. Each copy of the app has its
// own array, and a copy loses its notes when it restarts. The files attached
// to notes go to S3, so every copy can reach them.
const notes = [];
let nextId = 1;

const app = express();

app.use(express.json());

// Every response says which copy of the app sent it.
app.use((req, res, next) => {
  res.set("X-Instance-Name", instanceName);
  next();
});

// Writes one line for each request once the response is sent. On ECS these
// lines go to CloudWatch Logs.
app.use((req, res, next) => {
  res.on("finish", () => {
    console.log(`${req.method} ${req.originalUrl} ${res.statusCode}`);
  });
  next();
});

app.use(express.static("dist"));

// With local storage the uploaded files are sitting on this machine, so this
// server has to serve them. In S3 mode nothing is stored here to serve.
if (!usingS3) {
  app.use("/uploads", express.static(uploadsDir));
}

// A load balancer requests this to check that the app is running. Anything
// other than a 200 response counts as unhealthy.
app.get("/health", (req, res) => {
  res.send("ok");
});

app.get("/api/notes", async (req, res) => {
  // A note stores the name of its file, not a link to it, because an S3 link
  // expires. So the link is worked out fresh every time the notes are sent.
  const withUrls = await Promise.all(
    notes.map(async (note) => {
      if (!note.file) return note;

      return { ...note, url: await getFileUrl(note.file) };
    }),
  );

  res.json(withUrls);
});

// upload.single("file") runs before this handler. By the time the handler is
// reached the file has already been saved, and req.file describes where it is
// stored. It also reads the text fields of the form into req.body.
app.post("/api/notes", upload.single("file"), (req, res) => {
  const error = validateNoteText(req.body.text);

  if (error) {
    return res.status(400).json({ error });
  }

  const note = {
    id: nextId++,
    text: req.body.text,
    // multer-s3 calls it "key", diskStorage "filename".
    file: req.file ? req.file.key || req.file.filename : null,
  };
  notes.push(note);

  res.status(201).json(note);
});

export { instanceName, usingS3 };
export default app;
