import express from "express";

import { validateNoteText } from "./validation.js";

// The name this copy of the app reports, so you can tell copies apart when
// there is more than one. create-infrastructure.sh sets it differently on
// each instance.
const instanceName = process.env.INSTANCE_NAME || "local";

// The notes are kept in memory, in this array. Each copy of the app has its
// own array, and a copy loses its notes when it restarts.
const notes = [];
let nextId = 1;

const app = express();

app.use(express.json());

// Every response says which copy of the app sent it.
app.use((req, res, next) => {
  res.set("X-Instance-Name", instanceName);
  next();
});

app.use(express.static("dist"));

// The load balancer requests this to check that the app is running. Anything
// other than a 200 response counts as unhealthy.
app.get("/health", (req, res) => {
  res.send("ok");
});

app.get("/api/notes", (req, res) => {
  res.json(notes);
});

app.post("/api/notes", (req, res) => {
  const error = validateNoteText(req.body.text);

  if (error) {
    return res.status(400).json({ error });
  }

  const note = { id: nextId++, text: req.body.text };
  notes.push(note);

  res.status(201).json(note);
});

export default app;
