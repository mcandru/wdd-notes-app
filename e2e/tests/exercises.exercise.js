import { expect, test } from "@playwright/test";

test.describe("errors", () => {
  test("shows an error for a note over 500 characters", async ({ page }) => {
    // TODO: Write this test
    // Hint:
    // 1. Fill the text box with text that is 501 characters long, e.g.
    //    "x".repeat(501), and click the "Add note" button
    // 2. Check that the alert shows the error from validateNoteText in
    //    backend/validation.js
    expect(true).toBe(true); // Placeholder, replace it with your own expect
  });

  test("keeps the text in the box when a note is rejected", async ({
    page,
  }) => {
    // TODO: Write this test
    // Hint:
    // 1. Add a note that is too long, the same way as in the test above
    // 2. Wait for the alert to appear
    // 3. Check that the text box still has the text in it, with toHaveValue
    expect(true).toBe(true); // Placeholder, replace it with your own expect
  });

  test("shows an error for a file over 5 MB", async ({ page }) => {
    // TODO: Write this test
    // Hint:
    // 1. Fill the text box, and use setInputFiles to pick
    //    "../backend/tests/fixtures/blue-marble-large.jpg", which is 6.2 MB
    // 2. Click the "Add note" button
    // 3. Check that the alert shows "Files must be 5 MB or smaller"
    expect(true).toBe(true); // Placeholder, replace it with your own expect
  });
});

test.describe("attachments", () => {
  test("doesn't show a link for a note without an attachment", async ({
    page,
  }) => {
    // TODO: Write this test
    // Hint:
    // 1. Add a note without picking a file. Put Date.now() in its text, the
    //    same way as in the "adds a note" test in notes.spec.js
    // 2. Find the list item for the note, the same way as in the attachment
    //    test in notes.spec.js
    // 3. Check that there are no links in it, with toHaveCount(0)
    expect(true).toBe(true); // Placeholder, replace it with your own expect
  });
});
