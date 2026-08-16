// Chooses where uploaded files are stored.
//
// Both drivers expose the same two functions, so the rest of the app never
// needs to know which one it is using:
//
//   save(key, buffer, contentType)  puts a file somewhere
//   urlFor(key)                     returns something a browser can fetch
//
// Which one you get is decided by configuration, not by code. Set S3_BUCKET
// and the app uses S3. Leave it unset and it writes to a folder.

import path from "node:path";
import { randomUUID } from "node:crypto";

import * as local from "./local.js";
import * as s3 from "./s3.js";

export const name = process.env.S3_BUCKET ? "s3" : "local";

const driver = name === "s3" ? s3 : local;

export const { save, urlFor } = driver;

// Only meaningful with the local driver, where server.js has to serve the
// folder these files were written to. In S3 mode nothing is stored on this
// machine, so nothing needs serving from it.
export const uploadsDir = local.uploadsDir;

// Builds the name a file is stored under.
//
// Two people uploading "cv.pdf" must not overwrite each other, so every key
// gets a UUID. The original name is kept on the end only so that the key is
// readable when you are looking at the bucket.
export function keyFor(originalName) {
  // originalName came from a stranger's browser and is about to be used in a
  // file path, so strip any directory part and anything else awkward.
  const safeName = path
    .basename(originalName)
    .replace(/[^a-zA-Z0-9._-]/g, "_")
    .slice(0, 100);

  return `attachments/${randomUUID()}-${safeName}`;
}
