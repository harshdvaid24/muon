// Safe by construction: never triggers a real workflow and never builds a real app.
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { startServer } from "./helpers.mjs";
import { matchSim, matchAvd } from "../dist/tools/dev.js";
import { startJob, readJob } from "../dist/jobs.js";

const SANDBOX = path.join(os.homedir(), "Work/Muon/.sandbox/dev");
let s;
before(async () => {
  await fs.rm(SANDBOX, { recursive: true, force: true });
  await fs.mkdir(path.join(SANDBOX, "plain"), { recursive: true });
  await fs.writeFile(path.join(SANDBOX, "plain/package.json"), JSON.stringify({ name: "plain", dependencies: { express: "4" } }));
  s = startServer(); await s.init();
});
after(async () => { s.close(); await fs.rm(SANDBOX, { recursive: true, force: true }); });

test("matchSim prefers exact, then booted prefix match", () => {
  const sims = [
    { name: "iPhone 17e", udid: "a", state: "Shutdown", runtime: "iOS 26.4" },
    { name: "iPhone 17 Pro", udid: "b", state: "Booted", runtime: "iOS 26.2" },
    { name: "iPhone 16e", udid: "c", state: "Shutdown", runtime: "iOS 26.2" },
  ];
  assert.equal(matchSim("iPhone 17", sims).name, "iPhone 17 Pro");
  assert.equal(matchSim("iphone 16e", sims).name, "iPhone 16e");
  assert.equal(matchSim("Galaxy S30", sims), undefined);
});

test("matchAvd normalizes AVD names", () => {
  assert.equal(matchAvd("Pixel 9", ["Medium_Phone_API_35", "Pixel_9_API_35"]), "Pixel_9_API_35");
  assert.equal(matchAvd("pixel 7", ["Pixel_9_API_35"]), undefined);
});

test("dev tools registered with the right risk levels", async () => {
  const by = Object.fromEntries((await s.call("tools/list")).result.tools.map((t) => [t.name, t]));
  for (const n of ["listDevices", "listWorkflows", "workflowRuns", "jobStatus"]) assert.equal(by[n]?.annotations?.readOnlyHint, true, n);
  assert.equal(by.runOnDevice.annotations.readOnlyHint, false);
  assert.equal(by.runOnDevice.annotations.destructiveHint, false);
  assert.equal(by.triggerWorkflow.annotations.destructiveHint, true);
});

test("runOnDevice refuses non-React-Native projects without starting a job", async () => {
  const r = await s.tool("runOnDevice", { project: path.join(SANDBOX, "plain"), platform: "ios", device: "iPhone 17" });
  assert.ok(r.isError && /not a React Native project/.test(r.text), r.text);
});

test("runOnDevice refuses protected paths", async () => {
  const r = await s.tool("runOnDevice", { project: "~/Library", platform: "ios", device: "iPhone 17" });
  assert.ok(r.isError && /protected/.test(r.text), r.text);
});

test("background jobs run detached, log output and record the result", async () => {
  const job = await startJob("unit test job", "test", SANDBOX, [{ bin: "node", args: ["-e", "console.log('hello from job')"] }], false);
  let j;
  for (let i = 0; i < 50; i++) { j = await readJob(job.id); if (j.status !== "running") break; await new Promise((r) => setTimeout(r, 200)); }
  assert.equal(j.status, "done");
  assert.match(await fs.readFile(j.log, "utf8"), /hello from job/);
  const failing = await startJob("failing job", "test", SANDBOX, [{ bin: "node", args: ["-e", "process.exit(3)"] }], false);
  for (let i = 0; i < 50; i++) { j = await readJob(failing.id); if (j.status !== "running") break; await new Promise((r) => setTimeout(r, 200)); }
  assert.equal(j.status, "failed"); assert.equal(j.code, 3);
  const st = await s.tool("jobStatus", { id: job.id });
  assert.match(st.text, /hello from job/);
});

test("jobs refuse binaries outside the allowlist", async () => {
  await assert.rejects(() => startJob("bad", "test", SANDBOX, [{ bin: "bash", args: ["-c", "echo x"] }], false), /not allowed/);
});

test("openTerminal starts only coding assistants, inside allowed folders", async () => {
  const by = Object.fromEntries((await s.call("tools/list")).result.tools.map((t) => [t.name, t]));
  assert.equal(by.openTerminal.annotations.readOnlyHint, false);
  assert.equal(by.openTerminal.annotations.destructiveHint, false);
  let r = await s.tool("openTerminal", { project: path.join(SANDBOX, "plain"), command: "rm -rf /" });
  assert.ok(r.isError && /only these can be started/.test(r.text), r.text);
  r = await s.tool("openTerminal", { project: "~/Library", command: "claude" });
  assert.ok(r.isError && /protected/.test(r.text), r.text);
});
