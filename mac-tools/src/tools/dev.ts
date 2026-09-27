// Developer workflows: run React Native apps on iOS/Android devices and drive GitHub Actions.
// Long work runs as background jobs with notifications.
import fs from "node:fs";
import fsp from "node:fs/promises";
import path from "node:path";
import { execFile } from "node:child_process";
import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { defineTool } from "../define.js";
import { resolveAllowed, display } from "../paths.js";
import { startJob, listJobs, readJob, tail, jobEnv, ANDROID, type Step } from "../jobs.js";

const XCRUN = "/usr/bin/xcrun";
const EMULATOR = path.join(ANDROID, "emulator/emulator");
const ADB = path.join(ANDROID, "platform-tools/adb");
const GH = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"].find((p) => fs.existsSync(p)) ?? "gh";

const DEVICE = /^[\w .()'-]{1,60}$/;
const REF = /^[\w./-]{1,100}$/;
const WORKFLOW = /^[\w .\/-]{1,100}$/;
const RO = { readOnlyHint: true, destructiveHint: false, openWorldHint: false } as const;
const MUT = { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false } as const;

/** execFile with a fixed absolute binary (never a shell), job-style PATH, bounded output. */
function exec(bin: string, args: string[], cwd?: string, timeoutMs = 20000): Promise<{ stdout: string; stderr: string; code: number }> {
  return new Promise((resolve) => {
    execFile(bin, args, { cwd, timeout: timeoutMs, maxBuffer: 4 * 1024 * 1024, env: jobEnv() }, (err, stdout, stderr) => {
      const e = err as (Error & { code?: number | string }) | null;
      resolve({ stdout: String(stdout ?? ""), stderr: String(stderr ?? ""), code: e ? (typeof e.code === "number" ? e.code : 1) : 0 });
    });
  });
}

const norm = (s: string) => s.toLowerCase().replace(/[^a-z0-9]/g, "");

export interface Sim { name: string; udid: string; state: string; runtime: string }

/** "iPhone 17" → exact name, else a name starting with it (booted first), else a name containing it. */
export function matchSim(want: string, sims: Sim[]): Sim | undefined {
  const w = norm(want);
  const booted = (list: Sim[]) => list.sort((a, b) => Number(b.state === "Booted") - Number(a.state === "Booted"))[0];
  return sims.find((s) => norm(s.name) === w) ?? booted(sims.filter((s) => norm(s.name).startsWith(w))) ?? booted(sims.filter((s) => norm(s.name).includes(w)));
}

/** "Pixel 9" → AVD "Pixel_9_API_35" (normalized prefix/contains match). */
export function matchAvd(want: string, avds: string[]): string | undefined {
  const w = norm(want);
  return avds.find((a) => norm(a) === w) ?? avds.find((a) => norm(a).startsWith(w)) ?? avds.find((a) => norm(a).includes(w));
}

async function iosSims(): Promise<Sim[]> {
  const r = await exec(XCRUN, ["simctl", "list", "devices", "available", "-j"]);
  try {
    const data = JSON.parse(r.stdout).devices as Record<string, { name: string; udid: string; state: string }[]>;
    return Object.entries(data).flatMap(([rt, list]) => list.map((d) => ({ name: d.name, udid: d.udid, state: d.state, runtime: rt.replace(/.*SimRuntime\./, "").replace(/^([A-Za-z]+)-/, "$1 ").replace(/-/g, ".") })));
  } catch { return []; }
}
async function androidAvds(): Promise<string[]> {
  if (!fs.existsSync(EMULATOR)) return [];
  return (await exec(EMULATOR, ["-list-avds"])).stdout.split("\n").map((s) => s.trim()).filter((s) => s && !s.startsWith("INFO"));
}
async function adbDevices(): Promise<{ serial: string; model: string }[]> {
  if (!fs.existsSync(ADB)) return [];
  return (await exec(ADB, ["devices", "-l"])).stdout.split("\n").slice(1).map((l) => l.trim()).filter((l) => /\sdevice\s/.test(l))
    .map((l) => ({ serial: l.split(/\s+/)[0], model: (l.match(/model:(\S+)/)?.[1] ?? "").replace(/_/g, " ") }));
}

async function isReactNative(dir: string): Promise<boolean> {
  try {
    const pkg = JSON.parse(await fsp.readFile(path.join(dir, "package.json"), "utf8"));
    return !!({ ...pkg.dependencies, ...pkg.devDependencies })["react-native"];
  } catch { return false; }
}

export interface RunTarget { platform: "ios" | "android"; device: string }

/** Steps that build + launch a React Native app on one device. Throws a helpful error when the device is unknown. */
async function deviceSteps(project: string, t: RunTarget): Promise<{ steps: Step[]; label: string }> {
  if (!(await isReactNative(project))) {
    throw new Error(`${display(project)} is not a React Native project. For native Xcode projects, open the .xcworkspace with openPath and press Run.`);
  }
  if (t.platform === "ios") {
    const sims = await iosSims();
    const sim = matchSim(t.device, sims);
    if (!sim) throw new Error(`no iOS simulator matches "${t.device}". Available: ${[...new Set(sims.filter((s) => /iPhone|iPad/.test(s.name)).map((s) => s.name))].join(", ")}`);
    return { label: sim.name, steps: [{ bin: "npx", args: ["react-native", "run-ios", "--simulator", sim.name], label: `npx react-native run-ios --simulator "${sim.name}"` }] };
  }
  const avds = await androidAvds();
  const avd = matchAvd(t.device, avds);
  if (avd) {
    return {
      label: avd,
      steps: [
        { bin: "emulator", args: ["-avd", avd, "-no-snapshot-save"], background: true, label: `emulator -avd ${avd}` },
        { bin: "adb", args: ["wait-for-device"] },
        { bin: "adb", args: ["shell", "while [ -z \"$(getprop sys.boot_completed)\" ]; do sleep 1; done"], label: "adb: wait for boot" },
        { bin: "npx", args: ["react-native", "run-android"], label: "npx react-native run-android" },
      ],
    };
  }
  const dev = (await adbDevices()).find((d) => norm(d.model).includes(norm(t.device)));
  if (dev) return { label: dev.model, steps: [{ bin: "npx", args: ["react-native", "run-android", "--deviceId", dev.serial], label: `npx react-native run-android --deviceId ${dev.serial}` }] };
  throw new Error(`no Android emulator or device matches "${t.device}". AVDs: ${avds.join(", ") || "none — create one in Android Studio › Device Manager"}`);
}

export function registerDevTools(server: McpServer): void {
  defineTool(server, "listDevices", {
    description: "List iOS simulators, Android emulators (AVDs) and connected Android devices you can run apps on.",
    input: {},
    annotations: RO,
    handler: async () => {
      const [sims, avds, devs] = await Promise.all([iosSims(), androidAvds(), adbDevices()]);
      const phones = sims.filter((s) => /iPhone|iPad/.test(s.name));
      return [
        `iOS simulators (${phones.length}):`, ...phones.map((s) => `  ${s.name} · ${s.runtime}${s.state === "Booted" ? " · booted" : ""}`),
        `Android emulators (${avds.length}):`, ...(avds.length ? avds.map((a) => `  ${a}`) : ["  none — create one in Android Studio › Device Manager"]),
        `Android devices (${devs.length}):`, ...devs.map((d) => `  ${d.model} (${d.serial})`),
      ].join("\n");
    },
  });

  defineTool(server, "runOnDevice", {
    description: "Build and launch a React Native project on an iOS simulator (e.g. 'iPhone 17') or Android emulator/device (e.g. 'Pixel 9'). Runs in the background and notifies when done; returns a job id.",
    input: { project: z.string().min(1).describe("Project folder path"), platform: z.enum(["ios", "android"]), device: z.string().regex(DEVICE).describe("Device name, e.g. 'iPhone 17' or 'Pixel 9'") },
    annotations: MUT,
    handler: async ({ project, platform, device }) => {
      const dir = await resolveAllowed(project, { mustExist: true });
      const { steps, label } = await deviceSteps(dir, { platform, device });
      const job = await startJob(`${path.basename(dir)} on ${label}`, "run", dir, steps);
      return `Building ${path.basename(dir)} on ${label} in the background (job ${job.id}). You'll get a notification when it finishes; ask "job status" to check.`;
    },
  });

  defineTool(server, "listWorkflows", {
    description: "List a project's GitHub Actions workflows (needs the gh CLI signed in).",
    input: { project: z.string().min(1) },
    annotations: { ...RO, openWorldHint: true },
    handler: async ({ project }) => {
      const dir = await resolveAllowed(project, { mustExist: true });
      const r = await exec(GH, ["workflow", "list", "--json", "name,state,path"], dir);
      if (r.code !== 0) throw new Error(r.stderr.trim() || "gh workflow list failed (is this a GitHub repo and is gh signed in?)");
      const list = JSON.parse(r.stdout || "[]") as { name: string; state: string; path: string }[];
      return list.length ? list.map((w) => `${w.name} · ${w.state} · ${path.basename(w.path)}`).join("\n") : "No workflows in this repo.";
    },
  });

  defineTool(server, "workflowRuns", {
    description: "Show recent GitHub Actions runs (status, result, link) for a project, optionally one workflow.",
    input: { project: z.string().min(1), workflow: z.string().regex(WORKFLOW).optional() },
    annotations: { ...RO, openWorldHint: true },
    handler: async ({ project, workflow }) => {
      const dir = await resolveAllowed(project, { mustExist: true });
      const r = await exec(GH, ["run", "list", "-L", "5", "--json", "displayTitle,status,conclusion,workflowName,url,createdAt", ...(workflow ? ["--workflow", workflow] : [])], dir);
      if (r.code !== 0) throw new Error(r.stderr.trim() || "gh run list failed");
      const runs = JSON.parse(r.stdout || "[]") as { displayTitle: string; status: string; conclusion: string; workflowName: string; url: string }[];
      return runs.length ? runs.map((x) => `${x.workflowName}: ${x.displayTitle} · ${x.conclusion || x.status}\n  ${x.url}`).join("\n") : "No runs yet.";
    },
  });

  defineTool(server, "triggerWorkflow", {
    description: "Trigger a GitHub Actions workflow (e.g. a release build) on a branch or tag. Outward-facing: it can publish builds or releases.",
    input: { project: z.string().min(1), workflow: z.string().regex(WORKFLOW).describe("Workflow name or file, e.g. 'release.yml'"), ref: z.string().regex(REF).optional().describe("Branch or tag (default: repo default branch)") },
    annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: true },
    handler: async ({ project, workflow, ref }) => {
      const dir = await resolveAllowed(project, { mustExist: true });
      const r = await exec(GH, ["workflow", "run", workflow, ...(ref ? ["--ref", ref] : [])], dir);
      if (r.code !== 0) throw new Error(r.stderr.trim() || "gh workflow run failed");
      await new Promise((res) => setTimeout(res, 2500));
      const latest = await exec(GH, ["run", "list", "--workflow", workflow, "-L", "1", "--json", "url,status"], dir);
      const url = (JSON.parse(latest.stdout || "[]")[0] ?? {}).url;
      return `Triggered ${workflow}${ref ? ` on ${ref}` : ""}.${url ? `\n${url}` : ""}`;
    },
  });

  defineTool(server, "jobStatus", {
    description: "Status of background jobs (Claude Code runs, device builds). With an id: that job's details and recent log.",
    input: { id: z.string().regex(/^[\w-]{1,40}$/).optional() },
    annotations: RO,
    handler: async ({ id }) => {
      if (id) {
        const j = await readJob(id);
        if (!j) throw new Error(`no job ${id}`);
        return `${j.title}\nstatus: ${j.status}${j.failedStep ? ` (failed at ${j.failedStep})` : ""}\n--- log (tail) ---\n${await tail(j.log, 25)}`;
      }
      const jobs = await listJobs(8);
      if (!jobs.length) return "No background jobs yet.";
      const ago = (iso: string) => { const m = Math.round((Date.now() - Date.parse(iso)) / 60000); return m < 1 ? "just now" : m < 60 ? `${m} min ago` : `${Math.round(m / 60)} h ago`; };
      return jobs.map((j) => `${j.status === "running" ? "⏳" : j.status === "done" ? "✓" : "✗"} ${j.title} · ${j.status} · ${ago(j.startedAt)} · ${j.id}`).join("\n");
    },
  });
}
