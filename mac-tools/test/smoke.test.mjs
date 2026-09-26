import { test } from "node:test";
import assert from "node:assert/strict";
import { startServer } from "./helpers.mjs";

test("initialize + tools/list includes ping with readOnlyHint", async () => {
  const s = startServer();
  try {
    const init = await s.init();
    assert.equal(init.result.serverInfo.name, "mac-tools");
    const list = await s.call("tools/list");
    const ping = list.result.tools.find((t) => t.name === "ping");
    assert.ok(ping, "ping tool registered");
    assert.equal(ping.annotations?.readOnlyHint, true);
    const r = await s.tool("ping");
    assert.equal(r.text, "pong");
  } finally { s.close(); }
});
