import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { startServer } from "./helpers.mjs";

const SANDBOX = path.join(os.homedir(), "Work/Muon/.sandbox/tools");
let s;
before(async () => {
  await fs.rm(SANDBOX, { recursive: true, force: true });
  await fs.mkdir(path.join(SANDBOX, "sub"), { recursive: true });
  await fs.writeFile(path.join(SANDBOX, "hello.txt"), "hello world\n");
  await fs.writeFile(path.join(SANDBOX, "bin.dat"), Buffer.from([0, 1, 2, 3]));
  s = startServer(); await s.init();
});
after(async () => { s.close(); await fs.rm(SANDBOX, { recursive: true, force: true }); });

test("all phase-1 tools registered with annotations", async () => {
  const list = await s.call("tools/list");
  const by = Object.fromEntries(list.result.tools.map((t) => [t.name, t]));
  for (const n of ["searchFiles", "findFiles", "searchCode", "readFile", "listDirectory", "listProjects", "listRunningApps", "getSystemStats"])
    assert.equal(by[n]?.annotations?.readOnlyHint, true, `${n} readOnly`);
  for (const n of ["openApplication", "openPath", "revealInFinder"]) {
    assert.ok(by[n], n); assert.equal(by[n].annotations.readOnlyHint, false); assert.equal(by[n].annotations.destructiveHint, false);
  }
});
test("readFile reads text, rejects binary and protected paths", async () => {
  assert.equal((await s.tool("readFile", { path: path.join(SANDBOX, "hello.txt") })).text, "hello world\n");
  const bin = await s.tool("readFile", { path: path.join(SANDBOX, "bin.dat") });
  assert.ok(bin.isError && /binary/.test(bin.text));
  const lib = await s.tool("readFile", { path: "~/Library/Preferences/.GlobalPreferences.plist" });
  assert.ok(lib.isError && /protected/.test(lib.text));
});
test("listDirectory lists dirs first", async () => {
  const r = await s.tool("listDirectory", { path: SANDBOX });
  assert.match(r.text, /sub\/\nbin\.dat/);
});
test("searchCode finds text with rg", async () => {
  const r = await s.tool("searchCode", { pattern: "hello world", scope: SANDBOX });
  assert.match(r.text, /hello\.txt:1:hello world/);
});
test("findFiles finds by name (rg fallback works even before Spotlight indexes)", async () => {
  const r = await s.tool("findFiles", { name: "hello", scope: SANDBOX });
  assert.match(r.text, /hello\.txt/);
});
test("listProjects includes Muon", async () => {
  const r = await s.tool("listProjects");
  assert.match(r.text, /~\/Work\/Muon\t/i);   // on-disk case may differ (CI: ~/work)
});
test("getSystemStats and listRunningApps return data", async () => {
  assert.match((await s.tool("getSystemStats")).text, /RAM: \d+ GB total/);
  assert.match((await s.tool("listRunningApps")).text, /\d+ MB\s+\S/);   // at least one app (CI runners differ)
});
test("openPath outside roots is rejected without running open", async () => {
  const r = await s.tool("openPath", { path: "/etc" });
  assert.ok(r.isError && /protected/.test(r.text));
});
test("audit log written", async () => {
  const log = await fs.readFile(path.join(os.homedir(), "Library/Application Support/Muon/audit.jsonl"), "utf8");
  assert.ok(log.split("\n").some((l) => l.includes('"tool":"readFile"')));
});

// --- review fix pass ---
test("openPath refuses executables, app bundles and terminal apps", async () => {
  await fs.writeFile(path.join(SANDBOX, "deploy.sh"), "#!/bin/sh\necho hi\n", { mode: 0o755 });
  await fs.mkdir(path.join(SANDBOX, "Fake.app/Contents/MacOS"), { recursive: true });
  await fs.writeFile(path.join(SANDBOX, "notes.command"), "echo hi\n");
  const sh = await s.tool("openPath", { path: path.join(SANDBOX, "deploy.sh") });
  assert.ok(sh.isError && /executable/.test(sh.text), sh.text);
  const app = await s.tool("openPath", { path: path.join(SANDBOX, "Fake.app") });
  assert.ok(app.isError && /app bundle/.test(app.text), app.text);
  const cmd = await s.tool("openPath", { path: path.join(SANDBOX, "notes.command") });
  assert.ok(cmd.isError && /executable/.test(cmd.text), cmd.text);
  const term = await s.tool("openPath", { path: path.join(SANDBOX, "hello.txt"), app: "Terminal" });
  assert.ok(term.isError && /terminal/i.test(term.text), term.text);
  const list = await s.call("tools/list");
  assert.match(list.result.tools.find((t) => t.name === "openPath").description, /never runs executables/i);
});

test("allowed roots match by real path, so a root spelled in different case still works (APFS is case-insensitive)", async () => {
  const root = path.join(SANDBOX, "caseroot");
  await fs.mkdir(root, { recursive: true });
  await fs.writeFile(path.join(root, "f.txt"), "case ok\n");
  const s2 = startServer({ MUON_ALLOWED_ROOTS: root.toUpperCase() });   // configured in a different case than on disk
  try {
    await s2.init();
    const r = await s2.tool("readFile", { path: path.join(root, "f.txt") });
    assert.equal(r.isError, false, r.text);
    assert.equal(r.text, "case ok\n");
  } finally { s2.close(); }
});
