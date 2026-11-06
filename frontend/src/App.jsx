import { useEffect, useState } from "react";

function App() {
  const [notes, setNotes] = useState([]);
  const [instance, setInstance] = useState(null);
  const [error, setError] = useState(null);
  const [text, setText] = useState("");

  function load() {
    fetch("/api/notes").then(async (res) => {
      // The backend names itself in a header on every response, so this is
      // the copy of the app that sent these notes.
      setInstance(res.headers.get("X-Instance-Name"));
      setNotes(await res.json());
    });
  }

  useEffect(load, []);

  function submit(event) {
    event.preventDefault();

    fetch("/api/notes", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text }),
    }).then(async (res) => {
      // When the backend won't save a note, it replies with a 4xx status and
      // a body such as { "error": "Note text is required" }.
      if (!res.ok) {
        const body = await res.json();
        setError(body.error);
        return;
      }

      setError(null);
      setText("");
      load();
    });
  }

  return (
    <div>
      <h1>My notes</h1>

      <p>
        Served by <strong>{instance ?? "..."}</strong>
      </p>

      <form onSubmit={submit}>
        <input
          value={text}
          onChange={(e) => setText(e.target.value)}
          placeholder="Write a note"
        />
        <button type="submit">Add note</button>
      </form>

      {error && <p role="alert">{error}</p>}

      <ul>
        {notes.map((note) => (
          <li key={note.id}>{note.text}</li>
        ))}
      </ul>
    </div>
  );
}

export default App;
