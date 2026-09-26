import fsp from "node:fs/promises";
import path from "node:path";
import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { defineTool, cap } from "../define.js";
import { run } from "../run.js";
import { ALLOWED_ROOTS, resolveAllowed, display } from "../paths.js";

const MAX_RESULTS = 20;
const MAX_READ = 20 * 1024;
const RG_EXCLUDES = ["-g", "!node_modules", "-g", "!Pods", "-g", "!.git", "-g", "!DerivedData", "-g", "!build", "-g", "!*.lock"];
const RO = { readOnlyHint: true, destructiveHint: false, openWorldHint: false } as const;

async function scopeRoots(scope?: string): Promise<string[]> {
  if (!scope) return (await Promise.all(ALLOWED_ROOTS.map(async (r) => (await fsp.stat(r).catch(() => null))?.isDirectory() ? r : null))).filter((r): r is string => !!r);
  return [await resolveAllowed(scope, { mustExist: true })];
}

export function registerFileTools(server: McpServer): void {
  defineTool(server, "searchFiles", {
    description: "Spotlight content/metadata search (mdfind) inside allowed folders. Use for 'files about X', 'PDFs downloaded this week'. Query may use Spotlight syntax.",
    input: { query: z.string().min(1).describe("Search text or Spotlight query"), scope: z.string().optional().describe("Folder to limit search to (default: all allowed folders)") },
    annotations: RO,
    handler: async ({ query, scope }) => {
      const roots = await scopeRoots(scope);
      const found: string[] = [];
      for (const r of roots) {
        const res = await run("mdfind", ["-onlyin", r, query], { timeoutMs: 8000 });
        found.push(...res.stdout.split("\n").filter(Boolean));
        if (found.length > MAX_RESULTS * 3) break;
      }
      if (!found.length) return `No files matched "${query}".`;
      const { items, note } = cap(found, MAX_RESULTS);
      return items.map(display).join("\n") + note;
    },
  });

  defineTool(server, "findFiles", {
    description: "Find files or folders by (partial) name inside allowed folders. Uses Spotlight name index, falls back to ripgrep.",
    input: { name: z.string().min(1).describe("Partial file/folder name, e.g. 'package.json' or 'kathak'"), scope: z.string().optional().describe("Folder to limit search to") },
    annotations: RO,
    handler: async ({ name, scope }) => {
      const roots = await scopeRoots(scope);
      let found: string[] = [];
      for (const r of roots) {
        const res = await run("mdfind", ["-onlyin", r, "-name", name], { timeoutMs: 8000 });
        found.push(...res.stdout.split("\n").filter(Boolean));
      }
      found = found.filter((p) => !/\/(node_modules|Pods|\.git|DerivedData)\//.test(p));
      if (!found.length) {
        for (const r of roots) {
          const res = await run("rg", ["--files", "--iglob", `*${name}*`, ...RG_EXCLUDES, r], { timeoutMs: 8000 });
          found.push(...res.stdout.split("\n").filter(Boolean));
          if (found.length > MAX_RESULTS * 3) break;
        }
      }
      if (!found.length) return `Nothing named like "${name}" found.`;
      found.sort((a, b) => a.length - b.length);
      const { items, note } = cap(found, MAX_RESULTS);
      return items.map(display).join("\n") + note;
    },
  });

  defineTool(server, "searchCode", {
    description: "Search source code with ripgrep (regex, smart case). Returns file:line: text. Skips node_modules/Pods/.git.",
    input: { pattern: z.string().min(1).describe("Regex or literal text"), scope: z.string().optional().describe("Folder to search (default: all allowed folders)"), glob: z.string().optional().describe("Only files matching glob, e.g. '*.tsx' or 'package.json'") },
    annotations: RO,
    handler: async ({ pattern, scope, glob }) => {
      const roots = await scopeRoots(scope);
      const lines: string[] = [];
      for (const r of roots) {
        const args = ["-n", "-S", "--max-count", "3", "--max-columns", "200", "--no-messages", ...RG_EXCLUDES];
        if (glob) args.push("-g", glob);
        const res = await run("rg", [...args, "-e", pattern, r], { timeoutMs: 10000 });
        lines.push(...res.stdout.split("\n").filter(Boolean));
        if (lines.length > MAX_RESULTS * 3) break;
      }
      if (!lines.length) return `No code matched /${pattern}/.`;
      const { items, note } = cap(lines, MAX_RESULTS, "matches");
      return items.map(display).join("\n") + note;
    },
  });

  defineTool(server, "readFile", {
    description: "Read a text file (first 20 KB) inside allowed folders.",
    input: { path: z.string().min(1).describe("File path") },
    annotations: RO,
    handler: async ({ path: p }) => {
      const real = await resolveAllowed(p, { mustExist: true });
      const st = await fsp.stat(real);
      if (!st.isFile()) throw new Error(`not a file: ${display(real)}`);
      const fh = await fsp.open(real, "r");
      try {
        const buf = Buffer.alloc(Math.min(st.size, MAX_READ));
        const { bytesRead } = await fh.read(buf, 0, buf.length, 0);
        const head = buf.subarray(0, bytesRead);
        if (head.subarray(0, 8192).includes(0)) throw new Error(`binary file, not shown: ${display(real)} (${st.size} bytes)`);
        return head.toString("utf8") + (st.size > MAX_READ ? `\n…(truncated, ${st.size} bytes total)` : "");
      } finally { await fh.close(); }
    },
  });

  defineTool(server, "listDirectory", {
    description: "List a folder (dirs first, up to 100 entries) inside allowed folders.",
    input: { path: z.string().min(1).describe("Folder path") },
    annotations: RO,
    handler: async ({ path: p }) => {
      const real = await resolveAllowed(p, { mustExist: true });
      const entries = await fsp.readdir(real, { withFileTypes: true });
      const rows = await Promise.all(entries.filter((e) => !e.name.startsWith(".")).map(async (e) => {
        const st = await fsp.stat(path.join(real, e.name)).catch(() => null);
        return { name: e.name, dir: e.isDirectory(), size: st?.size ?? 0, mtime: st?.mtimeMs ?? 0 };
      }));
      rows.sort((a, b) => Number(b.dir) - Number(a.dir) || a.name.localeCompare(b.name));
      const { items, note } = cap(rows, 100, "entries");
      return `${display(real)}\n` + items.map((r) => r.dir ? `${r.name}/` : `${r.name}  ${fmtSize(r.size)}`).join("\n") + note;
    },
  });

  defineTool(server, "listProjects", {
    description: "List top-level project folders in ~/Projects and ~/Work with detected type (react-native, node, xcode, swift-package, other).",
    input: {},
    annotations: RO,
    handler: async () => {
      const out: string[] = [];
      for (const root of ALLOWED_ROOTS.filter((r) => /\/(Projects|Work)$/.test(r))) {
        const entries = await fsp.readdir(root, { withFileTypes: true }).catch(() => []);
        for (const e of entries) {
          if (!e.isDirectory() || e.name.startsWith(".")) continue;
          out.push(`${display(path.join(root, e.name))}\t${await projectType(path.join(root, e.name))}`);
        }
      }
      return out.length ? out.join("\n") : "No project folders found.";
    },
  });
}

async function projectType(dir: string): Promise<string> {
  const has = async (n: string) => !!(await fsp.stat(path.join(dir, n)).catch(() => null));
  if (await has("package.json")) {
    if (await has("ios") || await has("android") || await has("app.json")) return "react-native";
    if (await has("next.config.js") || await has("next.config.ts") || await has("next.config.mjs")) return "nextjs";
    return "node";
  }
  const names = await fsp.readdir(dir).catch(() => [] as string[]);
  if (names.some((n) => n.endsWith(".xcworkspace"))) return "xcode-workspace";
  if (names.some((n) => n.endsWith(".xcodeproj"))) return "xcode";
  if (await has("Package.swift")) return "swift-package";
  if (await has("pyproject.toml") || await has("requirements.txt")) return "python";
  if (await has("build.gradle") || await has("build.gradle.kts")) return "android";
  return "other";
}

function fmtSize(n: number): string {
  if (n < 1024) return `${n} B`;
  if (n < 1048576) return `${(n / 1024).toFixed(0)} KB`;
  if (n < 1073741824) return `${(n / 1048576).toFixed(1)} MB`;
  return `${(n / 1073741824).toFixed(2)} GB`;
}
