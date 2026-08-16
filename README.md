Example code for a simple notes app that will be used in tutorials for IADT's Web Development and Delivery module.

## How to run the backend

```bash
cd backend
cp .env.example .env
npm install
npm run dev
```

## How to run the frontend

```bash
cd frontend
npm install
npm run dev
```

## File uploads

A note can have a file attached to it, and the app can store that file in two
places. Which one it uses is decided by configuration, not by code.

| `S3_BUCKET` | Files go to       | Links are                              |
| ----------- | ----------------- | -------------------------------------- |
| unset       | `backend/uploads` | `/uploads/<key>`                       |
| set         | that S3 bucket    | presigned URLs, valid for five minutes |

The app prints which one it is using when it starts.

Both are in `backend/storage/`, behind the same two functions, so nothing else
in the app knows the difference:

- `save(key, buffer, contentType)` puts a file somewhere
- `urlFor(key)` returns something a browser can fetch

Leaving `S3_BUCKET` unset means the app runs on a laptop with no AWS account,
no bucket and no credentials.

> [!WARNING]
> **Local storage is a development convenience, not a deployment option.**
> Files written to `backend/uploads` live on one machine's disk. They are not
> backed up, they are lost when that machine is replaced, and a second copy of
> the app cannot see them.

Note that `backend/storage/s3.js` contains no access key and no secret. The AWS
SDK looks for credentials in a fixed order, and finds your CLI profile on a
laptop and the instance role when it runs on EC2.
