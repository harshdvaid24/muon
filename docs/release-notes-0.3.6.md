# Muon 0.3.6: the assistant window

- **"start claude code for kathak"** opens a VS Code window for that project that is just the assistant: Claude Code (or Codex, Gemini CLI, Aider) fills the window, no side bars, tabs, status bar or start page, newest `claude` from your login shell. Muon writes `<project>/.muon/<name>.code-workspace` (git-excluded locally) with a terminal profile that runs the assistant and seeds VS Code's remembered layout for it. If that window is already open, it is brought to the front; close it and ask again for a fresh session. No automatic-tasks setting needed any more.

Everything in [0.3.5](https://github.com/harshdvaid24/muon/releases/tag/v0.3.5) applies.
