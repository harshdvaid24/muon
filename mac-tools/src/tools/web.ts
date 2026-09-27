// Basic web search via DuckDuckGo. The one tool that reaches the network (openWorldHint), read-only.
import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { defineTool } from "../define.js";
import { run } from "../run.js";

const WEB = { readOnlyHint: true, destructiveHint: false, openWorldHint: true } as const;

export function registerWebTools(server: McpServer): void {
  defineTool(server, "webSearch", {
    description: "Search the web for a quick answer (DuckDuckGo). Use for general knowledge, definitions, or current info. Returns a short summary plus a few result links. This is the only tool that uses the network.",
    input: { query: z.string().min(1).max(400).describe("What to look up") },
    annotations: WEB,
    handler: async ({ query }) => {
      const ia = `https://api.duckduckgo.com/?q=${encodeURIComponent(query)}&format=json&no_html=1&skip_disambig=1&t=macagent`;
      let data: any;
      try {
        const res = await fetch(ia, { signal: AbortSignal.timeout(8000), headers: { "User-Agent": "Muon/0.1" } });
        if (!res.ok) throw new Error(`search returned HTTP ${res.status}`);
        data = await res.json();
      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        if (/abort|timeout/i.test(msg)) throw new Error("web search timed out (no internet?)");
        throw new Error(`web search failed: ${msg}`);
      }
      const out: string[] = [];
      const head = data.Heading ? String(data.Heading) : "";
      const abstract = (data.AbstractText || data.Answer || data.Definition || "").toString().trim();
      if (abstract) out.push(head ? `${head}: ${abstract}` : abstract);
      const src = data.AbstractURL || data.DefinitionURL;
      if (abstract && src) out.push(String(src));
      const topics = Array.isArray(data.RelatedTopics) ? data.RelatedTopics : [];
      const flat: any[] = [];
      for (const t of topics) { if (t.Text) flat.push(t); else if (Array.isArray(t.Topics)) flat.push(...t.Topics); }
      for (const t of flat.slice(0, abstract ? 3 : 5)) {
        if (t.Text) out.push(`• ${t.Text}${t.FirstURL ? `\n  ${t.FirstURL}` : ""}`);
      }
      if (!out.length) return `No instant answer for "${query}". Full results: https://duckduckgo.com/?q=${encodeURIComponent(query)}`;
      return out.join("\n");
    },
  });

  defineTool(server, "openInBrowser", {
    description: "Open a web search or a URL in the default browser. Use when the user wants to see full results or a page.",
    input: { query: z.string().min(1).max(400).optional().describe("Search terms"), url: z.string().url().optional().describe("A full http(s) URL") },
    annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: true },
    handler: async ({ query, url }) => {
      let target: string;
      if (url) {
        if (!/^https?:\/\//i.test(url)) throw new Error("only http(s) URLs are allowed");
        target = url;
      } else if (query) {
        target = `https://duckduckgo.com/?q=${encodeURIComponent(query)}`;
      } else {
        throw new Error("provide a query or a url");
      }
      const res = await run("open", [target]);
      if (res.code !== 0) throw new Error(res.stderr.trim() || "could not open browser");
      return `Opened ${target}`;
    },
  });
}
