import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { defineTool } from "../define.js";
import { run } from "../run.js";
import { resolveAllowed, display } from "../paths.js";

const APP_NAME = /^[\w .+&()'-]{1,64}$/;
const SAFE = { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false } as const;

export function registerAppTools(server: McpServer): void {
  defineTool(server, "listRunningApps", {
    description: "List running GUI applications with memory use (MB), highest first.",
    input: {},
    annotations: { readOnlyHint: true, destructiveHint: false, openWorldHint: false },
    handler: async () => {
      const res = await run("ps", ["-axo", "pid=,rss=,comm="]);
      const byApp = new Map<string, { mb: number; pids: number[] }>();
      for (const line of res.stdout.split("\n")) {
        const m = line.trim().match(/^(\d+)\s+(\d+)\s+(.+)$/);
        if (!m) continue;
        if (!m[3].includes(".app/Contents/MacOS/")) continue;
        const outer = m[3].split("/").find((seg) => seg.endsWith(".app"));
        if (!outer) continue;
        const name = outer.slice(0, -4);
        const e = byApp.get(name) ?? { mb: 0, pids: [] };
        e.mb += Number(m[2]) / 1024; e.pids.push(Number(m[1]));
        byApp.set(name, e);
      }
      const rows = [...byApp].sort((a, b) => b[1].mb - a[1].mb).slice(0, 30);
      return rows.map(([n, e]) => `${e.mb.toFixed(0).padStart(6)} MB  ${n}  (pid ${e.pids[0]}${e.pids.length > 1 ? ` +${e.pids.length - 1}` : ""})`).join("\n");
    },
  });

  defineTool(server, "openApplication", {
    description: "Launch or bring to front an application by name, e.g. 'Visual Studio Code', 'Xcode', 'Safari'.",
    input: { name: z.string().regex(APP_NAME).describe("Application name as shown in /Applications") },
    annotations: SAFE,
    handler: async ({ name }) => {
      const res = await run("open", ["-a", name]);
      if (res.code !== 0) throw new Error(res.stderr.trim() || `could not open ${name}`);
      return `Opened ${name}.`;
    },
  });

  defineTool(server, "openPath", {
    description: "Open a file or folder with its default app, or with a named app (e.g. open a project folder in 'Visual Studio Code' or an .xcworkspace in Xcode).",
    input: { path: z.string().min(1).describe("File or folder path"), app: z.string().regex(APP_NAME).optional().describe("Application to open it with") },
    annotations: SAFE,
    handler: async ({ path: p, app }) => {
      const real = await resolveAllowed(p, { mustExist: true });
      const res = await run("open", app ? ["-a", app, real] : [real]);
      if (res.code !== 0) throw new Error(res.stderr.trim() || `could not open ${display(real)}`);
      return `Opened ${display(real)}${app ? ` in ${app}` : ""}.`;
    },
  });

  defineTool(server, "revealInFinder", {
    description: "Reveal a file or folder in Finder.",
    input: { path: z.string().min(1) },
    annotations: SAFE,
    handler: async ({ path: p }) => {
      const real = await resolveAllowed(p, { mustExist: true });
      const res = await run("open", ["-R", real]);
      if (res.code !== 0) throw new Error(res.stderr.trim() || "could not reveal");
      return `Revealed ${display(real)} in Finder.`;
    },
  });
}
