// Disk-space helpers: largest files and duplicate files. Read-only, bounded walks.
import fsp from "node:fs/promises";
import { createReadStream } from "node:fs";
import { createHash } from "node:crypto";
import path from "node:path";
import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { defineTool } from "../define.js";
import { resolveAllowed, display } from "../paths.js";

const SKIP = new Set(["node_modules", ".git", "Pods", "DerivedData", "build", ".build", ".next", ".gradle", ".Trash"]);
const MAX_FILES = 20_000;
const MAX_DEPTH = 8;
const RO = { readOnlyHint: true, destructiveHint: false, openWorldHint: false } as const;

interface Entry { path: string; size: number }

/** Bounded recursive walk: skips build/dependency folders and hidden entries, never follows symlinks. */
async function walk(root: string): Promise<{ files: Entry[]; truncated: boolean }> {
  const files: Entry[] = [];
  let truncated = false;
  async function go(dir: string, depth: number): Promise<void> {
    if (depth > MAX_DEPTH || truncated) return;
    const entries = await fsp.readdir(dir, { withFileTypes: true }).catch(() => []);
    for (const e of entries) {
      if (e.name.startsWith(".") || SKIP.has(e.name)) continue;
      const p = path.join(dir, e.name);
      if (e.isDirectory()) { await go(p, depth + 1); continue; }
      if (!e.isFile()) continue; // symlinks, sockets, etc.
      const st = await fsp.stat(p).catch(() => null);
      if (!st) continue;
      files.push({ path: p, size: st.size });
      if (files.length >= MAX_FILES) { truncated = true; return; }
    }
  }
  await go(root, 0);
  return { files, truncated };
}

export function fmtSize(n: number): string {
  if (n < 1024) return `${n} B`;
  if (n < 1048576) return `${(n / 1024).toFixed(0)} KB`;
  if (n < 1073741824) return `${(n / 1048576).toFixed(1)} MB`;
  return `${(n / 1073741824).toFixed(2)} GB`;
}

function sha1(p: string): Promise<string> {
  return new Promise((resolve, reject) => {
    const h = createHash("sha1");
    createReadStream(p).on("data", (d) => h.update(d)).on("end", () => resolve(h.digest("hex"))).on("error", reject);
  });
}

const KINDS: Record<string, { ext?: string[]; name?: RegExp }> = {
  screenshots: { name: /^(screenshot|screen shot|simulator screen)/i },
  images: { ext: ["png", "jpg", "jpeg", "heic", "gif", "webp", "tiff", "bmp"] },
  pdfs: { ext: ["pdf"] },
  zips: { ext: ["zip", "rar", "7z", "tar", "gz", "tgz"] },
  videos: { ext: ["mov", "mp4", "m4v", "avi", "mkv", "webm"] },
  installers: { ext: ["dmg", "pkg", "apk", "aab", "ipa", "msi"] },
  documents: { ext: ["doc", "docx", "pages", "txt", "rtf", "md", "xls", "xlsx", "numbers", "key", "ppt", "pptx", "csv"] },
  audio: { ext: ["mp3", "m4a", "wav", "aac", "flac"] },
};

export function registerDiskTools(server: McpServer): void {
  defineTool(server, "matchFiles", {
    description: "Find files directly inside a folder by kind (screenshots, images, pdfs, zips, videos, installers, documents, audio), name text, and age. Read-only; returns exact paths to pass to moveItems or trashItems.",
    input: {
      folder: z.string().min(1).describe("Folder to look in (not recursive)"),
      kind: z.enum(["screenshots", "images", "pdfs", "zips", "videos", "installers", "documents", "audio", "any"]).optional(),
      nameContains: z.string().max(80).optional(),
      olderThanDays: z.number().int().min(1).max(3650).optional(),
    },
    annotations: RO,
    handler: async ({ folder, kind, nameContains, olderThanDays }) => {
      const dir = await resolveAllowed(folder, { mustExist: true });
      const k = kind && kind !== "any" ? KINDS[kind] : undefined;
      const cutoff = olderThanDays ? Date.now() - olderThanDays * 86_400_000 : undefined;
      const out: string[] = [];
      for (const e of await fsp.readdir(dir, { withFileTypes: true })) {
        if (!e.isFile() || e.name.startsWith(".")) continue;
        const ext = path.extname(e.name).slice(1).toLowerCase();
        if (k?.ext && !k.ext.includes(ext)) continue;
        if (k?.name && !k.name.test(e.name)) continue;
        if (nameContains && !e.name.toLowerCase().includes(nameContains.toLowerCase())) continue;
        const p = path.join(dir, e.name);
        if (cutoff) { const st = await fsp.stat(p).catch(() => null); if (!st || st.mtimeMs > cutoff) continue; }
        out.push(p);
        if (out.length >= 200) break;
      }
      return out.length ? out.map(display).join("\n") : `No matching files in ${display(dir)}.`;
    },
  });

  defineTool(server, "largestFiles", {
    description: "List the biggest files under a folder (skips node_modules, .git, Pods, build folders). Use to free up disk space.",
    input: { path: z.string().min(1).describe("Folder to scan, e.g. ~/Downloads"), limit: z.number().int().min(1).max(50).optional().describe("How many (default 15)") },
    annotations: RO,
    handler: async ({ path: p, limit }) => {
      const root = await resolveAllowed(p, { mustExist: true });
      const { files, truncated } = await walk(root);
      if (!files.length) return `No files under ${display(root)}.`;
      files.sort((a, b) => b.size - a.size);
      const top = files.slice(0, limit ?? 15);
      const total = files.reduce((s, f) => s + f.size, 0);
      return `Largest files in ${display(root)} (${files.length} files, ${fmtSize(total)} total${truncated ? ", scan capped" : ""}):\n`
        + top.map((f) => `${fmtSize(f.size).padStart(9)}  ${display(f.path)}`).join("\n");
    },
  });

  defineTool(server, "findDuplicates", {
    description: "Find duplicate files (identical content) under a folder, largest wasted space first. Read-only: it only reports.",
    input: { path: z.string().min(1).describe("Folder to scan, e.g. ~/Downloads"), minSizeKB: z.number().int().min(0).optional().describe("Ignore files smaller than this (default 1 KB)") },
    annotations: RO,
    handler: async ({ path: p, minSizeKB }) => {
      const root = await resolveAllowed(p, { mustExist: true });
      const { files, truncated } = await walk(root);
      const min = (minSizeKB ?? 1) * 1024;
      const bySize = new Map<number, Entry[]>();
      for (const f of files) if (f.size >= min && f.size <= 512 * 1048576) (bySize.get(f.size) ?? bySize.set(f.size, []).get(f.size)!).push(f);
      const groups: { size: number; paths: string[] }[] = [];
      for (const [size, same] of bySize) {
        if (same.length < 2) continue;
        const byHash = new Map<string, string[]>();
        for (const f of same) {
          const h = await sha1(f.path).catch(() => null);
          if (h) (byHash.get(h) ?? byHash.set(h, []).get(h)!).push(f.path);
        }
        for (const paths of byHash.values()) if (paths.length > 1) groups.push({ size, paths });
      }
      if (!groups.length) return `No duplicate files under ${display(root)}${truncated ? " (scan capped)" : ""}.`;
      groups.sort((a, b) => b.size * (b.paths.length - 1) - a.size * (a.paths.length - 1));
      const wasted = groups.reduce((s, g) => s + g.size * (g.paths.length - 1), 0);
      return `${groups.length} duplicate set(s) in ${display(root)}, ${fmtSize(wasted)} reclaimable:\n`
        + groups.slice(0, 10).map((g) => `${fmtSize(g.size)} × ${g.paths.length}\n` + g.paths.map((x) => `  ${display(x)}`).join("\n")).join("\n");
    },
  });
}
