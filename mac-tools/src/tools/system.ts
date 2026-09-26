import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { defineTool } from "../define.js";
import { run } from "../run.js";

export function registerSystemTools(server: McpServer): void {
  defineTool(server, "getSystemStats", {
    description: "CPU load, RAM free/used, disk free, battery and thermal status.",
    input: {},
    annotations: { readOnlyHint: true, destructiveHint: false, openWorldHint: false },
    handler: async () => {
      const [vm, mem, df, batt, therm, load, ncpu] = await Promise.all([
        run("vm_stat", []), run("sysctl", ["-n", "hw.memsize"]), run("df", ["-k", "/"]),
        run("pmset", ["-g", "batt"]), run("pmset", ["-g", "therm"]), run("sysctl", ["-n", "vm.loadavg"]), run("sysctl", ["-n", "hw.ncpu"]),
      ]);
      const page = Number(vm.stdout.match(/page size of (\d+)/)?.[1] ?? 16384);
      const pages = (k: string) => Number(vm.stdout.match(new RegExp(`${k}:\\s+(\\d+)`))?.[1] ?? 0);
      const gb = (p: number) => (p * page / 1073741824).toFixed(1);
      const total = (Number(mem.stdout.trim()) / 1073741824).toFixed(0);
      const free = gb(pages("Pages free") + pages("Pages inactive") + pages("Pages speculative"));
      const wired = gb(pages("Pages wired down")), compressed = gb(pages("Pages occupied by compressor"));
      const dfl = df.stdout.trim().split("\n").pop()?.trim().split(/\s+/) ?? [];
      const diskFree = dfl[3] ? (Number(dfl[3]) / 1048576).toFixed(0) + " GB free" : "?";
      const battery = batt.stdout.split("\n").find((l) => l.includes("%"))?.trim().replace(/\s+/g, " ") ?? "no battery info";
      const power = batt.stdout.includes("AC Power") ? "AC power" : "battery";
      const thermal = /No thermal warning/.test(therm.stdout) ? "nominal" : (therm.stdout.match(/CPU_Speed_Limit\s*=\s*(\d+)/)?.[0] ?? "see pmset");
      return [
        `RAM: ${total} GB total, ~${free} GB available, ${wired} GB wired, ${compressed} GB compressed`,
        `CPU load (1/5/15 min): ${load.stdout.trim().replace(/[{}]/g, "").trim()} on ${ncpu.stdout.trim()} cores`,
        `Disk: ${diskFree}`, `Power: ${power}; ${battery}`, `Thermal: ${thermal}`,
      ].join("\n");
    },
  });
}
