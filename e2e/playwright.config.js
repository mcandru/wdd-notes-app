import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "./tests",

  use: {
    baseURL: "http://localhost:5173",
  },

  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],

  // Starts the frontend with the Vite dev server. Vite sends requests for /api
  // and /uploads on to the backend, which runs in Docker Compose on port 8000.
  webServer: {
    command: "npm run dev --prefix ../frontend",
    url: "http://localhost:5173",
    reuseExistingServer: !process.env.CI,
  },
});
