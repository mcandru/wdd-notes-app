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
| unset       | `backend/uploads` | `/uploads/<filename>`                  |
| set         | that S3 bucket    | presigned URLs, valid for five minutes |

The app prints which one it is using when it starts.

All of it is in `backend/uploads.js`. Uploads are handled by
[multer](https://www.npmjs.com/package/multer), which is given one of two
storage engines:

- `multer.diskStorage`, which writes the file to a folder
- [`multer-s3`](https://www.npmjs.com/package/multer-s3), which sends it to a
  bucket instead

That file also exports `getFileUrl(filename)`, which turns a stored filename
into a link the browser can open.

Leaving `S3_BUCKET` unset means the app runs on a laptop with no AWS account,
no bucket and no credentials.

> [!WARNING]
> **Local storage is a development convenience, not a deployment option.**
> Files written to `backend/uploads` live on one machine's disk. They are not
> backed up, they are lost when that machine is replaced, and a second copy of
> the app cannot see them.

Note that `backend/uploads.js` contains no access key and no secret. The AWS
SDK looks for credentials in a fixed order, and finds your CLI profile on a
laptop and the instance role when it runs on EC2.

The bucket stays private. Nothing in it is publicly readable, so a note's
attachment link is a presigned URL: a link with a signature and an expiry built
into it. That is why a note stores the *name* of its file rather than a link to
it, and why `GET /api/notes` works the links out fresh on every request.
