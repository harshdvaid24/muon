// Single choke point for spawning binaries. Argv arrays only, never a shell.
import { execFile } from "node:child_process";

export const ALLOWED_BINS = new Set([
  "open", "mdfind", "rg", "ps", "pgrep", "osascript", "du", "df", "xcrun", "vm_stat", "pmset", "sysctl", "trash",
  // VS Code CLI, for "start claude code for <project>" (opens a window; never a shell)
  "/usr/local/bin/code", "/opt/homebrew/bin/code", "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code",
  "/usr/bin/sqlite3",   // seeds VS Code's per-workspace layout state for a terminal-only assistant window
]);

export interface RunResult { stdout: string; stderr: string; code: number }

const SAFE_ENV = {
  PATH: "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin",
  HOME: process.env.HOME ?? "",
  LANG: "en_US.UTF-8",
};

export function run(bin: string, args: string[], opts: { timeoutMs?: number; cwd?: string } = {}): Promise<RunResult> {
  if (!ALLOWED_BINS.has(bin)) return Promise.reject(new Error(`binary not allowed: ${bin}`));
  return new Promise((resolve) => {
    execFile(bin, args, { timeout: opts.timeoutMs ?? 10_000, maxBuffer: 1024 * 1024, cwd: opts.cwd, env: SAFE_ENV },
      (err, stdout, stderr) => {
        const anyErr = err as (Error & { code?: number | string }) | null;
        const code = anyErr ? (typeof anyErr.code === "number" ? anyErr.code : 1) : 0;
        resolve({ stdout: String(stdout ?? ""), stderr: String(stderr ?? ""), code });
      });
  });
}
