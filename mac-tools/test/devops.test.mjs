import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import http from "node:http";
import { execFileSync } from "node:child_process";
import { startServer } from "./helpers.mjs";
import { htmlToText } from "../dist/tools/devops.js";

const SANDBOX = path.join(os.homedir(), "Work/Muon/.sandbox/devops");
let s, web;
before(async () => {
  await fs.rm(SANDBOX, { recursive: true, force: true });
  await fs.mkdir(path.join(SANDBOX, "repo/node_modules/.cache"), { recursive: true });
  await fs.writeFile(path.join(SANDBOX, "repo/node_modules/.cache/x"), "x");
  execFileSync("git", ["-C", path.join(SANDBOX, "repo"), "init", "-q"]);
  execFileSync("git", ["-C", path.join(SANDBOX, "repo"), "config", "user.email", "t@example.com"]);
  execFileSync("git", ["-C", path.join(SANDBOX, "repo"), "config", "user.name", "T"]);
  await fs.writeFile(path.join(SANDBOX, "repo/a.txt"), "hello\n");
  web = http.createServer((req, res) => { res.setHeader("content-type", "text/html"); res.end("<html><head><title>Muon Test Page</title><style>p{}</style></head><body><nav>skip</nav><h1>Hello</h1><p>Body &amp; text</p><script>bad()</script></body></html>"); });
  await new Promise((r) => web.listen(0, "127.0.0.1", r));
  s = startServer(); await s.init();
});
after(async () => { s.close(); web.close(); await fs.rm(SANDBOX, { recursive: true, force: true }); });

test("htmlToText strips scripts, styles, nav and tags", () => {
  const t = htmlToText("<html><nav>menu</nav><h1>Title</h1><script>x()</script><p>a &amp; b</p></html>");
  assert.equal(t.includes("menu"), false); assert.equal(t.includes("x()"), false); assert.match(t, /Title\s+a & b/);
});
test("readWebPage returns title and text", async () => {
  const r = await s.tool("readWebPage", { url: `http://127.0.0.1:${web.address().port}/` });
  assert.match(r.text, /^Muon Test Page/); assert.match(r.text, /Hello\s+Body & text/); assert.ok(!r.text.includes("bad()"));
});
test("git status → commit → status clean; diff before commit", async () => {
  const repo = path.join(SANDBOX, "repo");
  const st = await s.tool("gitStatus", { project: repo });
  assert.match(st.text, /a\.txt/);
  const d = await s.tool("gitDiff", { project: repo });
  assert.match(d.text, /untracked:[\s\S]*a\.txt/);
  const c = await s.tool("gitCommit", { project: repo, message: "test: add a" });
  assert.match(c.text, /Committed [0-9a-f]{7}: test: add a/);
  assert.equal((await s.tool("gitStatus", { project: repo })).text.split("\n").length, 1);   // branch line only
});
test("git tools refuse non-repos and protected paths", async () => {
  // ~/Work itself is not a repo (the sandbox is inside the Muon repo, so it can't be used for this)
  const norepo = path.join(os.homedir(), "Work/.muon-test-norepo");
  await fs.mkdir(norepo, { recursive: true });
  try {
    const r = await s.tool("gitStatus", { project: norepo });
    assert.ok(r.isError && /not a git repository/.test(r.text), r.text);   // either "not a repo" or "enclosing repo won't be touched"
  } finally { await fs.rm(norepo, { recursive: true, force: true }); }
  const p = await s.tool("gitCommit", { project: "~/Library", message: "test message" });
  assert.ok(p.isError && /protected/.test(p.text));
});
test("cleanDevCaches removes node_modules/.cache only", async () => {
  const repo = path.join(SANDBOX, "repo");
  const r = await s.tool("cleanDevCaches", { project: repo });
  assert.match(r.text, /removed node_modules\/\.cache/);
  assert.ok(await fs.stat(path.join(repo, "a.txt")));
});
test("adbPair / installApp validate input before touching devices", async () => {
  const bad = await s.tool("adbPair", { address: "not-an-address", code: "12" }).catch((e) => ({ isError: true, text: e.message }));
  assert.ok(bad.isError);
  const notApk = await s.tool("installApp", { path: path.join(SANDBOX, "repo/a.txt") });
  assert.ok(notApk.isError && /\.apk|\.app/.test(notApk.text));
});
test("buildAndroidRelease refuses projects without gradlew", async () => {
  const r = await s.tool("buildAndroidRelease", { project: path.join(SANDBOX, "repo") });
  assert.ok(r.isError && /gradlew/.test(r.text));
});
