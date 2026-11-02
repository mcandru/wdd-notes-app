// The imports aren't used until you write the tests. Delete this line when you
// have.
/* eslint-disable no-unused-vars */

import { describe, expect, test } from "vitest";

import { formatFileSize, parseNoteId, summariseNote } from "../../notes.js";

describe("summariseNote", () => {
  test("returns short text as it is", () => {
    // TODO: Write this test
    // Hint:
    // 1. Call summariseNote with text shorter than 50 characters, e.g. "Buy milk"
    // 2. Check that it returns the same text
    expect(true).toBe(true); // Placeholder, replace it with your own expect
  });

  test("returns text of exactly the maximum length as it is", () => {
    // TODO: Write this test
    // Hint:
    // 1. Create text that is exactly 50 characters long, e.g. "x".repeat(50)
    // 2. Check that summariseNote returns the same text
    expect(true).toBe(true); // Placeholder, replace it with your own expect
  });

  test('shortens longer text and adds "..."', () => {
    // TODO: Write this test
    // Hint:
    // 1. Create text that is 51 characters long
    // 2. Check that summariseNote returns the first 50 characters with "..." on
    //    the end
    expect(true).toBe(true); // Placeholder, replace it with your own expect
  });

  test('removes a space before the "..."', () => {
    // TODO: Write this test
    // Hint:
    // 1. summariseNote takes a maxLength as its second argument
    // 2. Pick a maxLength that cuts "Ring the dentist back" just after a space,
    //    e.g. 9 cuts it to "Ring the "
    // 3. Check that the result has no space before the "..."
    expect(true).toBe(true); // Placeholder, replace it with your own expect
  });
});

describe("parseNoteId", () => {
  test('turns "3" into 3', () => {
    // TODO: Write this test
    // Hint:
    // 1. Call parseNoteId with the string "3"
    // 2. Check that it returns the number 3
    expect(true).toBe(true); // Placeholder, replace it with your own expect
  });

  test('returns null for "0", "-1", "1.5" and "abc"', () => {
    // TODO: Write this test
    // Hint:
    // 1. Use test.each in place of test, with one row for each value
    // 2. Check that parseNoteId returns null for each one with toBeNull
    expect(true).toBe(true); // Placeholder, replace it with your own expect
  });
});

describe("formatFileSize", () => {
  test("formats sizes in B, KB and MB", () => {
    // TODO: Write this test
    // Hint:
    // 1. Use test.each, with rows of a size and the text it should be
    //    formatted as, e.g. [1536, "1.5 KB"]
    // 2. 1 KB is 1024 bytes, and 1 MB is 1024 * 1024 bytes
    // 3. Include a size below 1 KB, one in KB and one in MB
    expect(true).toBe(true); // Placeholder, replace it with your own expect
  });

  test("throws for a negative size", () => {
    // TODO: Write this test
    // Hint:
    // 1. Use toThrow, the same way as in Part 2
    // 2. Put the call inside a function, () => formatFileSize(-1), so that
    //    expect can catch the error
    expect(true).toBe(true); // Placeholder, replace it with your own expect
  });

  test("throws for a size that isn't a whole number", () => {
    // TODO: Write this test
    // Hint:
    // 1. Call formatFileSize with a size such as 1.5
    // 2. Check that it throws the same error as the negative size
    expect(true).toBe(true); // Placeholder, replace it with your own expect
  });
});
