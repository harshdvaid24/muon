// Path policy: every filesystem argument passes through resolveAllowed().
// normalize → expand ~ → resolve symlinks → reject denied roots → require an allowed root.
import os from "node:os";
import path from "node:path";
import fs from "node:fs/promises";
import { realpathSync } from "node:fs";

export const HOME = os.homedir();

export function expandHome(p: string): string {
  if (p === "~") return HOME;
  if (p.startsWith("~/")) return path.join(HOME, p.slice(2));
  return p;
}

const DEFAULT_ALLOWED = ["~/Projects", "~/Work", "~/Downloads", "~/Documents", "~/Desktop"];

/** On-disk spelling of a path (APFS is case-insensitive; realpath returns the real case). Missing paths stay as typed. */
function canonical(p: string): string {
  try { return realpathSync.native(p); } catch { return p; }   // .native = OS realpath: returns the on-disk case
}
const envRoots = process.env.MUON_ALLOWED_ROOTS;
export const ALLOWED_ROOTS: string[] = (envRoots ? envRoots.split(":").filter(Boolean) : DEFAULT_ALLOWED)
  .map((p) => canonical(path.resolve(expandHome(p))));

export const DENIED_ROOTS: string[] = [
  "~/Library", "~/.ssh", "~/.gnupg", "~/.aws", "~/.config", "~/.docker", "~/.kube",
  "/System", "/private", "/usr", "/bin", "/sbin", "/Library", "/etc", "/var", "/Applications",
].map((p) => canonical(path.resolve(expandHome(p))));

export class PathError extends Error {
  constructor(message: string, public readonly input: string) { super(message); this.name = "PathError"; }
}

function under(p: string, root: string): boolean { return p === root || p.startsWith(root + path.sep); }

export async function resolveAllowed(input: string, opts: { mustExist?: boolean } = {}): Promise<string> {
  if (typeof input !== "string" || !input.trim()) throw new PathError("empty path", String(input));
  const abs = path.resolve(expandHome(input.trim()));
  let real: string;
  try {
    real = await fs.realpath(abs);
  } catch (e) {
    const code = (e as NodeJS.ErrnoException).code;
    if (code !== "ENOENT" || opts.mustExist) throw new PathError(`path does not exist: ${abs}`, input);
    // New path: realpath the nearest existing ancestor, re-append the missing tail.
    let base = abs;
    const tail: string[] = [];
    while (true) {
      const parent = path.dirname(base);
      if (parent === base) throw new PathError(`no existing parent for ${abs}`, input);
      tail.unshift(path.basename(base));
      base = parent;
      try { base = await fs.realpath(base); break; } catch { /* keep walking up */ }
    }
    real = path.join(base, ...tail);
  }
  if (DENIED_ROOTS.some((r) => under(real, r))) throw new PathError(`path is protected: ${display(real)}`, input);
  if (!ALLOWED_ROOTS.some((r) => under(real, r))) {
    throw new PathError(`path is outside allowed folders (${ALLOWED_ROOTS.map(display).join(", ")}): ${display(real)}`, input);
  }
  return real;
}

export function display(p: string): string { return p.startsWith(HOME + path.sep) || p === HOME ? "~" + p.slice(HOME.length) : p; }
