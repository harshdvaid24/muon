import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import { startServer } from "./helpers.mjs";

const SANDBOX = path.join(os.homedir(), "Work/Muon/.sandbox/fileops");
let s;
before(async () => {
  await fs.rm(SANDBOX, { recursive: true, force: true });
  await fs.mkdir(path.join(SANDBOX, "dest"), { recursive: true });
  for (const n of ["a.txt", "b.txt", "c.txt", "t.txt"]) await fs.writeFile(path.join(SANDBOX, n), n);
  s = startServer(); await s.init();
});
after(async () => { s.close(); await fs.rm(SANDBOX, { recursive: true, force: true }); });
const exists = async (p) => !!(await fs.stat(p).catch(() => null));

test("mutating tools registered with correct annotations", async () => {
  const by = Object.fromEntries((await s.call("tools/list")).result.tools.map((t) => [t.name, t]));
  for (const n of ["moveItems", "copyItems", "renameItem", "createFolder", "trashItems", "quitApplication"]) {
    assert.equal(by[n]?.annotations?.readOnlyHint, false, n); assert.equal(by[n]?.annotations?.destructiveHint, false, n);
  }
  assert.equal(by.killProcess.annotations.destructiveHint, true);
});
test("createFolder + moveItems + no overwrite", async () => {
  const r1 = await s.tool("createFolder", { path: path.join(SANDBOX, "new/deep") });
  assert.ok(await exists(path.join(SANDBOX, "new/deep")), r1.text);
  const r2 = await s.tool("moveItems", { paths: [path.join(SANDBOX, "a.txt")], destinationFolder: path.join(SANDBOX, "dest") });
  assert.match(r2.text, /^1\/1 moved/);
  assert.ok(await exists(path.join(SANDBOX, "dest/a.txt")) && !(await exists(path.join(SANDBOX, "a.txt"))));
  await fs.writeFile(path.join(SANDBOX, "a.txt"), "again");
  const r3 = await s.tool("moveItems", { paths: [path.join(SANDBOX, "a.txt")], destinationFolder: path.join(SANDBOX, "dest") });
  assert.match(r3.text, /^0\/1 moved[\s\S]*already exists/);
});
test("copyItems keeps source", async () => {
  const r = await s.tool("copyItems", { paths: [path.join(SANDBOX, "b.txt")], destinationFolder: path.join(SANDBOX, "dest") });
  assert.match(r.text, /^1\/1 copied/);
  assert.ok((await exists(path.join(SANDBOX, "b.txt"))) && (await exists(path.join(SANDBOX, "dest/b.txt"))));
});
test("renameItem in place; rejects slashes", async () => {
  await s.tool("renameItem", { path: path.join(SANDBOX, "c.txt"), newName: "c2.txt" });
  assert.ok(await exists(path.join(SANDBOX, "c2.txt")));
  const bad = await s.tool("renameItem", { path: path.join(SANDBOX, "c2.txt"), newName: "../x.txt" });
  assert.ok(bad.isError && /plain name/.test(bad.text));
});
test("destination outside allowed roots is rejected", async () => {
  const r = await s.tool("moveItems", { paths: [path.join(SANDBOX, "b.txt")], destinationFolder: "/tmp" });
  assert.ok(r.isError && /protected|outside/.test(r.text));
  assert.ok(await exists(path.join(SANDBOX, "b.txt")));
});
test("trashItems removes from folder via /usr/bin/trash", async () => {
  const r = await s.tool("trashItems", { paths: [path.join(SANDBOX, "t.txt")] });
  assert.match(r.text, /Moved 1 item\(s\) to Trash/);
  assert.equal(await exists(path.join(SANDBOX, "t.txt")), false);
});
test("killProcess terminates an owned process, refuses pid 1", async () => {
  const child = spawn("sleep", ["60"]);
  const exited = new Promise((res) => child.on("exit", (code, sig) => res(sig)));
  const r = await s.tool("killProcess", { pid: child.pid });
  assert.match(r.text, /SIGTERM/);
  assert.equal(await exited, "SIGTERM");
  const bad = await s.tool("killProcess", { pid: 1 }).catch((e) => ({ isError: true, text: e.message }));
  assert.ok(bad.isError);
});
test("quitApplication rejects unsafe names without running osascript", async () => {
  const r = await s.tool("quitApplication", { name: 'Finder" to quit\nsay "x' }).catch((e) => ({ isError: true, text: e.message }));
  assert.ok(r.isError);
});

// --- review fix pass ---
test("mutating tools refuse symlinks (act on the link path the user sees, never the target)", async () => {
  await fs.mkdir(path.join(SANDBOX, "real-target"), { recursive: true });
  await fs.symlink(path.join(SANDBOX, "real-target"), path.join(SANDBOX, "link"));
  const mv = await s.tool("moveItems", { paths: [path.join(SANDBOX, "link")], destinationFolder: path.join(SANDBOX, "dest") });
  assert.match(mv.text, /^0\/1 moved[\s\S]*symlink/);
  assert.ok(await exists(path.join(SANDBOX, "real-target")));
  const tr = await s.tool("trashItems", { paths: [path.join(SANDBOX, "link")] });
  assert.ok(tr.isError && /symlink/.test(tr.text));
  const rn = await s.tool("renameItem", { path: path.join(SANDBOX, "link"), newName: "link2" });
  assert.ok(rn.isError && /symlink/.test(rn.text));
});
test("mutating tools refuse an allowed root itself (sandboxed roots — never real folders)", async () => {
  // A dedicated server whose ONLY allowed root is a throwaway folder: if the refusal ever regresses,
  // the worst case is trashing this sandbox, never the user's real folders.
  const ROOT = path.join(SANDBOX, "fake-root");
  await fs.mkdir(path.join(ROOT, "dest"), { recursive: true });
  const s2 = startServer({ MUON_ALLOWED_ROOTS: ROOT });
  try {
    await s2.init();
    const r = await s2.tool("trashItems", { paths: [ROOT] });
    assert.ok(r.isError && /root/.test(r.text), r.text);
    const m = await s2.tool("moveItems", { paths: [ROOT], destinationFolder: path.join(ROOT, "dest") });
    assert.match(m.text, /^0\/1 moved[\s\S]*root/);
    assert.ok(await exists(ROOT));
  } finally { s2.close(); }
});

test("moveItems refuses moving a folder into itself", async () => {
  await fs.mkdir(path.join(SANDBOX, "parent/Archive"), { recursive: true });
  const r = await s.tool("moveItems", { paths: [path.join(SANDBOX, "parent")], destinationFolder: path.join(SANDBOX, "parent/Archive") });
  assert.match(r.text, /^0\/1 moved[\s\S]*into itself/);
});

test("writeTextFile writes, refuses overwrite and scripts, honors path policy", async () => {
  const f = path.join(SANDBOX, "notes/summary.md");
  const r = await s.tool("writeTextFile", { path: f, content: "# Summary\nhello" });
  assert.match(r.text, /Wrote/);
  assert.equal(await fs.readFile(f, "utf8"), "# Summary\nhello");
  const again = await s.tool("writeTextFile", { path: f, content: "x" });
  assert.ok(again.isError && /already exists/.test(again.text));
  const over = await s.tool("writeTextFile", { path: f, content: "y", overwrite: true });
  assert.ok(!over.isError); assert.equal(await fs.readFile(f, "utf8"), "y");
  const sh = await s.tool("writeTextFile", { path: path.join(SANDBOX, "run.sh"), content: "echo hi" });
  assert.ok(sh.isError && /script/.test(sh.text));
  const lib = await s.tool("writeTextFile", { path: "~/Library/x.txt", content: "z" });
  assert.ok(lib.isError && /protected/.test(lib.text));
});
