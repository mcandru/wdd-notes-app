import "dotenv/config";

import app from "./app.js";

const port = process.env.PORT || 8080;

app.listen(port, () => {
  console.log(`Listening on http://localhost:${port}`);
  console.log(`Instance name: ${process.env.INSTANCE_NAME || "local"}`);
});
