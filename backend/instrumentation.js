import { register } from "node:module";

// Sends logs, traces and metrics to the address in
// OTEL_EXPORTER_OTLP_ENDPOINT. It has to run before the app starts, so the
// app is started with: node --import ./instrumentation.js server.js

// The name the app has in Grafana
process.env.OTEL_SERVICE_NAME ||= "notes-api";

// Only the packages this app uses
process.env.OTEL_NODE_ENABLED_INSTRUMENTATIONS ||=
  "http,express,mysql2,aws-sdk,pino,runtime-node";

// Skips checking for Google Cloud and Azure, which delays startup
process.env.OTEL_NODE_RESOURCE_DETECTORS ||= "env,host,serviceinstance";

// The app uses import, not require, so OpenTelemetry needs this hook to see
// the packages it imports
register("@opentelemetry/instrumentation/hook.mjs", import.meta.url);

await import("@opentelemetry/auto-instrumentations-node/register");
