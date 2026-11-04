import "dotenv/config";

import app from "./app.js";
import { usingS3 } from "./uploads.js";

const port = process.env.PORT || 8080;

app.listen(port, () => {
  console.log(`Listening on http://localhost:${port}`);
  console.log(
    `Storing uploaded files ${usingS3 ? "in S3" : "in backend/uploads"}`,
  );
});
