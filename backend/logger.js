import pino from "pino";

// Writes each log as one line of JSON
export const logger = pino({
  level: process.env.LOG_LEVEL || "info",
  // "level":"info" instead of "level":30
  formatters: { level: (label) => ({ level: label }) },
  timestamp: pino.stdTimeFunctions.isoTime,
});
