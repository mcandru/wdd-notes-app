// The longest note the app accepts. On ECS, the task definition sets
// MAX_NOTE_LENGTH from a value in Parameter Store.
const maxLength = Number(process.env.MAX_NOTE_LENGTH) || 500;

// Checks the text of a note before it is saved. Returns a message saying what
// is wrong with it, or null if the text is fine.
export function validateNoteText(text) {
  if (typeof text !== "string" || text.trim() === "") {
    return "Note text is required";
  }

  if (text.length > maxLength) {
    return `Note text must be ${maxLength} characters or fewer`;
  }

  return null;
}
