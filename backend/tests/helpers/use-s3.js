// Sets the variables that make uploads.js use S3. uploads.js reads them as
// soon as it is imported, so import this file before uploads.js.
process.env.S3_BUCKET = "notes-test-bucket";
process.env.AWS_REGION = "eu-west-1";
