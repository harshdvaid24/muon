// App control via macOS menu commands (System Events UI scripting). Reaches essentially every
// function an app exposes through its menu bar, without arbitrary code. Needs Accessibility permission.
import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { defineTool } from "../define.js";
import { run } from "../run.js";

const APP_NAME = /^[\w .+&()'-]{1,64}$/;
// A menu title: printable, no newlines/quotes/control chars that could break out of the AppleScript string.
const MENU_ITEM = /^[^\n\r\t"\\]{1,80}$/;
const menuPath = z.array(z.string().regex(MENU_ITEM)).min(1).max(4).describe("Menu path by title, e.g. [\"File\",\"New Window\"] or [\"Format\",\"Font\",\"Bold\"]");

/** AppleScript string literal, safely quoted. Input is already regex-restricted, this is belt-and-braces. */
function asStr(s: string): string { return '"' + s.replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"'; }

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
}
