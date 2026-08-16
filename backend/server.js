import "dotenv/config";
import express from "express";
import multer from "multer";
import path from "node:path";
import { fileURLToPath } from "node:url";

import * as storage from "./storage/index.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const port = process.env.PORT || 8080;

const app = express();

// memoryStorage keeps the upload in a buffer instead of writing it to disk.
// The storage driver decides where it actually ends up.
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024 },
});

app.use(express.static("dist"));

// The local driver returns /uploads/<key> links, so those files need serving.
// In S3 mode nothing is stored on this machine and there is nothing to serve.
if (storage.name === "local") {
  app.use("/uploads", express.static(storage.uploadsDir));
}

const notes = [
  { id: 1, text: "Buy milk", attachment: null },
  { id: 2, text: "Finish the deployment tutorial", attachment: null },
  { id: 3, text: "Water the plants", attachment: null },
];

app.get("/api/notes", async (req, res) => {
  const withUrls = await Promise.all(
    notes.map(async (note) => {
      if (!note.attachment) return note;

      return { ...note, url: await storage.urlFor(note.attachment) };
    }),
  );

  res.json(withUrls);
});

app.post("/api/notes", upload.single("file"), async (req, res) => {
  let key = null;

  if (req.file) {
    key = storage.keyFor(req.file.originalname);
    await storage.save(key, req.file.buffer, req.file.mimetype);
  }

  const note = {
    id: notes.length + 1,
    text: req.body.text,
    attachment: key,
  };

  notes.push(note);
  res.status(201).json(note);
});

app.listen(port, () => {
  console.log(`Listening on http://localhost:${port}`);
  console.log(`Storing uploaded files with the "${storage.name}" driver`);
});
