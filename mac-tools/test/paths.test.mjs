import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

const HOME = os.homedir();
const SANDBOX = path.join(HOME, "Work/MacAgent/.sandbox/paths");
let resolveAllowed, PathError;

before(async () => {
  await fs.rm(SANDBOX, { recursive: true, force: true });
  await fs.mkdir(SANDBOX, { recursive: true });
  await fs.writeFile(path.join(SANDBOX, "a.txt"), "hi");
  await fs.symlink(path.join(HOME, "Library"), path.join(SANDBOX, "escape-link"));
  ({ resolveAllowed, PathError } = await import("../dist/paths.js"));
});
after(async () => { await fs.rm(SANDBOX, { recursive: true, force: true }); });

const rejects = (p, opts) => assert.rejects(() => resolveAllowed(p, opts), (e) => e instanceof PathError);

test("existing file inside allowed root resolves to real path", async () => {
  assert.equal(await resolveAllowed(path.join(SANDBOX, "a.txt")), path.join(SANDBOX, "a.txt"));
});
test("tilde expansion works", async () => {
  assert.equal(await resolveAllowed("~/Work/MacAgent/.sandbox/paths/a.txt"), path.join(SANDBOX, "a.txt"));
});
test("allowed root itself is allowed", async () => {
  assert.equal(await resolveAllowed("~/Work"), path.join(HOME, "Work"));
});
test("dot-dot escape to ~/.ssh is rejected", async () => {
  await rejects(path.join(SANDBOX, "../../../../.ssh/id_ed25519"));
});
test("denied root ~/Library is rejected", async () => { await rejects("~/Library/Preferences"); });
test("system path /etc/hosts is rejected", async () => { await rejects("/etc/hosts"); });
test("symlink inside allowed root pointing at ~/Library is rejected", async () => {
  await rejects(path.join(SANDBOX, "escape-link/Preferences"));
});
test("new (non-existent) path in allowed dir resolves via parent", async () => {
  assert.equal(await resolveAllowed(path.join(SANDBOX, "new.txt")), path.join(SANDBOX, "new.txt"));
});
test("non-existent path with mustExist is rejected", async () => {
  await rejects(path.join(SANDBOX, "nope.txt"), { mustExist: true });
});
test("empty / whitespace path is rejected", async () => { await rejects("   "); });
test("path outside all roots (~/Movies) is rejected", async () => { await rejects("~/Movies"); });
test("new nested path (two missing levels) resolves via nearest existing ancestor", async () => {
  assert.equal(await resolveAllowed(path.join(SANDBOX, "new/deep/x.txt")), path.join(SANDBOX, "new/deep/x.txt"));
});
test("new nested path under denied root is still rejected", async () => { await rejects("~/Library/new/deep/x.txt"); });
