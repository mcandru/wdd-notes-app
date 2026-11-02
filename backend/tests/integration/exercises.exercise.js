// The imports aren't used until you write the tests. Delete this line when you
// have.
/* eslint-disable no-unused-vars */

import { readdir, rm } from "node:fs/promises";
import path from "node:path";

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

describe("a note with only spaces", () => {
  test("replies with 400 and an error message", async () => {
    // TODO: Write this test
    // Hint:
    // 1. Post a note with the text "   "
    // 2. Check that res.status is 400
    // 3. Check that res.body is the error from validateNoteText in
    //    validation.js
    expect(true).toBe(true); // Placeholder, replace it with your own expect
  });
});

describe("a note with a file", () => {
  test("is listed with a link to the file", async () => {
    // TODO: Write this test
    // Hint:
    // 1. Post a note with a file attached, the same way as in
    //    attachments.test.js
    // 2. Request GET /api/notes
    // 3. Check that the third note in the list has the same attachment as the
    //    note you posted, and a url of "/uploads/" followed by the attachment
    // 4. Delete the file at the end of the test, the same way as in
    //    attachments.test.js
    expect(true).toBe(true); // Placeholder, replace it with your own expect
  });
});

describe("a file that is too big", () => {
  test("doesn't save the note", async () => {
    // TODO: Write this test
    // Hint:
    // 1. Post a note with tests/fixtures/blue-marble-large.jpg attached, the
    //    same way as in attachments.test.js
    // 2. Request GET /api/notes
    // 3. Check that the list still has only the two example notes
    expect(true).toBe(true); // Placeholder, replace it with your own expect
  });

  test("doesn't leave the file in the uploads folder", async () => {
    // TODO: Write this test
    // Hint:
    // 1. Use await readdir(uploadsDir) to get the names of the files in the
    //    uploads folder before the request
    // 2. Post a note with tests/fixtures/blue-marble-large.jpg attached
    // 3. Get the names of the files again, and check that they're the same as
    //    before, with toEqual
    expect(true).toBe(true); // Placeholder, replace it with your own expect
  });
});

describe("a file that doesn't exist", () => {
  test("replies with 404", async () => {
    // TODO: Write this test
    // Hint:
    // 1. Request a file from /uploads that isn't there, e.g.
    //    /uploads/missing.jpg
    // 2. Check that res.status is 404
    expect(true).toBe(true); // Placeholder, replace it with your own expect
  });
});
