import { describe, expect, test, vi } from "vitest";

import "../helpers/use-s3.js";
import { getFileUrl } from "../../uploads.js";

// Replaces the presigner in every file that imports it, so no request is ever
// sent to AWS.
vi.mock("@aws-sdk/s3-request-presigner", () => ({
  getSignedUrl: vi.fn(async () => "https://signed.example.com/notes.pdf"),
}));

describe("getFileUrl with S3", () => {
  test("returns the signed link", async () => {
    const url = await getFileUrl("notes.pdf");

    expect(url).toBe("https://signed.example.com/notes.pdf");
  });
});
