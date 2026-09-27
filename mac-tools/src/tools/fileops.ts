// Mutating tools. Batch forms so one user confirmation covers one logical operation.
import fsp from "node:fs/promises";
import path from "node:path";
import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { defineTool } from "../define.js";
import { run } from "../run.js";
import { resolveAllowed, display, expandHome, ALLOWED_ROOTS } from "../paths.js";

const MAX_OPS = 50;
const APP_NAME = /^[\w .+&()'-]{1,64}$/;
const MUT = { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false } as const;
const pathList = z.array(z.string().min(1)).min(1).max(MAX_OPS).describe(`Paths (max ${MAX_OPS})`);

const exists = async (p: string) => !!(await fsp.lstat(p).catch(() => null));

/** Mutations act on what the user sees: refuse symlinks (target would be affected) and allowed roots themselves. */
async function resolveMutable(p: string): Promise<string> {
  const lexical = path.resolve(expandHome(p.trim()));
  const st = await fsp.lstat(lexical).catch(() => null);
  if (st?.isSymbolicLink()) throw new Error(`refusing to modify a symlink: ${display(lexical)}`);
  const real = await resolveAllowed(p, { mustExist: true });
  if (ALLOWED_ROOTS.includes(real)) throw new Error(`refusing to modify an allowed root folder: ${display(real)}`);
  return real;
}

async function resolveFolder(p: string): Promise<string> {
  const real = await resolveAllowed(p, { mustExist: true });
  if (!(await fsp.stat(real)).isDirectory()) throw new Error(`not a folder: ${display(real)}`);
  return real;
}

async function batch(paths: string[], dest: string, op: (src: string, dst: string) => Promise<void>, verb: string): Promise<string> {
  const folder = await resolveFolder(dest);
  const lines: string[] = [];
  let done = 0;
  for (const p of paths) {
    try {
      const src = await resolveMutable(p);
      if (folder === src || folder.startsWith(src + path.sep)) { lines.push(`skip ${display(src)}: cannot move a folder into itself`); continue; }
      const dst = path.join(folder, path.basename(src));
      if (src === dst) { lines.push(`skip ${display(src)}: already there`); continue; }
      if (await exists(dst)) { lines.push(`skip ${display(src)}: ${display(dst)} already exists`); continue; }
      await op(src, dst); done++;
      lines.push(`${verb} ${display(src)} → ${display(dst)}`);
    } catch (e) { lines.push(`failed ${p}: ${e instanceof Error ? e.message : e}`); }
  }
  return `${done}/${paths.length} ${verb}.\n` + lines.join("\n");
}

export function registerFileOps(server: McpServer): void {
  defineTool(server, "moveItems", {
    description: "Move files/folders into a destination folder. Never overwrites. Max 50 items per call.",
    input: { paths: pathList, destinationFolder: z.string().min(1).describe("Existing destination folder") },
    annotations: MUT,
    handler: ({ paths, destinationFolder }) => batch(paths, destinationFolder, (s, d) => fsp.rename(s, d), "moved"),
  });

  defineTool(server, "copyItems", {
    description: "Copy files/folders into a destination folder. Never overwrites. Max 50 items per call.",
    input: { paths: pathList, destinationFolder: z.string().min(1).describe("Existing destination folder") },
    annotations: { ...MUT, idempotentHint: true },
    handler: ({ paths, destinationFolder }) => batch(paths, destinationFolder, (s, d) => fsp.cp(s, d, { recursive: true, errorOnExist: true, force: false }), "copied"),
  });

  defineTool(server, "renameItem", {
    description: "Rename a file or folder in place. Never overwrites.",
    input: { path: z.string().min(1), newName: z.string().min(1).max(255).describe("New name only, no slashes") },
    annotations: MUT,
    handler: async ({ path: p, newName }) => {
      if (newName.includes("/") || newName === "." || newName === "..") throw new Error("newName must be a plain name");
      const src = await resolveMutable(p);
      const dst = await resolveAllowed(path.join(path.dirname(src), newName));
      if (await exists(dst)) throw new Error(`${display(dst)} already exists`);
      await fsp.rename(src, dst);
      return `Renamed ${display(src)} → ${newName}`;
    },
  });

  defineTool(server, "createFolder", {
    description: "Create a folder (and parents) inside allowed folders.",
    input: { path: z.string().min(1) },
    annotations: { ...MUT, idempotentHint: true },
    handler: async ({ path: p }) => {
      const real = await resolveAllowed(p);
      await fsp.mkdir(real, { recursive: true });
      return `Created ${display(real)}`;
    },
  });

  defineTool(server, "trashItems", {
    description: "Move files/folders to the Trash (recoverable via Finder > Put Back). This is the only way to delete. Max 50 items.",
    input: { paths: pathList },
    annotations: MUT,
    handler: async ({ paths }) => {
      const reals = await Promise.all(paths.map(resolveMutable));
      const res = await run("trash", reals);
      if (res.code !== 0) throw new Error(res.stderr.trim() || "trash failed");
      return `Moved ${reals.length} item(s) to Trash:\n` + reals.map(display).join("\n");
    },
  });

  defineTool(server, "quitApplication", {
    description: "Gracefully quit a running application (it may ask to save).",
    input: { name: z.string().regex(APP_NAME).describe("Application name, e.g. 'Spotify'") },
    annotations: { ...MUT, idempotentHint: true },
    handler: async ({ name }) => {
      const res = await run("osascript", ["-e", `tell application "${name}" to quit`], { timeoutMs: 15000 });
      if (res.code !== 0) throw new Error(res.stderr.trim() || `could not quit ${name}`);
      return `Asked ${name} to quit.`;
    },
  });

  defineTool(server, "killProcess", {
    description: "Force-terminate (SIGTERM) a process you own by PID. Unsaved work in that process is lost.",
    input: { pid: z.number().int().min(2).describe("Process ID from listRunningApps") },
    annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false },
    handler: async ({ pid }) => {
      if (pid === process.pid || pid === process.ppid) throw new Error("refusing to kill the agent itself");
      const owner = await run("ps", ["-o", "uid=", "-p", String(pid)]);
      if (Number(owner.stdout.trim()) !== process.getuid?.()) throw new Error(`process ${pid} is not yours or does not exist`);
      process.kill(pid, "SIGTERM");
      return `Sent SIGTERM to ${pid}.`;
    },
  });
}
