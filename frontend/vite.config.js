import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      "/api": "http://localhost:8000",
      // The local storage driver returns relative /uploads links, so these have
      // to reach the backend too. Without this, Vite answers with index.html and
      // clicking an attachment appears to do nothing.
      "/uploads": "http://localhost:8000",
    },
  },
  build: { outDir: "../backend/dist", emptyOutDir: true },
});
