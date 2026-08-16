// Where uploaded files go.
//
// Set S3_BUCKET and files are uploaded to that bucket. Leave it unset and they
// are written to backend/uploads instead.
//

import { mkdirSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { randomUUID } from "node:crypto";

import multer from "multer";
import multerS3 from "multer-s3";
import { S3Client, GetObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export const usingS3 = Boolean(process.env.S3_BUCKET);
export const uploadsDir = path.join(__dirname, "uploads");

// How long an S3 download link stays valid for, in seconds.
const URL_LIFETIME = 300;

// Decides what a file is stored as. Two people uploading "cv.pdf" must not
// overwrite each other, so every file gets a UUID for a name. The extension is
// kept on the end so the file still opens in the right thing.
//
function chooseFilename(req, file, cb) {
  cb(null, randomUUID() + path.extname(file.originalname));
}

let s3;
let storage;

if (usingS3) {
  // Notice there is no access key and no secret anywhere here. The SDK looks
  // for credentials in a fixed order, and finds your CLI profile on a laptop
  // and the instance role when it runs on EC2, so the same code works in both.
  s3 = new S3Client({ region: process.env.AWS_REGION });

  // multer-s3 sends the file straight to the bucket as the request arrives, so
  // an upload never touches this machine's disk at all.
  storage = multerS3({
    s3,
    bucket: process.env.S3_BUCKET,
    contentType: multerS3.AUTO_CONTENT_TYPE,
    key: chooseFilename,
  });
} else {
  // multer will not create this folder itself, so make sure it is there.
  mkdirSync(uploadsDir, { recursive: true });

  storage = multer.diskStorage({
    destination: uploadsDir,
    filename: chooseFilename,
  });
}

export const upload = multer({
  storage,
  limits: { fileSize: 5 * 1024 * 1024 },
});

// Turns a stored filename into a link the browser can actually open.
export async function getFileUrl(filename) {
  if (!usingS3) {
    // Served by express.static, mounted at /uploads in server.js.
    return `/uploads/${filename}`;
  }

  // The bucket is private, so a plain bucket URL would be refused. A presigned
  // URL is a link with a signature and an expiry built into it, which lets a
  // browser fetch one file without having any AWS credentials of its own.
  return getSignedUrl(
    s3,
    new GetObjectCommand({ Bucket: process.env.S3_BUCKET, Key: filename }),
    { expiresIn: URL_LIFETIME },
  );
}
