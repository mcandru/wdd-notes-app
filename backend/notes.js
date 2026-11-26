// Helper functions for working with notes.

// Shortens the text of a note for a preview. Text that fits is returned unchanged.
// Longer text is cut to maxLength characters, with "..." on the end.
export function summariseNote(text, maxLength = 50) {
  if (text.length <= maxLength) {
    return text;
  }

  return text.slice(0, maxLength).trimEnd() + "...";
}

// Turns the ID from a URL, such as the "3" in /api/notes/3, into a number.
// Returns null if it isn't a whole number above 0.
export function parseNoteId(value) {
  if (!/^\d+$/.test(value)) {
    return null;
  }

  const id = Number(value);

  return id > 0 ? id : null;
}

// Formats a file size for people to read, e.g. 1536 becomes "1.5 KB".
export function formatFileSize(bytes) {
  if (!Number.isInteger(bytes) || bytes < 0) {
    throw new Error("The size must be a whole number of bytes");
  }

  if (bytes < 1024) {
    return `${bytes} B`;
  }

  if (bytes < 1024 * 1024) {
    return `${Number((bytes / 1024).toFixed(1))} KB`;
  }

  return `${Number((bytes / (1024 * 1024)).toFixed(1))} MB`;
}
