import { useEffect, useState } from "react";

function App() {
  const [notes, setNotes] = useState([]);
  const [error, setError] = useState(null);
  const [text, setText] = useState("");
  const [file, setFile] = useState(null);

  function load() {
    fetch("/api/notes")
      .then((res) => res.json())
      .then((data) => setNotes(data));
  }

  useEffect(load, []);

  function submit(event) {
    event.preventDefault();

    // FormData is what makes the browser send a multipart request. Do not set
    // a Content-Type header here, the browser has to set it itself.
    const form = new FormData();
    form.append("text", text);
    if (file) form.append("file", file);

    fetch("/api/notes", { method: "POST", body: form }).then(async (res) => {
      // When the backend won't save a note, it replies with a 4xx status and
      // a body such as { "error": "Note text is required" }.
      if (!res.ok) {
        const body = await res.json();
        setError(body.error);
        return;
      }

      setError(null);
      setText("");
      setFile(null);
      event.target.reset();
      load();
    });
  }

  return (
    <div>
      <h1>My notes</h1>

      <form onSubmit={submit}>
        <input
          value={text}
          onChange={(e) => setText(e.target.value)}
          placeholder="Write a note"
        />
        <input type="file" onChange={(e) => setFile(e.target.files[0])} />
        <button type="submit">Add note</button>
      </form>

      {error && <p role="alert">{error}</p>}

      <ul>
        {notes.map((note) => (
          <li key={note.id}>
            {note.text}
            {note.url && <a href={note.url}> (attachment)</a>}
          </li>
        ))}
      </ul>
    </div>
  );
}

export default App;
