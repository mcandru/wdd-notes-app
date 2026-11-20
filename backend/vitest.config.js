import { defineConfig } from "vitest/config";

// The tests use a database of their own, so that they never change your notes.
process.env.DB_NAME = "notes_test";

export default defineConfig({
  test: {
    globalSetup: "./tests/setup.js",
    // The test files share one database, so run them one at a time.
    fileParallelism: false,
    coverage: {
      exclude: ["tests/**"],
    },
  },
});
