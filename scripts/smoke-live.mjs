#!/usr/bin/env node
/**
 * Live GitHub Pages smoke check. No dependencies.
 *
 * Fetches a URL, asserts HTTP 200, HTML content-type, and that the document
 * contains an expected <title> substring and/or a root HTML needle (so a
 * cached GitHub Pages 404 page cannot pass). Then every stylesheet and
 * script href must return 200 with a CSS or JavaScript content-type — not
 * the HTML 404 page Jekyll serves for hidden /_astro/ assets.
 *
 * Retries until --timeout-ms (default 5 minutes) so Pages CDN propagation
 * does not fail the job spuriously.
 *
 * Usage:
 *   node scripts/smoke-live.mjs --url https://example.com/ --expect-title "Example"
 *   node scripts/smoke-live.mjs --url https://example.com/pr-preview/pr-2/ \
 *     --expect-title "Example" --expect-root "data-site" --timeout-ms 300000
 */

import { setTimeout as delay } from "node:timers/promises";

const CSS_TYPES = ["text/css"];
const JS_TYPES = [
  "text/javascript",
  "application/javascript",
  "application/x-javascript",
  "application/ecmascript",
  "text/ecmascript",
];

function parseArgs(argv) {
  const args = {
    url: null,
    expectTitle: null,
    expectRoot: null,
    timeoutMs: 5 * 60 * 1000,
    intervalMs: 10 * 1000,
    fetchTimeoutMs: 20 * 1000,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const key = argv[i];
    const val = argv[i + 1];
    switch (key) {
      case "--url":
        args.url = val;
        i += 1;
        break;
      case "--expect-title":
        args.expectTitle = val;
        i += 1;
        break;
      case "--expect-root":
        args.expectRoot = val;
        i += 1;
        break;
      case "--timeout-ms":
        args.timeoutMs = Number(val);
        i += 1;
        break;
      case "--interval-ms":
        args.intervalMs = Number(val);
        i += 1;
        break;
      case "--fetch-timeout-ms":
        args.fetchTimeoutMs = Number(val);
        i += 1;
        break;
      case "-h":
      case "--help":
        args.help = true;
        break;
      default:
        throw new Error(`Unknown argument: ${key}`);
    }
  }
  return args;
}

function mime(contentType) {
  return (contentType || "").split(";")[0].trim().toLowerCase();
}

function decodeEntities(text) {
  return text
    .replace(/&middot;/gi, "·")
    .replace(/&amp;/gi, "&")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;|&apos;/gi, "'")
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n)))
    .replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCodePoint(parseInt(n, 16)));
}

function extractTitle(html) {
  const m = html.match(/<title[^>]*>([\s\S]*?)<\/title>/i);
  return m ? decodeEntities(m[1]).replace(/\s+/g, " ").trim() : "";
}

function htmlAttr(tag, name) {
  const quoted = tag.match(new RegExp(`\\b${name}\\s*=\\s*(["'])([\\s\\S]*?)\\1`, "i"));
  if (quoted) return quoted[2];
  const unquoted = tag.match(new RegExp(`\\b${name}\\s*=\\s*([^\\s"'=<>\`]+)`, "i"));
  return unquoted ? unquoted[1] : "";
}

function extractAssets(html, baseUrl) {
  const assets = [];
  const linkRe = /<link\b[^>]*>/gi;
  let m;
  while ((m = linkRe.exec(html))) {
    const tag = m[0];
    const rel = htmlAttr(tag, "rel");
    const href = htmlAttr(tag, "href");
    if (href && rel.split(/\s+/).some((r) => r.toLowerCase() === "stylesheet")) {
      assets.push({ kind: "stylesheet", url: new URL(href, baseUrl).href });
    }
  }
  const scriptRe = /<script\b[^>]*>/gi;
  while ((m = scriptRe.exec(html))) {
    const tag = m[0];
    const src = htmlAttr(tag, "src");
    if (src) assets.push({ kind: "script", url: new URL(src, baseUrl).href });
  }
  const seen = new Set();
  return assets.filter((a) => {
    const key = `${a.kind} ${a.url}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return a.url.startsWith("http://") || a.url.startsWith("https://");
  });
}

async function fetchBuffer(url, fetchTimeoutMs) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), fetchTimeoutMs);
  try {
    const res = await fetch(url, {
      redirect: "follow",
      signal: controller.signal,
      headers: { "user-agent": "singleton-sd-pages-smoke/1.0" },
    });
    const buf = Buffer.from(await res.arrayBuffer());
    return {
      status: res.status,
      contentType: res.headers.get("content-type") || "",
      body: buf,
      finalUrl: res.url,
    };
  } finally {
    clearTimeout(timer);
  }
}

function typeOk(kind, contentType) {
  const type = mime(contentType);
  if (kind === "stylesheet") return CSS_TYPES.includes(type);
  if (kind === "script") return JS_TYPES.includes(type);
  return false;
}

function looksLikeHtml(contentType, peek) {
  if (mime(contentType).includes("html")) return true;
  const start = peek.toString("utf8", 0, 200).trimStart().toLowerCase();
  return start.startsWith("<!doctype html") || start.startsWith("<html");
}

async function runOnce(args) {
  const failures = [];
  const index = await fetchBuffer(args.url, args.fetchTimeoutMs);
  const html = index.body.toString("utf8");
  const title = extractTitle(html);
  console.log(
    `index ${index.status} ${mime(index.contentType) || "(no content-type)"} ${index.finalUrl} title=${JSON.stringify(title)} bytes=${index.body.length}`,
  );

  if (index.status !== 200) {
    failures.push(`index returned HTTP ${index.status}, expected 200`);
  }
  if (!mime(index.contentType).includes("html")) {
    failures.push(`index content-type was ${index.contentType || "(missing)"}, expected text/html`);
  }

  if (!args.expectTitle && !args.expectRoot) {
    failures.push("pass --expect-title and/or --expect-root so a cached 404 page cannot pass");
  }
  if (args.expectTitle) {
    if (!title.toLowerCase().includes(args.expectTitle.toLowerCase())) {
      failures.push(
        `index title ${JSON.stringify(title)} does not contain ${JSON.stringify(args.expectTitle)}`,
      );
    }
    // Guard against the GitHub Pages 404 document even if the caller title is loose.
    if (/page not found/i.test(title) && !/page not found/i.test(args.expectTitle)) {
      failures.push(`index looks like the GitHub Pages 404 document (title ${JSON.stringify(title)})`);
    }
  }
  if (args.expectRoot && !html.includes(args.expectRoot)) {
    failures.push(`index HTML does not contain root needle ${JSON.stringify(args.expectRoot)}`);
  }

  if (failures.length) return failures;

  const assets = extractAssets(html, index.finalUrl || args.url);
  if (assets.length === 0) {
    failures.push("index HTML has no stylesheet or script hrefs to check");
    return failures;
  }

  for (const asset of assets) {
    const res = await fetchBuffer(asset.url, args.fetchTimeoutMs);
    const peek = res.body.subarray(0, 80);
    const okType = typeOk(asset.kind, res.contentType);
    const htmlBody = looksLikeHtml(res.contentType, peek);
    console.log(
      `  ${asset.kind} ${res.status} ${mime(res.contentType) || "(no content-type)"} ${asset.url} bytes=${res.body.length}`,
    );
    if (res.status !== 200) {
      failures.push(`${asset.kind} ${asset.url} returned HTTP ${res.status}, expected 200`);
    } else if (htmlBody || !okType) {
      failures.push(
        `${asset.kind} ${asset.url} content-type was ${res.contentType || "(missing)"}, expected ${asset.kind === "stylesheet" ? "text/css" : "javascript"} (HTML 404 bodies fail this check)`,
      );
    }
  }
  return failures;
}

async function main() {
  let args;
  try {
    args = parseArgs(process.argv.slice(2));
  } catch (err) {
    console.error(err.message);
    process.exit(2);
  }
  if (args.help) {
    console.log(`Usage: node scripts/smoke-live.mjs --url URL --expect-title TEXT [--expect-root NEEDLE]
  --timeout-ms 300000   total retry budget (default 5 minutes)
  --interval-ms 10000   wait between attempts
  --fetch-timeout-ms 20000`);
    process.exit(0);
  }
  if (!args.url) {
    console.error("Missing --url");
    process.exit(2);
  }
  if (!args.expectTitle && !args.expectRoot) {
    console.error("Missing --expect-title or --expect-root");
    process.exit(2);
  }
  if (!Number.isFinite(args.timeoutMs) || args.timeoutMs < 0) {
    console.error("Invalid --timeout-ms");
    process.exit(2);
  }

  const deadline = Date.now() + args.timeoutMs;
  let attempt = 0;
  let lastFailures = [];
  while (true) {
    attempt += 1;
    console.log(`\n== attempt ${attempt} ${new Date().toISOString()} ==`);
    try {
      lastFailures = await runOnce(args);
    } catch (err) {
      lastFailures = [`fetch error: ${err.name}: ${err.message}`];
      console.error(lastFailures[0]);
    }
    if (lastFailures.length === 0) {
      console.log("smoke-live: PASS");
      process.exit(0);
    }
    for (const failure of lastFailures) console.error(`FAIL: ${failure}`);
    const remaining = deadline - Date.now();
    if (remaining <= 0) break;
    const wait = Math.min(args.intervalMs, remaining);
    console.error(`retrying in ${wait}ms (${remaining}ms left)`);
    await delay(wait);
  }
  console.error(`smoke-live: FAIL after ${attempt} attempt(s)`);
  process.exit(1);
}

await main();
