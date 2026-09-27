// App control via macOS menu commands (System Events UI scripting). Reaches essentially every
// function an app exposes through its menu bar, without arbitrary code. Needs Accessibility permission.
import fs from "node:fs";
import path from "node:path";
import { createHash } from "node:crypto";
import { pathToFileURL } from "node:url";
import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { defineTool } from "../define.js";
import { run } from "../run.js";
import { resolveAllowed, HOME } from "../paths.js";

const APP_NAME = /^[\w .+&()'-]{1,64}$/;
// A menu title: printable, no newlines/quotes/control chars that could break out of the AppleScript string.
const MENU_ITEM = /^[^\n\r\t"\\]{1,80}$/;
const menuPath = z.array(z.string().regex(MENU_ITEM)).min(1).max(4).describe("Menu path by title, e.g. [\"File\",\"New Window\"] or [\"Format\",\"Font\",\"Bold\"]");

/** AppleScript string literal, safely quoted. Input is already regex-restricted, this is belt-and-braces. */
function asStr(s: string): string { return '"' + s.replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"'; }

/** VS Code remembers layout per workspace under this folder, keyed by md5 of the lower-cased workspace path.
 *  For a workspace it has never seen, seed "side bar, panel and secondary bar hidden" so the first open is
 *  already just the assistant. An existing folder is the user's own choice and is left alone. */
const CODE_STORAGE = path.join(HOME, "Library/Application Support/Code/User/workspaceStorage");
async function seedTerminalOnlyLayout(wsFile: string): Promise<void> {
  const dir = path.join(CODE_STORAGE, createHash("md5").update(wsFile.toLowerCase()).digest("hex"));
  if (fs.existsSync(dir) || !fs.existsSync(CODE_STORAGE)) return;
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, "workspace.json"), JSON.stringify({ workspace: pathToFileURL(wsFile).href }, null, 2));
  await run("/usr/bin/sqlite3", [path.join(dir, "state.vscdb"),
    "CREATE TABLE IF NOT EXISTS ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB); " +
    "INSERT INTO ItemTable(key, value) VALUES ('workbench.sideBar.hidden','true'), ('workbench.panel.hidden','true'), ('workbench.auxiliaryBar.hidden','true');"]);
}

/** What openTerminal may start: interactive coding assistants only, never arbitrary shell text. */
const TERMINAL_COMMANDS = new Set(["", "claude", "claude --continue", "claude --resume", "codex", "gemini", "aider"]);
const AGENT_LABELS: Record<string, string> = { claude: "Claude Code", codex: "Codex", gemini: "Gemini CLI", aider: "Aider" };
const CODE_CLI = ["/usr/local/bin/code", "/opt/homebrew/bin/code", "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"].find((p) => fs.existsSync(p));

async function osa(script: string, timeoutMs = 12000): Promise<string> {
  const res = await run("osascript", ["-e", script], { timeoutMs });
  if (res.code !== 0) {
    const msg = res.stderr.trim();
    if (/-1743|not allowed|assistive|accessibility/i.test(msg)) {
      throw new Error("Accessibility permission is required. Grant Muon in System Settings › Privacy & Security › Accessibility, then try again.");
    }
    if (/-1728|-1719|doesn't understand|Can’t get|Can't get/i.test(msg)) throw new Error("that menu item was not found (check the exact titles with listMenus)");
    if (/-600|not running|-609/i.test(msg)) throw new Error("that application is not running");
    throw new Error(msg || "menu command failed");
  }
  return res.stdout.trim();
}

/** Nested AppleScript reference to a menu item at the given title path. */
function menuRef(path: string[]): string {
  // menu bar item "File" of menu bar 1 → menu 1 → menu item "New Window" of that, nesting submenus.
  let ref = `menu 1 of menu bar item ${asStr(path[0])} of menu bar 1`;
  for (let i = 1; i < path.length - 1; i++) ref = `menu 1 of menu item ${asStr(path[i])} of ${ref}`;
  const leaf = path.length === 1 ? `menu bar item ${asStr(path[0])} of menu bar 1` : `menu item ${asStr(path[path.length - 1])} of ${ref}`;
  return leaf;
}

export function registerControlTools(server: McpServer): void {
  defineTool(server, "listMenus", {
    description: "List an app's menu commands so you know what functions it offers. With no menu, returns the top-level menu titles (File, Edit, View…); with a menu title, returns that menu's items. Read-only.",
    input: { app: z.string().regex(APP_NAME).describe("Running app name, e.g. 'Safari'"), menu: z.string().regex(MENU_ITEM).optional().describe("A top-level menu to expand, e.g. 'File'") },
    annotations: { readOnlyHint: true, destructiveHint: false, openWorldHint: false },
    handler: async ({ app, menu }) => {
      const proc = `application process ${asStr(app)}`;
      const target = menu
        ? `name of menu items of menu 1 of menu bar item ${asStr(menu)} of menu bar 1`
        : `name of menu bar items of menu bar 1`;
      const out = await osa(`tell application "System Events" to tell ${proc} to get ${target}`);
      const items = out.split(", ").map((s) => s.trim()).filter((s) => s && s !== "missing value");
      if (!items.length) return menu ? `${app} ▸ ${menu} has no listable items.` : `No menus found for ${app} (is it running and frontmost-capable?).`;
      return (menu ? `${app} ▸ ${menu}:\n` : `${app} menus:\n`) + items.join("\n");
    },
  });

  defineTool(server, "runMenuCommand", {
    description: "Invoke a menu command in any running app by its title path — this is how you use an app's functions (e.g. Safari ▸ File ▸ New Private Window, Notes ▸ File ▸ New Note). Discover paths with listMenus first. Activates the app, then clicks the item.",
    input: { app: z.string().regex(APP_NAME), path: menuPath },
    annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false },
    handler: async ({ app, path }) => {
      const script = [
        `tell application ${asStr(app)} to activate`,
        `delay 0.15`,
        `tell application "System Events" to tell application process ${asStr(app)}`,
        `  click ${menuRef(path)}`,
        `end tell`,
      ].join("\n");
      await osa(script);
      return `Ran ${app} ▸ ${path.join(" ▸ ")}.`;
    },
  });

  defineTool(server, "openTerminal", {
    description: "Start an interactive coding assistant in a project: Claude Code (claude), Codex, Gemini CLI or Aider, or just a shell. With app 'vscode' it opens a VS Code window for the project with the assistant running in the integrated terminal; otherwise a Terminal window. The user drives the session from there.",
    input: {
      project: z.string().min(1).describe("Project folder path"),
      command: z.string().max(40).optional().describe("claude (default), claude --continue, codex, gemini, aider, or empty for just a shell"),
      app: z.enum(["vscode", "terminal"]).optional().describe("'vscode': a VS Code window for the project, assistant in its terminal; 'terminal' (default): Terminal.app"),
    },
    annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false },
    handler: async ({ project, command = "claude", app = "terminal" }) => {
      const dir = await resolveAllowed(project, { mustExist: true });
      const cmd = command.trim();
      if (!TERMINAL_COMMANDS.has(cmd)) throw new Error(`only these can be started: ${[...TERMINAL_COMMANDS].filter(Boolean).join(", ")}`);
      const name = path.basename(dir);
      // VS Code: a workspace file inside the project with a task that runs on open, so the assistant starts in the
      // integrated terminal of a window for that project. No keystrokes: they can land in another window.
      if (app === "vscode" && CODE_CLI) {
        const wsDir = path.join(dir, ".muon");
        fs.mkdirSync(wsDir, { recursive: true });
        const who = cmd ? (AGENT_LABELS[cmd.split(" ")[0]] ?? cmd) : "Shell";
        // The window is just the assistant: VS Code opens a terminal in the editor area on startup, and the
        // workspace's default terminal profile runs the assistant, so nothing is typed and no task is needed.
        // No activity bar, tabs or status bar. One stable workspace file per project, so VS Code remembers the
        // layout (hide the side bar once with ⌘B) and an open window is focused instead of duplicated.
        const profile = cmd ? { path: "/bin/zsh", args: ["-lic", cmd], icon: "sparkle" } : { path: "/bin/zsh", args: ["-l"] };
        const ws = {
          folders: [{ path: ".." }],
          settings: {
            "workbench.startupEditor": "terminal",
            "terminal.integrated.profiles.osx": { [who]: profile },
            "terminal.integrated.defaultProfile.osx": who,
            "terminal.integrated.defaultLocation": "editor",
            "terminal.integrated.enablePersistentSessions": false,
            "terminal.integrated.confirmOnExit": "never",
            "workbench.activityBar.location": "hidden",
            "workbench.secondarySideBar.defaultVisibility": "hidden",
            "workbench.editor.showTabs": "none",
            "workbench.statusBar.visible": false,
          },
        };
        const wsFile = path.join(wsDir, `${name}.code-workspace`);
        for (const old of fs.readdirSync(wsDir).filter((f) => f.endsWith(".code-workspace") && f !== `${name}.code-workspace`)) fs.rmSync(path.join(wsDir, old), { force: true });
        const openWindows = await osa('tell application "System Events" to tell process "Code" to get name of windows').catch(() => "");
        const alreadyOpen = openWindows.toLowerCase().includes(`${name} (workspace)`.toLowerCase());
        fs.writeFileSync(wsFile, JSON.stringify(ws, null, 2));
        await seedTerminalOnlyLayout(wsFile).catch(() => { /* layout seeding is best effort */ });
        const exclude = path.join(dir, ".git", "info", "exclude");
        try {
          if (fs.existsSync(path.join(dir, ".git"))) {
            fs.mkdirSync(path.dirname(exclude), { recursive: true });
            const cur = fs.existsSync(exclude) ? fs.readFileSync(exclude, "utf8") : "";
            if (!cur.split("\n").includes(".muon/")) fs.appendFileSync(exclude, `${cur.endsWith("\n") || !cur ? "" : "\n"}.muon/\n`);
          }
        } catch { /* keeping the repo clean is best effort */ }
        await run(CODE_CLI, [wsFile], { timeoutMs: 15000 });
        if (alreadyOpen) return `${who} for ${name} is already open in VS Code; brought that window to the front. Close it and ask again for a fresh session.`;
        return `Opened a VS Code window for ${name} with ${who} running in it. Take it from there. (If VS Code asks whether to trust the folder, choose Trust.)`;
      }
      const shellDir = "'" + dir.replace(/'/g, "'\\''") + "'";
      await osa(`tell application "Terminal" to do script ${asStr(`cd ${shellDir}${cmd ? " && " + cmd : ""}`)}`);
      await osa('tell application "Terminal" to activate');
      return `Opened a Terminal window in ${name}${cmd ? ` running ${cmd}` : ""}. Take it from there.`;
    },
  });
}
