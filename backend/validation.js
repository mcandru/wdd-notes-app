// Checks the text of a note before it is saved. Returns a message saying what
// is wrong with it, or null if the text is fine.
export function validateNoteText(text) {
  if (typeof text !== "string" || text.trim() === "") {
    return "Note text is required";
  }

  if (text.length > 500) {
    return "Note text must be 500 characters or fewer";
  }

  return null;
}
