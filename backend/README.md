# notes-app

The finished code from the tutorial "Build a Simple Server with Node.js".

This exists so that you can start the next tutorial even if your own version
didn't come together. Building it yourself is still the better option, so use
this as a fallback rather than a shortcut.

## Running it

The app reads and writes a MySQL database, so there has to be one running
before you start. The README in the folder above has the Docker command that
starts one.

```bash
npm install
cp .env.example .env
npm run seed
npm run dev
```

Then open <http://localhost:8000>.

`npm run seed` is the one you can forget about after the first time. It creates
the table the app expects, and you only need it again when you want an empty
database.

## What's in here

- `server.js`, the Express server. It serves the built frontend out of `dist/`,
  and handles `GET /api/notes` and `POST /api/notes`, which read from and write
  to the database.
- `seed.js`, the script behind `npm run seed`. It drops the `notes` table,
  creates it again, and inserts two example notes.
- `uploads.js`, which decides whether an attached file is written to
  `uploads/` or sent to S3, and turns a stored filename into a link the browser
  can open.
- `.env.example`, the configuration this app expects. Copy it to `.env`, which
  is deliberately never committed.
