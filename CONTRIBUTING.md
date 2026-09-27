# Contributing to Muon

Thanks for your interest! Muon has two parts:

- **`Muon/`** — the macOS app (Swift, AppKit + SwiftUI). Requires macOS 26 and Xcode 26.
- **`mac-tools/`** — the MCP tool server (TypeScript, Node ≥ 20). Cross-editor; testable without Xcode.

## Setup

```bash
git clone https://github.com/harshdvaid24/muon.git
cd muon/mac-tools && npm install && npm run build && cd ..
scripts/build.sh          # generates the Xcode project and builds the app
```

## Tests

```bash
cd mac-tools && npm test   # tool server (node --test)
scripts/build.sh test      # app (Swift Testing)
```

Please add a test with any behavior change. Security-bearing code (path policy,
permissions, menu-command escaping) must keep its tests green.

## Ground rules

- No new runtime dependencies without discussion — the design goal is a tiny idle footprint.
- Never widen the tool surface past typed tools. The LLM must never get a shell.
- Filesystem tests that verify a *refusal* must run against a throwaway sandbox, never real folders.

Open an issue before large changes so we can agree on the approach.
