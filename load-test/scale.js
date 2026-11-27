// Each virtual user does the same as in load.js
export { default } from "./load.js";

const USERS = Number(__ENV.USERS) || 100;

export const options = {
  stages: [
    { duration: "2m", target: USERS }, // from 0 to USERS over 2 minutes
    { duration: "10m", target: USERS }, // stay at USERS for 10 minutes
    { duration: "2m", target: 0 }, // back down to 0
  ],

  // The same thresholds as load.js
  thresholds: {
    http_req_duration: ["p(95)<500"],
    http_req_failed: ["rate<0.01"],
  },

  // Where k6 Cloud runs the test from, and the test's name in Grafana Cloud
  cloud: {
    name: "Notes app scaling test",
    distribution: {
      dublin: { loadZone: "amazon:ie:dublin", percent: 100 },
    },
  },
};
