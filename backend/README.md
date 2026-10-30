# notes-app

The backend for the notes app.

## Running it

```bash
npm install
cp .env.example .env
npm run seed
npm run dev
```

Then open <http://localhost:8000/api/notes>.

## What's in here

- `server.js`, the Express server. It serves the built frontend out of `dist/`,
  and handles `GET /api/notes` and `POST /api/notes`, which read from and write
  to the MySQL database.
- `seed.js`, the script behind `npm run seed`. It drops the `notes` table,
  creates it again, and inserts two example notes.
- `uploads.js`, which decides whether an attached file is written to
  `uploads/` or sent to S3, and turns a stored filename into a link the browser
  can open.
- `validation.js`, which checks the text of a note before it is saved.
- `.env.example`, the configuration this app expects. Copy it to `.env`, which
  is deliberately never committed.
