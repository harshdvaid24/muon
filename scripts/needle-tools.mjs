// Prints Muon's tool schemas (tools/list from the tool server) as JSON, for scripts/needle-data.py.
import { startServer } from "../mac-tools/test/helpers.mjs";
const s = await startServer();
const r = await s.call("tools/list");
console.log(JSON.stringify(r.result.tools, null, 2));
process.exit(0);
