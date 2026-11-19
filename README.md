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

## Running the end-to-end tests

Start the app with Docker Compose and seed the database first, as above. Then:

```bash
cd frontend
npm install
cd ../e2e
npm install
npx playwright install chromium
npm test
```

Playwright starts the frontend with the Vite dev server, which sends requests
for `/api` and `/uploads` on to the backend on port 8000.

`e2e/tests/notes.spec.js` has the tests from the end-to-end tests tutorial, and
`e2e/tests/exercises.spec.js` is the solution to the end-to-end test exercises.
