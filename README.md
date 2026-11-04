# Notes app

## Running it with Docker

```bash
docker compose up --build
```

The first time, create the `notes` table and add two example notes to it. In a
second terminal, run:

```bash
docker compose exec app npm run seed
```

Then open <http://localhost:8000/api/notes>.

## Running it without Docker

Start a MySQL database first, with the settings in `backend/.env.example`.

```bash
cd backend
cp .env.example .env
npm install
npm run seed
npm run dev
```

In another terminal:

```bash
cd frontend
npm install
npm run dev
```

## End-to-end tests

`e2e/tests/exercises.exercise.js` has the end-to-end test exercises, with hints
and placeholders to replace. The end-to-end tests tutorial sets up Playwright in
the `e2e` folder.
