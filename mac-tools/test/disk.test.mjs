import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { startServer } from "./helpers.mjs";

const SANDBOX = path.join(os.homedir(), "Work/Muon/.sandbox/disk");
let s;
before(async () => {
  await fs.rm(SANDBOX, { recursive: true, force: true });
  await fs.mkdir(path.join(SANDBOX, "a/node_modules"), { recursive: true });
  await fs.writeFile(path.join(SANDBOX, "big.bin"), Buffer.alloc(300 * 1024, 1));
  await fs.writeFile(path.join(SANDBOX, "small.txt"), "x");
  await fs.writeFile(path.join(SANDBOX, "a/copy1.zip"), Buffer.alloc(50 * 1024, 7));
  await fs.writeFile(path.join(SANDBOX, "copy2.zip"), Buffer.alloc(50 * 1024, 7));      // duplicate of copy1
  await fs.writeFile(path.join(SANDBOX, "diff.zip"), Buffer.alloc(50 * 1024, 8));       // same size, different content
  await fs.writeFile(path.join(SANDBOX, "a/node_modules/huge.bin"), Buffer.alloc(900 * 1024, 1)); // must be skipped
  s = startServer(); await s.init();
});
after(async () => { s.close(); await fs.rm(SANDBOX, { recursive: true, force: true }); });

test("largestFiles sorts by size and skips node_modules", async () => {
  const r = await s.tool("largestFiles", { path: SANDBOX, limit: 3 });
  const lines = r.text.split("\n").slice(1);
  assert.match(lines[0], /big\.bin/);
  assert.ok(!r.text.includes("huge.bin"), r.text);
});
test("findDuplicates groups identical content only", async () => {
  const r = await s.tool("findDuplicates", { path: SANDBOX });
  assert.match(r.text, /1 duplicate set/);
  assert.match(r.text, /copy1\.zip/); assert.match(r.text, /copy2\.zip/);
  assert.ok(!r.text.includes("diff.zip"), r.text);
});
test("disk tools refuse protected folders", async () => {
  const r = await s.tool("largestFiles", { path: "~/Library" });
  assert.ok(r.isError && /protected/.test(r.text));
});

test("matchFiles filters by kind, name and age", async () => {
  const dir = path.join(SANDBOX, "m");
  await fs.mkdir(dir, { recursive: true });
  for (const n of ["Screenshot 2026-01-01 at 1.png", "Screenshot 2026-01-02 at 2.png", "photo.jpg", "invoice.pdf", "build.zip"]) await fs.writeFile(path.join(dir, n), "x");
  const old = new Date(Date.now() - 40 * 86400000);
  await fs.utimes(path.join(dir, "Screenshot 2026-01-01 at 1.png"), old, old);
  const shots = await s.tool("matchFiles", { folder: dir, kind: "screenshots" });
  assert.equal(shots.text.split("\n").length, 2);
  const oldShots = await s.tool("matchFiles", { folder: dir, kind: "screenshots", olderThanDays: 30 });
  assert.match(oldShots.text, /2026-01-01/); assert.ok(!oldShots.text.includes("2026-01-02"));
  const images = await s.tool("matchFiles", { folder: dir, kind: "images" });
  assert.equal(images.text.split("\n").length, 3);   // 2 png + 1 jpg
  assert.match((await s.tool("matchFiles", { folder: dir, kind: "pdfs" })).text, /invoice\.pdf/);
});
