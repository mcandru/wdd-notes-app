// Stores uploaded files in backend/uploads.
//
// This is the development fallback. It is used when S3_BUCKET is not set, so
// that the app runs on a laptop with no AWS account, no bucket and no
// credentials. It is not a deployment option: see the README.

import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export const uploadsDir = path.join(__dirname, "..", "uploads");

export async function save(key, buffer) {
  const target = path.join(uploadsDir, key);

  // The key contains a "/", so the folder it implies has to exist first.
  await mkdir(path.dirname(target), { recursive: true });
  await writeFile(target, buffer);
}

export async function urlFor(key) {
  // Served by express.static, mounted at /uploads in server.js.
  return `/uploads/${key}`;
}
