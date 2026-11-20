import "dotenv/config";

import app from "./app.js";
import { logger } from "./logger.js";
import { usingS3 } from "./uploads.js";

const port = process.env.PORT || 8080;

app.listen(port, () => {
  logger.info(`Listening on http://localhost:${port}`);
  logger.info(
    `Storing uploaded files ${usingS3 ? "in S3" : "in backend/uploads"}`,
  );
});
