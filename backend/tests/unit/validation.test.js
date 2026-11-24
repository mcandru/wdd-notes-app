import { describe, expect, test } from "vitest";

import { validateNoteText } from "../../validation.js";

describe("validateNoteText", () => {
  test("accepts ordinary text", () => {
    expect(validateNoteText("Buy milk")).toBeNull();
  });

  test("accepts text that is exactly 500 characters", () => {
    expect(validateNoteText("x".repeat(500))).toBeNull();
  });

  test.each([
    ["", "Note text is required"],
    ["   ", "Note text is required"],
    [undefined, "Note text is required"],
    ["x".repeat(501), "Note text must be 500 characters or fewer"],
  ])("rejects %j", (text, message) => {
    expect(validateNoteText(text)).toBe(message);
  });
});
