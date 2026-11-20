import { execSync } from "node:child_process";

// Puts the notes table back to the two example notes, by running the same seed
// script as the app. The seed script creates the table again, so the next note
// saved is always 3.
export function resetDatabase() {
  execSync("npm run seed");
}
