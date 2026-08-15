# notes-app

The finished code from the tutorial "Build a Simple Server with Node.js".

This exists so that you can start the next tutorial even if your own version
didn't come together. Building it yourself is still the better option, so use
this as a fallback rather than a shortcut.

## Running it

```bash
npm install
cp .env.example .env
npm run dev
```

Then open <http://localhost:8000>.

## What's in here

- `server.js`, the Express server. It serves the `public/` folder and a
  `GET /api/notes` endpoint that returns a hardcoded array of notes.
- `serverVanilla.js`, the plain `node:http` version from Part 1 of the
  tutorial. Nothing uses it, it is kept so you can compare the two.
- `public/index.html`, the frontend. Plain HTML and JavaScript, no framework.
- `.env.example`, the configuration this app expects. Copy it to `.env`, which
  is deliberately never committed.
