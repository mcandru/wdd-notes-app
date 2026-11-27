export { default } from "./load.js";

export const options = {
  // Add 25 users every minute, up to 200
  stages: [
    { duration: "1m", target: 25 },
    { duration: "1m", target: 50 },
    { duration: "1m", target: 75 },
    { duration: "1m", target: 100 },
    { duration: "1m", target: 125 },
    { duration: "1m", target: 150 },
    { duration: "1m", target: 175 },
    { duration: "1m", target: 200 },
    { duration: "1m", target: 0 },
  ],

  // The same thresholds as load.js. The stress test is expected to fail them,
  // and the dashboard shows when it started to fail them.
  thresholds: {
    http_req_duration: ["p(95)<500"],
    http_req_failed: ["rate<0.01"],
  },
};
