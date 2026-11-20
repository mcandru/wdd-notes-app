import { expect, test } from "@playwright/test";

test.describe("errors", () => {
  test("shows an error for a note over 500 characters", async ({ page }) => {
    await page.goto("/");

    await page.getByPlaceholder("Write a note").fill("x".repeat(501));
    await page.getByRole("button", { name: "Add note" }).click();

    await expect(page.getByRole("alert")).toHaveText(
      "Note text must be 500 characters or fewer",
    );
  });

  test("keeps the text in the box when a note is rejected", async ({
    page,
  }) => {
    const text = "x".repeat(501);

    await page.goto("/");

    await page.getByPlaceholder("Write a note").fill(text);
    await page.getByRole("button", { name: "Add note" }).click();

    await expect(page.getByRole("alert")).toBeVisible();
    await expect(page.getByPlaceholder("Write a note")).toHaveValue(text);
  });

  test("shows an error for a file over 5 MB", async ({ page }) => {
    await page.goto("/");

    await page.getByPlaceholder("Write a note").fill(`Too big ${Date.now()}`);
    await page
      .locator('input[type="file"]')
      .setInputFiles("../backend/tests/fixtures/blue-marble-large.jpg");
    await page.getByRole("button", { name: "Add note" }).click();

    await expect(page.getByRole("alert")).toHaveText(
      "Files must be 5 MB or smaller",
    );
  });
});

test.describe("attachments", () => {
  test("doesn't show a link for a note without an attachment", async ({
    page,
  }) => {
    const text = `No file ${Date.now()}`;

    await page.goto("/");

    await page.getByPlaceholder("Write a note").fill(text);
    await page.getByRole("button", { name: "Add note" }).click();

    const note = page.getByRole("listitem").filter({ hasText: text });

    await expect(note).toBeVisible();
    await expect(note.getByRole("link")).toHaveCount(0);
  });
});
