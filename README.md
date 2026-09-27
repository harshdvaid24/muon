# MacAgent

Local, offline AI agent for macOS 26 on Apple Silicon. Menu bar resident, Liquid Glass palette, zero idle load.

```
⌃⌥Space  →  glass palette  →  tier 0 memory (0 ms) → tier 1 Apple on-device model (~1 s) → tier 2 LM Studio (MLX, on demand)
                                                        │
                                              mac-tools (TypeScript MCP server, spawned on demand, exits after 5 min idle)
```

## Run

```bash
cd mac-tools && npm install && npm run build && cd ..
scripts/build.sh          # XcodeGen + xcodebuild (Debug)
scripts/run.sh            # launch build/DerivedData/Build/Products/Debug/MacAgent.app
scripts/build.sh test     # Swift tests;  cd mac-tools && npm test  for the tool server
scripts/fixture.sh        # 20 read-only queries: tier + latency
```

Requirements: macOS 26 with Apple Intelligence on (tier 1), Node ≥ 20, LM Studio with `lms` bootstrapped (tier 2):

```bash
lms get qwen/qwen3.5-9b@4bit --mlx -y     # main model (~6 GB)
lms get qwen/qwen3.5-4b@4bit --mlx -y     # low-memory fallback (~3 GB)
```

## Entry points

| How | What |
|---|---|
| ⌃⌥Space (Settings → Hotkey to change) | palette, bottom-center |
| Menu bar icon | palette anchored under icon; right-click for model status, macros, Settings |
| Spotlight / Shortcuts / Siri | App Intents: Open Project, Ask MacAgent, Run Macro |
| `open "macagent://ask?q=open%20kathak"` | scripts, Raycast, Shortcuts |
| `MacAgent.app/Contents/MacOS/MacAgent --query "…" [--yes] [--tier 2]` | headless, prints tier/tools/answer |

Try: `open kathak in vs code` · `find pdfs about invoices` · `which apps use the most memory` · `quit spotify` · `how many react native projects do I have and which use firebase?` · `save macro morning`.

## Safety model

- No shell exists. Every tool is a typed TypeScript function calling `execFile` with argv arrays; binaries allowlisted.
- Every path is normalized, symlink-resolved, must be under an allowed folder (`~/Projects ~/Work ~/Downloads ~/Documents ~/Desktop`) and never under a protected one (`~/Library ~/.ssh ~/.aws /System /private …`).
- Read-only tools run automatically. Move/copy/rename/trash/quit ask in the palette (with "Always allow in <folder>"). Kill process asks via a native alert. Delete = Trash, never `rm`.
- Audit log: `~/Library/Application Support/MacAgent/audit.jsonl` (30 days, paths only).
- Tier 2 loads only when the Mac can afford it: thermal state, memory pressure, Low Power Mode, battery, running builds. Tight memory → 4B fallback model.

## Learning (bounded)

`~/Library/Application Support/MacAgent/memory.db`: intent cache, project aliases, app/path frecency, macros. ≤ 300 rows per table, 14-day half-life, pruned at launch. More use → more requests served at tier 0 with no model at all.

## Reuse the tool server elsewhere

`mac-tools` is a standard MCP server (stdio). Already registered in `~/.lmstudio/mcp.json`. For Claude Code:

```bash
claude mcp add mac-tools -- node ~/Work/MacAgent/mac-tools/dist/index.js
```

## Known limitations

- LM Studio ignores `lms load --context-length` for the MLX Qwen3.5 models (API reports `loaded_context_length: 123648`). MLX grows the KV cache with actual tokens and the agent loop is bounded (≤ 8 steps, ≤ 20 results per tool), so memory stays near the weights (~3 GB for 4B, ~6 GB for 9B). To hard-cap it, set the model's Context Length in LM Studio → My Models → model settings.
- Tier 1 needs Apple Intelligence enabled; without it every request goes to LM Studio.
- `mac-tools` is run from the repo path (see Settings → Tool server); it is not bundled into the .app yet.
- Hotkey presets only (⌘⇧Space default); free-form recorder not yet implemented.

## Controlling any app

`runMenuCommand(app, path)` clicks a menu item in any running app, so MacAgent can use essentially every function an app exposes — e.g. `Safari ▸ File ▸ New Private Window`, `Notes ▸ File ▸ New Note`. `listMenus(app[, menu])` discovers the titles. Menu control is confirm-gated (asked before each run) and requires Accessibility permission (Settings › App control › Grant, or System Settings › Privacy & Security › Accessibility). Menu titles are validated, so a title can never inject AppleScript.
