import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// The end-to-end tests set API_URL, so that Vite sends requests to the test
// copy of the backend instead.
const apiUrl = process.env.API_URL ?? "http://localhost:8000";

export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      "/api": apiUrl,
      // The local storage driver returns relative /uploads links, so these have
      // to reach the backend too. Without this, Vite answers with index.html and
      // clicking an attachment appears to do nothing.
      "/uploads": apiUrl,
    },
  },
  build: { outDir: "../backend/dist", emptyOutDir: true },
});
