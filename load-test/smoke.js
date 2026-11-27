import http from "k6/http";
import { check } from "k6";

const BASE_URL = __ENV.BASE_URL || "http://localhost:8000";

export const options = {
  vus: 1,
  iterations: 1,

  // Fail the test if any check fails
  thresholds: {
    checks: ["rate==1"],
  },
};

export default function () {
  const notesList = http.get(`${BASE_URL}/api/notes`);
  check(notesList, {
    "notesList status is 200": (res) => res.status === 200,
  });

  const createNote = http.post(`${BASE_URL}/api/notes`, {
    text: "Smoke test note",
    file: http.file("Milk, bread, coffee", "list.txt", "text/plain"),
  });
  check(createNote, {
    "createNote status is 201": (res) => res.status === 201,
  });
}
