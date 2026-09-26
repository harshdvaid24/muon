// Audit log: one JSON line per tool call. Paths/args only, never file contents.
import fs from "node:fs";
import fsp from "node:fs/promises";
import path from "node:path";
import { HOME } from "./paths.js";

export const DATA_DIR = path.join(HOME, "Library/Application Support/MacAgent");
export const AUDIT_FILE = path.join(DATA_DIR, "audit.jsonl");
const KEEP_DAYS = 30;

export interface AuditEntry { ts: string; tool: string; args: Record<string, unknown>; ok: boolean; ms: number; error?: string }

export function audit(entry: AuditEntry): void {
  try {
    fs.mkdirSync(DATA_DIR, { recursive: true });
    fs.appendFileSync(AUDIT_FILE, JSON.stringify(entry) + "\n");
  } catch { /* auditing must never break a tool call */ }
}

/** Drop entries older than KEEP_DAYS. Runs once at startup. */
export async function rotateAudit(): Promise<void> {
  try {
    const raw = await fsp.readFile(AUDIT_FILE, "utf8");
    const cutoff = Date.now() - KEEP_DAYS * 86_400_000;
    const kept = raw.split("\n").filter((l) => {
      if (!l.trim()) return false;
      try { return Date.parse(JSON.parse(l).ts) >= cutoff; } catch { return false; }
    });
    if (kept.length !== raw.split("\n").filter((l) => l.trim()).length) await fsp.writeFile(AUDIT_FILE, kept.join("\n") + (kept.length ? "\n" : ""));
  } catch { /* no file yet */ }
}
