#!/usr/bin/env node
// mac-tools: MCP server exposing typed, path-policed macOS tools for MacAgent.
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { rotateAudit } from "./audit.js";
import { registerFileTools } from "./tools/files.js";
import { registerAppTools } from "./tools/apps.js";
import { registerSystemTools } from "./tools/system.js";

export const server = new McpServer({ name: "mac-tools", version: "0.1.0" });

server.registerTool("ping", { description: "Health check.", annotations: { readOnlyHint: true } },
  async () => ({ content: [{ type: "text", text: "pong" }] }));
registerFileTools(server);
registerAppTools(server);
registerSystemTools(server);

process.stdin.on("end", () => process.exit(0));
void rotateAudit();
await server.connect(new StdioServerTransport());
