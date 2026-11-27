import http from "k6/http";
import { check, sleep } from "k6";

const BASE_URL = __ENV.BASE_URL || "http://localhost:8000";

export const options = {
  stages: [
    { duration: "1m", target: 20 }, // from 0 to 20 users over a minute
    { duration: "3m", target: 20 }, // stay at 20 users
    { duration: "1m", target: 0 }, // back down to 0
  ],

  // The test passes if 95% of requests take under half a second, and fewer
  // than 1% of requests fail
  thresholds: {
    http_req_duration: ["p(95)<500"],
    http_req_failed: ["rate<0.01"],
  },
};

// Run by each "virtual user" repeatedly until the test finishes
export default function () {
  const notesList = http.get(`${BASE_URL}/api/notes`);
  check(notesList, {
    "notesList status is 200": (res) => res.status === 200,
  });

  // Reading the notes, for between 1 and 5 seconds
  sleep(1 + Math.random() * 4);

  // About 1 visit in 5 saves a note
  if (Math.random() < 0.2) {
    const createNote = http.post(`${BASE_URL}/api/notes`, {
      text: "Load test note",
      file: http.file("Milk, bread, coffee", "list.txt", "text/plain"),
    });
    check(createNote, {
      "createNote status is 201": (res) => res.status === 201,
    });

    sleep(1 + Math.random() * 2);
  }
}
