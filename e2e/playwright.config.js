import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "./tests",

  use: {
    baseURL: "http://localhost:5174",
  },

  projects: [
    { name: "chromium", use: { ...devices["Desktop Chrome"] } },
    { name: "firefox", use: { ...devices["Desktop Firefox"] } },
    { name: "webkit", use: { ...devices["Desktop Safari"] } },
  ],

  webServer: [
    // The test copy of the backend and its database, from compose.e2e.yaml.
    {
      command: "docker compose -f ../compose.e2e.yaml up --build",
      url: "http://localhost:8001/api/notes",
      timeout: 180_000,
      stderr: "ignore",
      gracefulShutdown: { signal: "SIGTERM", timeout: 20_000 },
    },
    // The frontend, with Vite sending requests for /api and /uploads on to
    // the test backend.
    {
      command: "npm run dev --prefix ../frontend -- --port 5174",
      url: "http://localhost:5174",
      env: { API_URL: "http://localhost:8001" },
    },
  ],
});
