// Stores uploaded files in an S3 bucket.
//
// Used when S3_BUCKET is set. Notice that there is no access key and no secret
// anywhere in this file. The SDK looks for credentials in a fixed order and
// finds your CLI profile on a laptop, and the instance role when it runs on
// EC2, so the same code works in both places.

import {
  S3Client,
  PutObjectCommand,
  GetObjectCommand,
} from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

// How long a download link stays valid for, in seconds.
const URL_LIFETIME = 300;

let client;

// Built on first use rather than when this file is imported, so that nothing
// AWS-related happens at all when the app is running with the local driver.
function getClient() {
  if (!client) {
    client = new S3Client({ region: process.env.AWS_REGION });
  }

  return client;
}

export async function save(key, buffer, contentType) {
  await getClient().send(
    new PutObjectCommand({
      Bucket: process.env.S3_BUCKET,
      Key: key,
      Body: buffer,
      ContentType: contentType,
    }),
  );
}

export async function urlFor(key) {
  // The bucket is private, so a plain bucket URL would be refused. A presigned
  // URL is a link with a signature and an expiry built into it, which lets a
  // browser fetch one object without having any AWS credentials of its own.
  return getSignedUrl(
    getClient(),
    new GetObjectCommand({ Bucket: process.env.S3_BUCKET, Key: key }),
    { expiresIn: URL_LIFETIME },
  );
}
