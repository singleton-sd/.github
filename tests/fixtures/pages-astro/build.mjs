import { mkdirSync, writeFileSync } from "node:fs";

mkdirSync("dist", { recursive: true });
writeFileSync(
  "dist/index.html",
  `<!doctype html><html><head><title>Fixture</title></head><body><h1>pages-astro fixture</h1></body></html>\n`,
);
writeFileSync("dist/.nojekyll", "");
