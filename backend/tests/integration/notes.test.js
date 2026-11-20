import { beforeEach, describe, expect, test } from "vitest";
import request from "supertest";

import app from "../../app.js";
import { resetDatabase } from "../helpers/database.js";

beforeEach(() => {
  resetDatabase();
});

describe("GET /api/notes", () => {
  test("returns the example notes", async () => {
    const res = await request(app).get("/api/notes");

    expect(res.status).toBe(200);
    expect(res.body).toHaveLength(2);
    expect(res.body[0]).toEqual({
      id: 1,
      text: "Milk, bread, coffee",
      attachment: null,
    });
  });
});

describe("POST /api/notes", () => {
  test("saves a note", async () => {
    const res = await request(app).post("/api/notes").field("text", "Buy eggs");

    expect(res.status).toBe(201);
    expect(res.body).toEqual({ id: 3, text: "Buy eggs", attachment: null });
  });

  test("adds the note to the list", async () => {
    await request(app).post("/api/notes").field("text", "Buy eggs");

    const res = await request(app).get("/api/notes");

    expect(res.body).toHaveLength(3);
    expect(res.body[2].text).toBe("Buy eggs");
  });

  test("rejects an empty note", async () => {
    const res = await request(app).post("/api/notes").field("text", "");

    expect(res.status).toBe(400);
    expect(res.body).toEqual({ error: "Note text is required" });
  });
});
