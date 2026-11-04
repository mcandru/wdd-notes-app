import { execSync } from "node:child_process";

import mysql from "mysql2/promise";

// Runs once, before any of the tests.
export default async function setup() {
  const name = process.env.DB_NAME;

  // The tests empty the notes table, so never let them run against the
  // database the app uses.
  if (!name.endsWith("_test")) {
    console.error(`Refusing to run the tests against ${name}`);
    process.exit(1);
  }

  const db = await mysql.createConnection({
    host: process.env.DB_HOST,
    port: process.env.DB_PORT,
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
  });

  await db.query(`CREATE DATABASE IF NOT EXISTS ${name}`);
  await db.end();

  // The same script that creates the app's table, run against the test
  // database.
  execSync("npm run seed", { stdio: "inherit" });
}
