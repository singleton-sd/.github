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

const unquotedCssOnly = `<!doctype html><html><head><title>LeaseMate Test</title>
<link rel=stylesheet href=/app.css>
</head><body></body></html>`;

const unquotedJsOnly = `<!doctype html><html><head><title>LeaseMate Test</title>
<script src=/app.js></script>
</head><body></body></html>`;

const dualKindPage = `<!doctype html><html><head><title>LeaseMate Test</title>
<link rel="stylesheet" href="/dual">
<script src="/dual"></script>
</head><body></body></html>`;

const duplicateCssPage = `<!doctype html><html><head><title>LeaseMate Test</title>
<link rel="stylesheet" href="/app.css">
<link rel="stylesheet" href="/app.css">
<script src="/app.js"></script>
</head><body></body></html>`;

const dataSrcPage = `<!doctype html><html><head><title>LeaseMate Test</title>
<link rel="stylesheet" href="/app.css">
<script data-src="/placeholder.js" src="/app.js"></script>
</head><body></body></html>`;

function trackingHandler(inner) {
  const requested = [];
  return {
    requested,
    handler(req, res) {
      requested.push(req.url);
      inner(req, res);
    },
  };
}

function assetHandler(indexHtml, cssType = "text/css", jsType = "application/javascript", cssStatus = 200, jsStatus = 200) {
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
      res.writeHead(jsStatus, { "content-type": jsType });
      res.end(jsStatus === 200 && jsType.includes("javascript") ? "void 0;" : "<!doctype html><title>Page not found</title>");
      return;
    }
    if (req.url === "/dual") {
      res.writeHead(200, { "content-type": "text/css" });
      res.end("body{}");
      return;
    }
    if (req.url === "/placeholder.js") {
      res.writeHead(404, { "content-type": "text/html" });
      res.end("<!doctype html><title>Page not found</title>");
      return;
    }
    res.writeHead(404, { "content-type": "text/html" });
    res.end("<!doctype html><title>Page not found</title>");
  };
}

async function withServer(handler, fn) {
  const { server, origin } = await startServer(handler);
  try {
    return await fn(origin);
  } finally {
    server.close();
  }
}

test("quoted assets and matching title pass", async () => {
  await withServer(assetHandler(quotedPage), async (origin) => {
    const result = await runSmoke(["--url", `${origin}/`, "--expect-title", "LeaseMate", "--timeout-ms", "0"]);
    assert.equal(result.code, 0, result.stderr);
  });
});

test("unquoted stylesheet and script attributes are both fetched", async () => {
  const tracked = trackingHandler(assetHandler(unquotedPage));
  await withServer(tracked.handler, async (origin) => {
    const result = await runSmoke(["--url", `${origin}/`, "--expect-title", "LeaseMate", "--timeout-ms", "0"]);
    assert.equal(result.code, 0, result.stderr);
    assert.ok(tracked.requested.includes("/app.css"), `css not fetched: ${tracked.requested.join(",")}`);
    assert.ok(tracked.requested.includes("/app.js"), `js not fetched: ${tracked.requested.join(",")}`);
  });
});

test("unquoted CSS HTML 404 fails even when JS is valid", async () => {
  await withServer(assetHandler(unquotedPage, "text/html", "application/javascript", 404, 200), async (origin) => {
    const result = await runSmoke(["--url", `${origin}/`, "--expect-title", "LeaseMate", "--timeout-ms", "0"]);
    assert.notEqual(result.code, 0);
    assert.match(result.stderr, /FAIL:/);
  });
});

test("unquoted JS HTML 404 fails even when CSS is valid", async () => {
  await withServer(assetHandler(unquotedPage, "text/css", "text/html", 200, 404), async (origin) => {
    const result = await runSmoke(["--url", `${origin}/`, "--expect-title", "LeaseMate", "--timeout-ms", "0"]);
    assert.notEqual(result.code, 0);
    assert.match(result.stderr, /FAIL:/);
  });
});

test("unquoted CSS-only page still checks the stylesheet", async () => {
  await withServer(assetHandler(unquotedCssOnly, "text/html", "application/javascript", 404), async (origin) => {
    const result = await runSmoke(["--url", `${origin}/`, "--expect-title", "LeaseMate", "--timeout-ms", "0"]);
    assert.notEqual(result.code, 0);
    assert.match(result.stderr, /FAIL:/);
  });
});

test("unquoted JS-only page still checks the script", async () => {
  await withServer(assetHandler(unquotedJsOnly, "text/css", "text/html", 200, 404), async (origin) => {
    const result = await runSmoke(["--url", `${origin}/`, "--expect-title", "LeaseMate", "--timeout-ms", "0"]);
    assert.notEqual(result.code, 0);
    assert.match(result.stderr, /FAIL:/);
  });
});

test("same URL as stylesheet and script keeps both kind checks", async () => {
  await withServer(assetHandler(dualKindPage), async (origin) => {
    const result = await runSmoke(["--url", `${origin}/`, "--expect-title", "LeaseMate", "--timeout-ms", "0"]);
    assert.notEqual(result.code, 0, "script MIME check must still run when the URL is also a stylesheet");
    assert.match(result.stderr, /script/i);
  });
});

test("same-kind duplicate assets are fetched once", async () => {
  const tracked = trackingHandler(assetHandler(duplicateCssPage));
  await withServer(tracked.handler, async (origin) => {
    const result = await runSmoke(["--url", `${origin}/`, "--expect-title", "LeaseMate", "--timeout-ms", "0"]);
    assert.equal(result.code, 0, result.stderr);
    const cssHits = tracked.requested.filter((u) => u === "/app.css").length;
    assert.equal(cssHits, 1, `duplicate stylesheet fetched ${cssHits} times`);
  });
});

test("data-src does not override src", async () => {
  const tracked = trackingHandler(assetHandler(dataSrcPage));
  await withServer(tracked.handler, async (origin) => {
    const result = await runSmoke(["--url", `${origin}/`, "--expect-title", "LeaseMate", "--timeout-ms", "0"]);
    assert.equal(result.code, 0, result.stderr);
    assert.ok(tracked.requested.includes("/app.js"), `real src not fetched: ${tracked.requested.join(",")}`);
    assert.ok(!tracked.requested.includes("/placeholder.js"), "data-src placeholder must not be fetched as the script");
  });
});

test("CSS asset returning HTML 404 fails", async () => {
  await withServer(assetHandler(quotedPage, "text/html", "application/javascript", 404), async (origin) => {
    const result = await runSmoke(["--url", `${origin}/`, "--expect-title", "LeaseMate", "--timeout-ms", "0"]);
    assert.notEqual(result.code, 0);
    assert.match(result.stderr, /FAIL:/);
  });
});

test("title mismatch fails", async () => {
  await withServer(assetHandler(quotedPage), async (origin) => {
    const result = await runSmoke(["--url", `${origin}/`, "--expect-title", "InkAds", "--timeout-ms", "0"]);
    assert.notEqual(result.code, 0);
    assert.match(result.stderr, /does not contain/);
  });
});
