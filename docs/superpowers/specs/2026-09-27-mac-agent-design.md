# Muon — Design Spec (2026-09-27)

## Goal
Local, offline AI agent for MacBook Air M4 (24 GB, macOS 26.6) that searches/manages files, opens/quits apps, runs machine tasks, learns user habits, and never raises idle load. Native Liquid Glass UI, menu bar resident, hotkey + Spotlight/Shortcuts entry points.

## Decisions (approved 2026-09-27)
| # | Decision | Value |
|---|---|---|
| 1 | Host | **C**: Swift menu bar app (host) + TypeScript MCP tool server |
| 2 | LLM runtime | **LM Studio, MLX engine**, JIT load, TTL unload |
| 3 | Hotkey | ⌃⌥Space |
| 4 | Allowed dirs | ~/Projects, ~/Work, ~/Downloads, ~/Documents, ~/Desktop |
| 5 | Heavy 20B tier | dropped |
| 6 | Menu bar icon | SF Symbol `sparkle.magnifyingglass`, template |
| 7 | UI | Liquid Glass, system components only |

## Architecture
```
hotkey / menu bar / Spotlight (App Intents) / wisp:// URL
        │
        ▼
┌──────────────────────── Muon.app (Swift, ~40 MB idle) ────────────────────────┐
│ Palette UI (glass)  ·  Confirm UI  ·  Settings  ·  Audit viewer                    │
│ Tier 0  SQLite memory: intent cache, aliases, usage frecency, macros (no model)    │
│ Tier 1  Apple Foundation Models (on-device, OS-managed) → guided `Command` struct   │
│ Tier 2  LM Studio /v1/chat/completions, tools, ttl=300 → agent loop (≤8 iters)     │
│ ResourceGate: thermal, memory pressure, low power, battery, builds running         │
│ MCP client (stdio JSON-RPC): spawns node on demand, kills after 5 min idle         │
└───────────────────────────────────┬────────────────────────────────────────────────┘
                                    │ stdio
┌──────────────────────── mac-tools (TypeScript MCP server) ─────────────────────────┐
│ Typed tools only. execFile with argv arrays. No shell. Path policy. Audit JSONL.   │
│ Annotations: readOnlyHint / destructiveHint drive host confirmation.               │
│ Reusable from LM Studio chat (mcp.json) and Claude Code / Claude Desktop.          │
└────────────────────────────────────────────────────────────────────────────────────┘
```

## Inference tiers
| Tier | Engine | Cost | Use |
|---|---|---|---|
| 0 | SQLite intent cache + macros | 0 | repeated commands, learned shortcuts |
| 1 | Foundation Models, guided generation into `Command` | ~0.5 s, 0 app RAM | single-step commands; `confidence < 0.6` or `.complex` → tier 2 |
| 2 | LM Studio, `qwen3-8b` MLX 4-bit (`/no_think`), `ttl: 300` | ~5 GB while loaded | multi-step, codebase questions |

Tier 2 only loads when ResourceGate passes: thermalState ∈ {nominal, fair}, memory pressure normal, not Low Power Mode, AC or battery > 25 %, no `xcodebuild`/`gradle`/`ffmpeg` running. Otherwise stay at tier 1 and say why.

## Self-learning (bounded, load-reducing)
SQLite at `~/Library/Application Support/Muon/memory.db`.
- `intent_cache(key PK, tool, args_json, hits, last_used, ok)` — key = lowercased, whitespace-collapsed, punctuation-stripped query. Hit executes directly (still confirms non-auto tools). Invalidated on failure.
- `aliases(term PK, path, hits, last_used)` — learned when a project/path resolution succeeds ("portfolio" → ~/Work/portfolio).
- `usage(kind, name PK(kind,name), hits, last_used)` — app/path frecency for ranking + disambiguation; `kind='seq'` rows count repeated 2-step sequences.
- `macros(name PK, steps_json, hits, last_used)` — saved on "save macro <name>" or accepted suggestion after a sequence repeats 3×.
Bounds: ≤ 300 rows per table, frecency = hits × 0.5^(age_days/14), evict lowest on insert, prune on launch. Prompt injection fixed: top 15 aliases + top 10 apps. No embeddings, no fine-tune, no daemon, no timers.

## Tools (MCP, mac-tools)
Phase 1 (readOnlyHint / safe): `searchFiles(query, scope?)` mdfind · `findFiles(name, scope?)` rg --files -g · `searchCode(pattern, scope?)` rg · `readFile(path)` ≤ 20 KB · `listDirectory(path)` · `listRunningApps()` with RSS · `getSystemStats()` · `openApplication(name)` · `openPath(path, app?)` · `revealInFinder(path)` · `listProjects()`.
Phase 2 (confirm): `moveItem(from,to)` · `copyItem(from,to)` · `renameItem(path,newName)` · `createFolder(path)` · `trashItem(path)` (reversible; never permanent delete) · `quitApplication(name)`.
Phase 3 (destructiveHint → modal): `killProcess(pid)` · `clearDevCache(kind)`.
Never: shell, sudo, launchctl, diskutil, csrutil, nvram, rm -rf, permanent delete.
Caps: ≤ 20 results, ≤ 50 file ops/request, ≤ 20 KB read.

## Path policy (in mac-tools, enforced on every path arg)
normalize → resolve symlinks (realpath, or parent realpath for new paths) → must start with an allowed root → must not start with a denied root (`~/Library`, `~/.ssh`, `~/.gnupg`, `~/.aws`, `~/.config`, `/System`, `/private`, `/usr`, `/bin`, `/sbin`, `/Library`, `/etc`, `/var`) → reject otherwise with a clear error.

## Host permission rule
`readOnlyHint` → auto · host whitelist (`openApplication`, `openPath`, `revealInFinder`) → auto · `destructiveHint` → native alert · everything else (incl. unknown tools) → inline glass confirm card with "Always allow in this folder" toggle (stored in UserDefaults keyed by tool+parent dir).

## UI (Liquid Glass, macOS 26)
- `NSStatusItem` template SF Symbol. Left click → panel anchored under icon. Right click → native `NSMenu` (recent, macros, model status/unload, Settings, Quit).
- Hotkey → same panel centered, upper third, Spotlight-style. Borderless transparent `NSPanel`, floating, key window, activates app.
- Root view `.glassEffect(.regular, in: .rect(cornerRadius: 28))` inside `GlassEffectContainer`; search capsule at idle, expands to results; `glassEffectID` morph.
- Esc closes · ↑↓⏎ · click-outside dismiss. Semantic colors, system fonts, SF Symbols only.
- Confirm card: `.glass` Cancel, `.glassProminent` Allow. Modal: SwiftUI `.alert`.
- Settings: own `NSWindow` hosting `Form` `.formStyle(.grouped)` (model name, port, hotkey display, allowed dirs list, model TTL).
- Notifications via `UNUserNotificationCenter` for long tasks.

## Entry points
- Hotkey ⌃⌥Space (Carbon `RegisterEventHotKey`, no Accessibility permission).
- `wisp://ask?q=...` URL scheme (scripts, Shortcuts, Raycast).
- App Intents: `AskMuon(request)`, `OpenProject(project: ProjectEntity)`, `RunMacro(macro: MacroEntity)`; `AppShortcutsProvider` phrases → Spotlight (macOS 26), Shortcuts.app, Siri.
- CLI debug: `Muon.app/Contents/MacOS/Muon --query "..." [--yes]` prints JSON, exits.

## Audit
`~/Library/Application Support/Muon/audit.jsonl`: `{ts, tool, args (paths only), result, tier, ms}`. Rotate > 30 days on launch. Never file contents.

## Startup
Login item: Muon.app only. LM Studio started lazily (`lms server start`) on first tier-2 need. Node spawned on first tool call, exits after 5 min idle. Idle = 1 process.

## Non-goals
Permanent delete, package install, GUI/screen automation, cloud models, fine-tuning, background indexing.

## Success metrics
- Idle RSS of Muon < 60 MB, 0 timers.
- ≥ 70 % of a 20-command fixture resolved at tier 0/1 after one week of use.
- Path policy tests: `..`, symlink escape, denied roots all rejected.
