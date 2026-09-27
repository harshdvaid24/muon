import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { startServer } from "./helpers.mjs";

let s;
before(async () => { s = startServer(); await s.init(); });
after(() => s.close());

test("web tools registered with openWorldHint", async () => {
  const by = Object.fromEntries((await s.call("tools/list")).result.tools.map((t) => [t.name, t]));
  assert.equal(by.webSearch?.annotations?.readOnlyHint, true);
  assert.equal(by.webSearch?.annotations?.openWorldHint, true);
  assert.equal(by.openInBrowser?.annotations?.readOnlyHint, false);
});

test("openInBrowser rejects non-http URLs", async () => {
  const r = await s.tool("openInBrowser", { url: "file:///etc/passwd" }).catch((e) => ({ isError: true, text: e.message }));
  // zod .url() may accept file:, our guard rejects it; either way it must not open.
  assert.ok(r.isError, r.text);
});

test("webSearch returns text (or a clear offline error)", async () => {
  const r = await s.tool("webSearch", { query: "what is the speed of light" });
  assert.ok(r.text.length > 0);
  assert.ok(/299|792|light|duckduckgo|timed out|failed/i.test(r.text), r.text);
});
