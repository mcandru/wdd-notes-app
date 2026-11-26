import { beforeEach, describe, expect, test, vi } from "vitest";

// Runs before the imports below, so the app reads this limit when it starts.
// A low limit means the tests don't need many requests to reach it.
vi.hoisted(() => {
  process.env.NOTES_RATE_LIMIT = "3";
});

import request from "supertest";

import app from "../../app.js";
import { resetDatabase } from "../helpers/database.js";

beforeEach(() => {
  resetDatabase();
});

function saveNote() {
  return request(app).post("/api/notes").field("text", "Buy eggs");
}

describe("rate limiting POST /api/notes", () => {
  test("blocks the fourth note in a minute", async () => {
    for (let i = 0; i < 3; i++) {
      const res = await saveNote();
      expect(res.status).toBe(201);
    }

    const res = await saveNote();

    expect(res.status).toBe(429);
    expect(res.body).toEqual({
      error: "Too many notes. Please try again later.",
    });
  });

  test("still lets the notes be read", async () => {
    const res = await request(app).get("/api/notes");

    expect(res.status).toBe(200);
  });
});
