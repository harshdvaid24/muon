// Detached job runner: executes a job's steps in order, appends output to its log, records the result,
// and posts a macOS notification. Started by startJob(); survives the tool server exiting.
import fs from "node:fs";
import { spawn } from "node:child_process";

const file = process.argv[2];
const job = JSON.parse(fs.readFileSync(file, "utf8"));
const out = fs.openSync(job.log, "a");
const write = (s: string) => fs.writeSync(out, s);
const save = () => fs.writeFileSync(file, JSON.stringify(job, null, 2));
const TIMEOUT_MS = 45 * 60 * 1000;

function runStep(step: { bin: string; args: string[]; cwd?: string; background?: boolean; label?: string }): Promise<number> {
  write(`\n$ ${step.label ?? [step.bin, ...step.args].join(" ")}\n`);
  return new Promise((resolve) => {
    const child = spawn(step.bin, step.args, { cwd: step.cwd ?? job.cwd, env: process.env, stdio: ["ignore", out, out], detached: !!step.background });
    if (step.background) { child.unref(); write(`(running in background, pid ${child.pid})\n`); resolve(0); return; }
    const timer = setTimeout(() => { write("\n[timed out after 45 min]\n"); child.kill("SIGTERM"); }, TIMEOUT_MS);
    child.on("error", (e) => { clearTimeout(timer); write(`\n[error] ${e.message}\n`); resolve(127); });
    child.on("exit", (code) => { clearTimeout(timer); resolve(code ?? 1); });
  });
}

(async () => {
  for (const step of job.steps) {
    const code = await runStep(step);
    if (code !== 0) { job.status = "failed"; job.code = code; job.failedStep = step.label ?? step.bin; break; }
  }
  if (job.status === "running") { job.status = "done"; job.code = 0; }
  job.endedAt = new Date().toISOString();
  write(`\n[${job.status}] ${job.endedAt}\n`);
  save();
  if (job.notify) {
    const msg = `${job.title} ${job.status === "done" ? "finished ✓" : "failed ✗"}`;
    spawn("/usr/bin/osascript", ["-e", `display notification ${JSON.stringify(msg)} with title "Muon"`], { stdio: "ignore" });
  }
})();
