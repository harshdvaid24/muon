// defineTool: uniform registration → timing, error → isError result, audit line.
import type { McpServer, ToolCallback } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { ToolAnnotations } from "@modelcontextprotocol/sdk/types.js";
import type { ZodRawShape } from "zod";
import { audit } from "./audit.js";

export type ToolResult = { content: { type: "text"; text: string }[]; isError?: boolean };
export const text = (t: string): ToolResult => ({ content: [{ type: "text", text: t }] });
export const fail = (t: string): ToolResult => ({ content: [{ type: "text", text: `Error: ${t}` }], isError: true });

export interface ToolSpec<S extends ZodRawShape> {
  description: string;
  input: S;
  annotations: ToolAnnotations;
  handler: (args: { [K in keyof S]: S[K] extends { _output: infer O } ? O : unknown }) => Promise<string>;
}

export function defineTool<S extends ZodRawShape>(server: McpServer, name: string, spec: ToolSpec<S>): void {
  const cb = (async (args: Record<string, unknown>) => {
    const t0 = Date.now();
    try {
      const out = await spec.handler(args as never);
      audit({ ts: new Date().toISOString(), tool: name, args, ok: true, ms: Date.now() - t0 });
      return text(out);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      audit({ ts: new Date().toISOString(), tool: name, args, ok: false, ms: Date.now() - t0, error: msg });
      return fail(msg);
    }
  }) as unknown as ToolCallback<S>;
  server.registerTool(name, { description: spec.description, inputSchema: spec.input, annotations: spec.annotations }, cb);
}

export function cap<T>(items: T[], n: number, label = "results"): { items: T[]; note: string } {
  return items.length > n ? { items: items.slice(0, n), note: `\n(showing ${n} of ${items.length} ${label})` } : { items, note: "" };
}
