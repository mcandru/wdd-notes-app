import http from "node:http";

const server = http.createServer((req, res) => {
  console.log(req.method, req.url);
  res.writeHead(200, { "Content-Type": "text/plain" });
  res.end("Hello from my server!\n");
});

server.listen(8000, () => {
  console.log("Listening on http://localhost:8000");
});

