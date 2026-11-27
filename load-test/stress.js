// Each virtual user does the same as in load.js
export { default } from "./load.js";

export const options = {
  stages: [
    { duration: "4m", target: 200 }, // from 0 to 200 users over 4 minutes
    { duration: "1m", target: 0 }, // back down to 0
  ],

  // The same thresholds as load.js.
  thresholds: {
    http_req_duration: ["p(95)<500"],
    http_req_failed: ["rate<0.01"],
  },
};
