import { expect, test } from "@playwright/test";

test("shows the example notes", async ({ page }) => {
  await page.goto("/");

  await expect(page.getByText("Milk, bread, coffee")).toBeVisible();
});

test("adds a note", async ({ page }) => {
  const text = `Water the plants ${Date.now()}`;

  await page.goto("/");

  await page.getByPlaceholder("Write a note").fill(text);
  await page.getByRole("button", { name: "Add note" }).click();

  await expect(page.getByText(text)).toBeVisible();
  await expect(page.getByPlaceholder("Write a note")).toHaveValue("");

  await page.reload();

  await expect(page.getByText(text)).toBeVisible();
});

test("adds a note with an attachment", async ({ page }) => {
  const text = `The Earth from Apollo 17 ${Date.now()}`;

  await page.goto("/");

  await page.getByPlaceholder("Write a note").fill(text);
  await page
    .locator('input[type="file"]')
    .setInputFiles("../backend/tests/fixtures/blue-marble.jpg");
  await page.getByRole("button", { name: "Add note" }).click();

  const note = page.getByRole("listitem").filter({ hasText: text });

  await expect(note.getByRole("link")).toHaveAttribute(
    "href",
    /^\/uploads\/.+\.jpg$/,
  );
});

test("shows an error for an empty note", async ({ page }) => {
  await page.goto("/");

  await page.getByRole("button", { name: "Add note" }).click();

  await expect(page.getByRole("alert")).toHaveText("Note text is required");
});
