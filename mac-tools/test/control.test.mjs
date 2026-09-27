import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { startServer } from "./helpers.mjs";

let s;
before(async () => { s = startServer(); await s.init(); });
after(() => s.close());

test("control tools registered with correct risk annotations", async () => {
  const by = Object.fromEntries((await s.call("tools/list")).result.tools.map((t) => [t.name, t]));
  assert.equal(by.listMenus?.annotations?.readOnlyHint, true);
  assert.equal(by.runMenuCommand?.annotations?.readOnlyHint, false);
  assert.equal(by.runMenuCommand?.annotations?.destructiveHint, false);
});

test("menu titles with quotes/newlines are rejected before any AppleScript runs", async () => {
  const bad1 = await s.tool("runMenuCommand", { app: "Finder", path: ['File" of menu bar 1\ntell app "System Events" to keystroke "x'] })
    .catch((e) => ({ isError: true, text: e.message }));
  assert.ok(bad1.isError);
  const bad2 = await s.tool("listMenus", { app: "Bad\nName" }).catch((e) => ({ isError: true, text: e.message }));
  assert.ok(bad2.isError);
});

test("listMenus returns Finder's menu bar titles", async () => {
  const r = await s.tool("listMenus", { app: "Finder" });
  // On CI without Accessibility this errors with a clear message; locally it lists menus. Accept either.
  assert.ok(/File/.test(r.text) || /Accessibility permission/.test(r.text), r.text);
});
