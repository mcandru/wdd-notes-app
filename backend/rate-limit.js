import { rateLimit } from "express-rate-limit";

// Limits how many notes one IP address can save in a minute. Once it has used
// them up, the API will respond with a 429 until the minute is over.
export const notesRateLimit = rateLimit({
  windowMs: 60 * 1000,
  limit: Number(process.env.NOTES_RATE_LIMIT) || 5,
  message: { error: "Too many notes. Please try again later." },
  // Tells the client how many requests it has left, in the RateLimit headers
  standardHeaders: "draft-8",
  legacyHeaders: false,
});
