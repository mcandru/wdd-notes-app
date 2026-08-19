Example code for a simple notes app that will be used in tutorials for IADT's Web Development and Delivery module.

## How to run the backend

The notes are stored in MySQL, so start a database before you start the app.
The command below downloads MySQL, runs it in Docker, and creates an empty
database called `notes`.

```bash
docker run --name notes-db \
  -e MYSQL_ROOT_PASSWORD=notes \
  -e MYSQL_DATABASE=notes \
  -p 3306:3306 \
  -d mysql:8
```

The database keeps running in the background until you stop it. Use
`docker stop notes-db` to stop it and `docker start notes-db` to bring it back
with your notes still in it, or `docker rm -f notes-db` to delete it and
start again from the command above.

Then start the backend.

```bash
cd backend
cp .env.example .env
npm install
npm run seed
npm run dev
```

`npm run seed` creates the `notes` table and puts two example notes in it, and
`.env.example` already has the username, password and port that the Docker
command above sets up.

## How to run the frontend

```bash
cd frontend
npm install
npm run dev
```

## The database

The app keeps its notes in a single table called `notes`, which
`backend/seed.js` creates.

| Column       | Type              | Holds                                     |
| ------------ | ----------------- | ----------------------------------------- |
| `id`         | `BIGINT UNSIGNED` | the number MySQL gives the note           |
| `body`       | `VARCHAR(1000)`   | the text of the note                      |
| `attachment` | `VARCHAR(255)`    | the name of the uploaded file, or nothing |
| `created_at` | `TIMESTAMP`       | when the note was saved                   |

The `id` column is `AUTO_INCREMENT`, so MySQL picks the next number itself
whenever a note is inserted. The code in `server.js` never works one out, it
reads the number back out of the insert and sends it to the browser.

The `attachment` column is allowed to be empty, because most notes have no
file attached to them. It holds a filename rather than a link, for the reason
described in the next section.

Running `npm run seed` again drops the table and creates it a second time, so
it is a way to get back to a clean database. Anything you saved is lost.

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
into it. That is why a note stores the _name_ of its file rather than a link to
it, and why `GET /api/notes` works the links out fresh on every request.
