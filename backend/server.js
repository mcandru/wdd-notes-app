import "dotenv/config";
import express from "express";

const port = process.env.PORT || 8080;

const app = express();

app.use(express.static("dist"));

const notes = [
  { id: 1, text: "Buy milk" },
  { id: 2, text: "Finish the deployment tutorial" },
  { id: 3, text: "Water the plants" },
];

app.get("/api/notes", (req, res) => {
  res.json(notes);
});

app.listen(port, () => {
  console.log(`Listening on http://localhost:${port}`);
});
