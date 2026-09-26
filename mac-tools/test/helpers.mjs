// Minimal JSON-RPC-over-stdio client for testing the MCP server end to end.
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";

export const DIST = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../dist/index.js");

export function startServer(env = {}) {
  const proc = spawn(process.execPath, [DIST], { stdio: ["pipe", "pipe", "inherit"], env: { ...process.env, ...env } });
  const pending = new Map();
  let buf = "";
  let id = 0;
  proc.stdout.on("data", (d) => {
    buf += d.toString();
    let i;
    while ((i = buf.indexOf("\n")) >= 0) {
      const line = buf.slice(0, i).trim();
      buf = buf.slice(i + 1);
      if (!line) continue;
      const msg = JSON.parse(line);
      if (msg.id != null && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); }
    }
  });
  const send = (obj) => proc.stdin.write(JSON.stringify(obj) + "\n");
  const call = (method, params = {}) => new Promise((resolve, reject) => {
    const mid = ++id;
    const t = setTimeout(() => { pending.delete(mid); reject(new Error(`timeout: ${method}`)); }, 15000);
    pending.set(mid, (m) => { clearTimeout(t); resolve(m); });
    send({ jsonrpc: "2.0", id: mid, method, params });
  });
  const init = async () => {
    const r = await call("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "test", version: "0" } });
    send({ jsonrpc: "2.0", method: "notifications/initialized" });
    return r;
  };
  const tool = async (name, args = {}) => {
    const r = await call("tools/call", { name, arguments: args });
    if (r.error) throw new Error(r.error.message);
    const text = (r.result.content ?? []).filter((c) => c.type === "text").map((c) => c.text).join("\n");
    return { text, isError: !!r.result.isError, raw: r.result };
  };
  return { proc, call, init, tool, close: () => proc.kill() };
}
