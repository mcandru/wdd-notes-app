// The imports aren't used until you write the tests. Delete this line when you
// have.
/* eslint-disable no-unused-vars */

import { readdir } from "node:fs/promises";

import { beforeEach, describe, expect, test } from "vitest";
import request from "supertest";

import app from "../../app.js";
import { uploadsDir } from "../../uploads.js";
import { resetDatabase } from "../helpers/database.js";

beforeEach(() => {
  resetDatabase();
});

describe("a note that is too long", () => {
  test("replies with 400 and an error message", async () => {
    // TODO: Write this test
    // Hint:
    // 1. Post a note with text that is 501 characters long, e.g. "x".repeat(501)
    // 2. Check that res.status is 400
    // 3. Check that res.body is the error from validateNoteText in
    //    validation.js
    expect(true).toBe(true); // Placeholder, replace it with your own expect
  });

  test("doesn't save the note", async () => {
    // TODO: Write this test
    // Hint:
    // 1. Post a note with text that is 501 characters long
    // 2. Request GET /api/notes
    // 3. Check that the list still has only the two example notes
    expect(true).toBe(true); // Placeholder, replace it with your own expect
  });
});

describe("a rejected note with a file", () => {
  test("doesn't leave the file in the uploads folder", async () => {
    // TODO: Write this test
    // Hint:
    // 1. Use await readdir(uploadsDir) to get the names of the files in the
    //    uploads folder before the request
    // 2. Post a note with empty text and a file attached, the same way as in
    //    attachments.test.js
    // 3. Check that res.status is 400
    // 4. Get the names of the files again, and check that they're the same as
    //    before, with toEqual
    expect(true).toBe(true); // Placeholder, replace it with your own expect
  });
});

describe("a file under the wrong name", () => {
  test("rejects a file in a field with a different name", async () => {
    // TODO: Write this test
    // Hint:
    // 1. Post a note with .attach("photo", "tests/fixtures/blue-marble.jpg")
    // 2. Use console.log(res.status) to find out what the app replies with
    // 3. Decide which status code it should reply with, and check for that
    //    status code instead
    expect(true).toBe(true); // Placeholder, replace it with your own expect
  });
});

describe("GET /api/notes/:id", () => {
  test("returns the note", async () => {
    // TODO: Write this test
    // Hint:
    // 1. Request GET /api/notes/1
    // 2. Check that res.status is 200
    // 3. Check that res.body is the first example note, the same way as in
    //    notes.test.js
    expect(true).toBe(true); // Placeholder, replace it with your own expect
  });

  test("replies with 404 when there's no note with that ID", async () => {
    // TODO: Write this test
    // Hint:
    // 1. Request a note with an ID that isn't in the database, e.g. 99
    // 2. Check that res.status is 404
    expect(true).toBe(true); // Placeholder, replace it with your own expect
  });

  test("replies with 400 when the ID isn't valid", async () => {
    // TODO: Write this test
    // Hint:
    // 1. Request a note with an ID that parseNoteId rejects, e.g. "abc"
    // 2. Check that res.status is 400
    expect(true).toBe(true); // Placeholder, replace it with your own expect
  });
});
