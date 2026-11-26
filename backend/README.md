# notes-app

The backend for the notes app, with the finished tests from the unit tests and
integration tests tutorials.

## Running it

```bash
npm install
cp .env.example .env
npm run seed
npm run dev
```

Then open <http://localhost:8000/api/notes>.

## Running the tests

The tests run in the app's container. From the folder with `compose.yaml`:

```bash
docker compose up --build
docker compose exec app npm test
```

`npm test` runs the tests, then runs them again whenever a file changes. Press
`q` to stop. `npx vitest run` runs them once, and `npm run test:coverage` runs
them once and prints a coverage report.

The tests use a `notes_test` database on the same MySQL server, so they never
change the app's notes.

## What's in here

- `app.js`, the Express app. It serves the built frontend out of `dist/`, and
  handles `GET /api/notes` and `POST /api/notes`. It also connects to the
  MySQL database.
- `server.js`, which starts the app on a port.
- `seed.js`, the script behind `npm run seed`. It drops the `notes` table,
  creates it again, and inserts two example notes.
- `uploads.js`, which decides whether an attached file is written to
  `uploads/` or sent to S3, and turns a stored filename into a link the browser
  can open.
- `validation.js`, which checks the text of a note before it is saved.
- `notes.js`, helper functions for working with notes.
- `vitest.config.js`, which points the tests at the `notes_test` database.
- `tests/setup.js`, which creates the test database before the tests run.
- `tests/fixtures`, the photos that the integration tests upload.
- `tests/helpers/database.js`, which puts the test database back to the two
  example notes before each test.
- `tests/unit` and `tests/integration`, the tests.
- `tests/unit/notes.exercise.js` and `tests/integration/exercises.exercise.js`,
  the exercise files from the unit and integration tests tutorials, with hints
  and placeholders to replace.
- `.env.example`, the configuration this app expects. Copy it to `.env`, which
  is deliberately never committed.
