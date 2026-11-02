// Creates the notes table and puts two example notes in it.
//
// Run it with `npm run seed`, once when you first set the app up, and again
// whenever you want to go back to a clean database. It drops the table before
// it creates it, so any notes you saved are lost.

import "dotenv/config";
import mysql from "mysql2/promise";

// server.js opens a pool, because it handles many requests at once. A script
// that runs a handful of statements and then exits only needs one connection.
const db = await mysql.createConnection({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
});

await db.query("DROP TABLE IF EXISTS notes");

// A note is one row here.
//
// AUTO_INCREMENT means MySQL picks the id for each new note, so server.js
// never has to work one out. It reads the number back out of the insert.
//
// attachment holds the name of an uploaded file rather than a link to it,
// because an S3 link expires after five minutes. See uploads.js. It is
// nullable because most notes have no file attached to them.
await db.query(`
  CREATE TABLE notes (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    body VARCHAR(1000) NOT NULL,
    attachment VARCHAR(255) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id)
  )
`);

await db.query("INSERT INTO notes (body) VALUES (?), (?)", [
  "Milk, bread, coffee",
  "Ring the dentist back",
]);

console.log(`Created the notes table in the ${process.env.DB_NAME} database.`);

await db.end();
