// Background jobs: long-running work (simulator builds) that must outlive a tool call
// and even the tool server. Each job is a JSON file + a log; a detached runner executes its steps.
import fsp from "node:fs/promises";
import path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { randomUUID } from "node:crypto";
import { DATA_DIR } from "./audit.js";
import { HOME } from "./paths.js";

export const JOBS_DIR = path.join(DATA_DIR, "jobs");
export const ANDROID = process.env.ANDROID_HOME || path.join(HOME, "Library/Android/sdk");
/** Only these binaries may run inside a job (resolved on the job PATH below). */
export const JOB_BINS = new Set(["npx", "node", "xcrun", "xcodebuild", "emulator", "adb", "gh", "pod", "gradlew"]);
const KEEP_JOBS = 40;

export interface Step { bin: string; args: string[]; cwd?: string; background?: boolean; label?: string }
export interface Job {
  id: string; title: string; kind: string; cwd: string; steps: Step[];
  status: "running" | "done" | "failed"; startedAt: string; endedAt?: string; code?: number; failedStep?: string;
  log: string; notify: boolean;
}

export function jobEnv(): Record<string, string> {
  const PATH = [path.dirname(process.execPath), "/opt/homebrew/bin", "/usr/local/bin", path.join(ANDROID, "platform-tools"),
    path.join(ANDROID, "emulator"), path.join(HOME, ".local/bin"), "/usr/bin", "/bin", "/usr/sbin", "/sbin"].join(":");
  return { PATH, HOME, LANG: "en_US.UTF-8", ANDROID_HOME: ANDROID, ANDROID_SDK_ROOT: ANDROID, TERM: "dumb", CI: "1" };
}

export async function startJob(title: string, kind: string, cwd: string, steps: Step[], notify = true): Promise<Job> {
  for (const s of steps) if (!JOB_BINS.has(s.bin) && !JOB_BINS.has(path.basename(s.bin))) throw new Error(`binary not allowed in jobs: ${s.bin}`);
  await fsp.mkdir(JOBS_DIR, { recursive: true });
  const id = new Date().toISOString().replace(/[-:T.Z]/g, "").slice(0, 14) + "-" + randomUUID().slice(0, 4);
  const job: Job = { id, title, kind, cwd, steps, status: "running", startedAt: new Date().toISOString(), log: path.join(JOBS_DIR, `${id}.log`), notify };
  const file = path.join(JOBS_DIR, `${id}.json`);
  await fsp.writeFile(file, JSON.stringify(job, null, 2));
  await fsp.writeFile(job.log, `${title}\nstarted ${job.startedAt} in ${cwd}\n`);
  const runner = path.join(path.dirname(fileURLToPath(import.meta.url)), "job-runner.js");
  spawn(process.execPath, [runner, file], { detached: true, stdio: "ignore", env: jobEnv() }).unref();
  return job;
}

export async function readJob(id: string): Promise<Job | null> {
  if (!/^[\w-]{1,40}$/.test(id)) return null;
  try { return JSON.parse(await fsp.readFile(path.join(JOBS_DIR, `${id}.json`), "utf8")); } catch { return null; }
}

export async function listJobs(n = 8): Promise<Job[]> {
  const names = (await fsp.readdir(JOBS_DIR).catch(() => [] as string[])).filter((f) => f.endsWith(".json")).sort().reverse();
  const jobs = await Promise.all(names.slice(0, n).map((f) => readJob(f.slice(0, -5))));
  return jobs.filter((j): j is Job => !!j);
}

export async function tail(file: string, lines = 30): Promise<string> {
  const text = await fsp.readFile(file, "utf8").catch(() => "");
  return text.trimEnd().split("\n").slice(-lines).join("\n");
}

/** Keep the newest KEEP_JOBS jobs; runs at server start so the folder never grows unbounded. */
export async function pruneJobs(): Promise<void> {
  const names = (await fsp.readdir(JOBS_DIR).catch(() => [] as string[])).filter((f) => f.endsWith(".json")).sort().reverse();
  for (const f of names.slice(KEEP_JOBS)) {
    const id = f.slice(0, -5);
    await fsp.rm(path.join(JOBS_DIR, f), { force: true });
    await fsp.rm(path.join(JOBS_DIR, `${id}.log`), { force: true });
  }
}
