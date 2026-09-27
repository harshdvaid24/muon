// Developer chores: git status/diff/commit/push (no force, no history rewrites), Metro/watchman cache cleanup,
// adb pairing and app installs, signed Android builds, and reading a web page as text.
import fs from "node:fs";
import fsp from "node:fs/promises";
import path from "node:path";
import os from "node:os";
import { execFile } from "node:child_process";
import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { defineTool } from "../define.js";
import { resolveAllowed, display, ALLOWED_ROOTS } from "../paths.js";
import { startJob, jobEnv, ANDROID } from "../jobs.js";

const GIT = "/usr/bin/git";
const ADB = path.join(ANDROID, "platform-tools/adb");
const RO = { readOnlyHint: true, destructiveHint: false, openWorldHint: false } as const;
const MUT = { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false } as const;

function exec(bin: string, args: string[], cwd?: string, timeoutMs = 20000): Promise<{ stdout: string; stderr: string; code: number }> {
  return new Promise((resolve) => {
    execFile(bin, args, { cwd, timeout: timeoutMs, maxBuffer: 4 * 1024 * 1024, env: jobEnv() }, (err, stdout, stderr) => {
      const e = err as (Error & { code?: number | string }) | null;
      resolve({ stdout: String(stdout ?? ""), stderr: String(stderr ?? ""), code: e ? (typeof e.code === "number" ? e.code : 1) : 0 });
    });
  });
}

/** The project's own repository. Refuses a repo that is an allowed root's parent (e.g. a dotfiles repo in $HOME),
 *  so "commit this" in a non-repo folder can never stage the whole home directory. */
async function repo(project: string): Promise<string> {
  const dir = await resolveAllowed(project, { mustExist: true });
  const r = await exec(GIT, ["-C", dir, "rev-parse", "--show-toplevel"]);
  if (r.code !== 0) throw new Error(`${display(dir)} is not a git repository`);
  const top = r.stdout.trim();
  const inside = ALLOWED_ROOTS.some((root) => top !== root && top.startsWith(root + path.sep));
  if (!inside) throw new Error(`${display(dir)} is not a git repository of its own (the enclosing repository is ${display(top)}, which Muon won't touch)`);
  return top;
}

/** Strip a page down to readable text. */
export function htmlToText(html: string): string {
  let s = html.replace(/<script[\s\S]*?<\/script>/gi, " ").replace(/<style[\s\S]*?<\/style>/gi, " ").replace(/<(nav|footer|header|aside|noscript)[\s\S]*?<\/\1>/gi, " ");
  s = s.replace(/<(br|p|div|li|h[1-6]|tr|section|article)[^>]*>/gi, "\n").replace(/<[^>]+>/g, " ");
  s = s.replace(/&nbsp;/g, " ").replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&#39;/g, "'");
  return s.replace(/[ \t]+/g, " ").replace(/\n\s*\n+/g, "\n").trim();
}

const ADDRESS = /^(\d{1,3}\.){3}\d{1,3}:\d{2,5}$/;

export function registerDevOpsTools(server: McpServer): void {
  defineTool(server, "readWebPage", {
    description: "Fetch a web page and return its readable text (for summarizing or answering questions about it). http(s) only, 60 KB cap.",
    input: { url: z.string().url() },
    annotations: { readOnlyHint: true, destructiveHint: false, openWorldHint: true },
    handler: async ({ url }) => {
      if (!/^https?:\/\//i.test(url)) throw new Error("only http(s) URLs");
      const res = await fetch(url, { signal: AbortSignal.timeout(12000), headers: { "User-Agent": "Mozilla/5.0 (Macintosh) Muon/0.2", Accept: "text/html,text/plain,*/*" }, redirect: "follow" });
      if (!res.ok) throw new Error(`page returned HTTP ${res.status}`);
      const type = res.headers.get("content-type") ?? "";
      const raw = (await res.text()).slice(0, 2_000_000);
      const text = /html/i.test(type) ? htmlToText(raw) : raw;
      const title = raw.match(/<title[^>]*>([^<]{1,200})/i)?.[1]?.trim();
      return (title ? `${title}\n\n` : "") + text.slice(0, 60_000) + (text.length > 60_000 ? "\n…(truncated)" : "");
    },
  });

  defineTool(server, "gitStatus", {
    description: "Git status for a project: branch, ahead/behind, changed files.",
    input: { project: z.string().min(1) },
    annotations: RO,
    handler: async ({ project }) => {
      const dir = await repo(project);
      const r = await exec(GIT, ["-C", dir, "status", "--short", "--branch"]);
      return r.stdout.trim() || "clean";
    },
  });

  defineTool(server, "gitDiff", {
    description: "What changed in a project (unstaged + staged), as a stat summary plus the first 300 diff lines. Use before writing a commit message.",
    input: { project: z.string().min(1) },
    annotations: RO,
    handler: async ({ project }) => {
      const dir = await repo(project);
      const stat = await exec(GIT, ["-C", dir, "diff", "HEAD", "--stat"]);
      const diff = await exec(GIT, ["-C", dir, "diff", "HEAD"]);
      const untracked = await exec(GIT, ["-C", dir, "ls-files", "--others", "--exclude-standard"]);
      const lines = diff.stdout.split("\n").slice(0, 300).join("\n");
      return [stat.stdout.trim() || "no tracked changes", untracked.stdout.trim() ? `untracked:\n${untracked.stdout.trim()}` : "", lines].filter(Boolean).join("\n\n");
    },
  });

  defineTool(server, "gitCommit", {
    description: "Stage all changes and commit with the given message. Never amends or rewrites history.",
    input: { project: z.string().min(1), message: z.string().min(3).max(2000) },
    annotations: MUT,
    handler: async ({ project, message }) => {
      const dir = await repo(project);
      const add = await exec(GIT, ["-C", dir, "add", "-A"]);
      if (add.code !== 0) throw new Error(add.stderr.trim());
      const c = await exec(GIT, ["-C", dir, "commit", "-m", message]);
      if (c.code !== 0) throw new Error(c.stderr.trim() || c.stdout.trim() || "commit failed");
      const h = await exec(GIT, ["-C", dir, "rev-parse", "--short", "HEAD"]);
      return `Committed ${h.stdout.trim()}: ${message.split("\n")[0]}`;
    },
  });

  defineTool(server, "gitPush", {
    description: "Push the current branch to origin (sets upstream if needed). Never force-pushes.",
    input: { project: z.string().min(1) },
    annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: true },
    handler: async ({ project }) => {
      const dir = await repo(project);
      const r = await exec(GIT, ["-C", dir, "push", "-u", "origin", "HEAD"], undefined, 120000);
      if (r.code !== 0) throw new Error(r.stderr.trim() || "push failed");
      return (r.stderr.trim() || r.stdout.trim() || "Pushed.").split("\n").slice(-3).join("\n");
    },
  });

  defineTool(server, "cleanDevCaches", {
    description: "Fix a stuck React Native/Metro setup: free ports 8081/8097, reset watchman, delete Metro and haste caches and node_modules/.cache. Does not touch node_modules or build outputs.",
    input: { project: z.string().min(1) },
    annotations: MUT,
    handler: async ({ project }) => {
      const dir = await resolveAllowed(project, { mustExist: true });
      const done: string[] = [];
      for (const port of [8081, 8097]) {
        const l = await exec("/usr/sbin/lsof", ["-ti", `:${port}`]);
        for (const pid of l.stdout.split("\n").map((s) => s.trim()).filter(Boolean)) { try { process.kill(Number(pid), "SIGTERM"); done.push(`stopped pid ${pid} on :${port}`); } catch { /* gone */ } }
      }
      const wm = ["/opt/homebrew/bin/watchman", "/usr/local/bin/watchman"].find((p) => fs.existsSync(p));
      if (wm) { await exec(wm, ["watch-del-all"]); done.push("watchman: watch-del-all"); }
      const tmp = os.tmpdir();
      for (const e of await fsp.readdir(tmp).catch(() => [] as string[])) if (/^(metro|haste-map|react-)/.test(e)) { await fsp.rm(path.join(tmp, e), { recursive: true, force: true }); done.push(`removed ${e}`); }
      for (const rel of ["node_modules/.cache", ".metro"]) { const p = path.join(dir, rel); if (fs.existsSync(p)) { await fsp.rm(p, { recursive: true, force: true }); done.push(`removed ${rel}`); } }
      return done.length ? done.join("\n") : "Nothing to clean.";
    },
  });

  defineTool(server, "adbPair", {
    description: "Pair with an Android phone or Wear OS watch over Wi-Fi (Developer options › Wireless debugging › Pair device with pairing code).",
    input: { address: z.string().regex(ADDRESS).describe("ip:port shown in the pairing dialog"), code: z.string().regex(/^\d{6}$/) },
    annotations: MUT,
    handler: async ({ address, code }) => {
      if (!fs.existsSync(ADB)) throw new Error("adb not found; install Android platform-tools");
      const r = await exec(ADB, ["pair", address, code], undefined, 30000);
      if (r.code !== 0 || /failed/i.test(r.stdout)) throw new Error((r.stdout + r.stderr).trim());
      return r.stdout.trim();
    },
  });

  defineTool(server, "adbConnect", {
    description: "Connect to a paired Android device or watch over Wi-Fi (ip:port from Wireless debugging).",
    input: { address: z.string().regex(ADDRESS) },
    annotations: MUT,
    handler: async ({ address }) => {
      if (!fs.existsSync(ADB)) throw new Error("adb not found; install Android platform-tools");
      const r = await exec(ADB, ["connect", address], undefined, 30000);
      if (/failed|unable|refused/i.test(r.stdout + r.stderr)) throw new Error((r.stdout + r.stderr).trim());
      return r.stdout.trim();
    },
  });

  defineTool(server, "installApp", {
    description: "Install an .apk on an Android device/emulator (adb install -r) or a .app on the booted iOS Simulator.",
    input: { path: z.string().min(1), device: z.string().regex(/^[\w.:-]{1,60}$/).optional().describe("adb serial or ip:port (optional)") },
    annotations: MUT,
    handler: async ({ path: p, device }) => {
      const real = await resolveAllowed(p, { mustExist: true });
      if (real.endsWith(".apk")) {
        if (!fs.existsSync(ADB)) throw new Error("adb not found");
        const r = await exec(ADB, [...(device ? ["-s", device] : []), "install", "-r", real], undefined, 180000);
        if (r.code !== 0 || /failure/i.test(r.stdout)) throw new Error((r.stdout + r.stderr).trim());
        return `Installed ${display(real)}${device ? ` on ${device}` : ""}`;
      }
      if (real.endsWith(".app")) {
        const r = await exec("/usr/bin/xcrun", ["simctl", "install", "booted", real], undefined, 60000);
        if (r.code !== 0) throw new Error(r.stderr.trim() || "simctl install failed");
        return `Installed ${display(real)} on the booted simulator`;
      }
      throw new Error("expected an .apk or a simulator .app");
    },
  });

  defineTool(server, "buildAndroidRelease", {
    description: "Build a signed release APK for a React Native/Android project (gradlew assembleRelease) as a background job with a notification. Signing must be configured in android/app/build.gradle.",
    input: { project: z.string().min(1) },
    annotations: MUT,
    handler: async ({ project }) => {
      const dir = await resolveAllowed(project, { mustExist: true });
      const gradlew = path.join(dir, "android/gradlew");
      if (!fs.existsSync(gradlew)) throw new Error(`no android/gradlew in ${display(dir)}`);
      const job = await startJob(`${path.basename(dir)} release APK`, "build", path.join(dir, "android"), [
        { bin: gradlew, args: ["assembleRelease", "--no-daemon", "-q"], label: "./gradlew assembleRelease" },
      ]);
      return `Building the release APK in the background (job ${job.id}). The APK lands in android/app/build/outputs/apk/release/. Ask "job status" to check.`;
    },
  });
}
