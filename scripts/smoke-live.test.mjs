#!/usr/bin/env node
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createServer } from "node:http";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const script = join(dirname(fileURLToPath(import.meta.url)), "smoke-live.mjs");

function startServer(handler) {
  return new Promise((resolve) => {
    const server = createServer(handler);
    server.listen(0, "127.0.0.1", () => {
      const { port } = server.address();
      resolve({ server, origin: `http://127.0.0.1:${port}` });
    });
  });
}

function runSmoke(args) {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, [script, ...args], {
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => {
      stdout += chunk;
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk;
    });
    child.on("close", (code) => resolve({ code, stdout, stderr }));
  });
}

const quotedPage = `<!doctype html><html><head><title>LeaseMate Test</title>
<link rel="stylesheet" href="/app.css">
<script src="/app.js"></script>
</head><body></body></html>`;

const unquotedPage = `<!doctype html><html><head><title>LeaseMate Test</title>
<link rel=stylesheet href=/app.css>
<script src=/app.js></script>
</head><body></body></html>`;

function assetHandler(indexHtml, cssType = "text/css", jsType = "application/javascript", cssStatus = 200) {
  return (req, res) => {
    if (req.url === "/" || req.url === "/index.html") {
      res.writeHead(200, { "content-type": "text/html" });
      res.end(indexHtml);
      return;
    }
    if (req.url === "/app.css") {
      res.writeHead(cssStatus, { "content-type": cssType });
      res.end(cssStatus === 200 && cssType === "text/css" ? "body{}" : "<!doctype html><title>Page not found</title>");
      return;
    }
    if (req.url === "/app.js") {
      res.writeHead(200, { "content-type": jsType });
      res.end("void 0;");
      return;
    }
    res.writeHead(404, { "content-type": "text/html" });
    res.end("<!doctype html><title>Page not found</title>");
  };
}

test("quoted assets and matching title pass", async () => {
  const { server, origin } = await startServer(assetHandler(quotedPage));
  try {
    const result = await runSmoke([
      "--url",
      `${origin}/`,
      "--expect-title",
      "LeaseMate",
      "--timeout-ms",
      "0",
    ]);
    assert.equal(result.code, 0, result.stderr);
  } finally {
    server.close();
  }
});

test("unquoted stylesheet and script attributes are checked", async () => {
  const { server, origin } = await startServer(assetHandler(unquotedPage));
  try {
    const result = await runSmoke([
      "--url",
      `${origin}/`,
      "--expect-title",
      "LeaseMate",
      "--timeout-ms",
      "0",
    ]);
    assert.equal(result.code, 0, result.stderr);
  } finally {
    server.close();
  }
});

test("CSS asset returning HTML 404 fails", async () => {
  const { server, origin } = await startServer(
    assetHandler(quotedPage, "text/html", "application/javascript", 404),
  );
  try {
    const result = await runSmoke([
      "--url",
      `${origin}/`,
      "--expect-title",
      "LeaseMate",
      "--timeout-ms",
      "0",
    ]);
    assert.notEqual(result.code, 0);
    assert.match(result.stderr, /FAIL:/);
  } finally {
    server.close();
  }
});

test("title mismatch fails", async () => {
  const { server, origin } = await startServer(assetHandler(quotedPage));
  try {
    const result = await runSmoke([
      "--url",
      `${origin}/`,
      "--expect-title",
      "InkAds",
      "--timeout-ms",
      "0",
    ]);
    assert.notEqual(result.code, 0);
    assert.match(result.stderr, /does not contain/);
  } finally {
    server.close();
  }
});
