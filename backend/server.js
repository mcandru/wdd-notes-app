import "dotenv/config";
import express from "express";

import { upload, getFileUrl, usingS3, uploadsDir } from "./uploads.js";

const port = process.env.PORT || 8080;

const app = express();

app.use(express.static("dist"));

// With local storage the uploaded files are sitting on this machine, so this
// server has to serve them. In S3 mode nothing is stored here to serve.
if (!usingS3) {
  app.use("/uploads", express.static(uploadsDir));
}

const notes = [
  { id: 1, text: "Buy milk", file: null },
  { id: 2, text: "Finish the deployment tutorial", file: null },
  { id: 3, text: "Water the plants", file: null },
];

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
// reached the file has already been saved, and req.file describes where it is stored
app.post("/api/notes", upload.single("file"), (req, res) => {
  const note = {
    id: notes.length + 1,
    text: req.body.text,
    // multer-s3 calls it "key", diskStorage "filename".
    file: req.file ? req.file.key || req.file.filename : null,
  };

  notes.push(note);
  res.status(201).json(note);
});

app.listen(port, () => {
  console.log(`Listening on http://localhost:${port}`);
  console.log(
    `Storing uploaded files ${usingS3 ? "in S3" : "in backend/uploads"}`,
  );
});
