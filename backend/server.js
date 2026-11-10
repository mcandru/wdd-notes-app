import "dotenv/config";

import app, { instanceName, usingS3 } from "./app.js";

const port = process.env.PORT || 8080;

app.listen(port, () => {
  console.log(`Listening on http://localhost:${port}`);
  console.log(`Instance name: ${instanceName}`);
  console.log(
    `Storing uploaded files ${usingS3 ? "in S3" : "in backend/uploads"}`,
  );
});
