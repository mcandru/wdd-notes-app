import { readFile, rm } from "node:fs/promises";
import path from "node:path";

import { beforeEach, describe, expect, test } from "vitest";
import request from "supertest";

import app from "../../app.js";
import { uploadsDir } from "../../uploads.js";
import { resetDatabase } from "../helpers/database.js";

beforeEach(() => {
  resetDatabase();
});

describe("attachments", () => {
  test("saves an attached file", async () => {
    const res = await request(app)
      .post("/api/notes")
      .field("text", "The Earth from Apollo 17")
      .attach("file", "tests/fixtures/blue-marble.jpg");

    expect(res.status).toBe(201);
    expect(res.body.attachment).toMatch(/\.jpg$/);

    const file = await request(app).get(`/uploads/${res.body.attachment}`);

    expect(file.body).toEqual(await readFile("tests/fixtures/blue-marble.jpg"));

    await rm(path.join(uploadsDir, res.body.attachment));
  });

  test("rejects a file over 5 MB", async () => {
    const res = await request(app)
      .post("/api/notes")
      .field("text", "Too big")
      .attach("file", "tests/fixtures/blue-marble-large.jpg");

    expect(res.status).toBe(413);
  });
});
