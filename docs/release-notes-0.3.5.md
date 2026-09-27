# Muon 0.3.5: start your coding assistant inside VS Code

- **"start claude code for kathak"** now opens a new VS Code window for that project with Claude Code (or Codex, Gemini CLI, Aider) already running in the integrated terminal. Muon writes a small workspace file under `<project>/.muon/` (git-excluded locally) whose task starts the assistant when the window opens; nothing is typed into any window. Turn on VS Code's **Task: Allow Automatic Tasks** setting once. Without the `code` command line tool, a Terminal window is used instead.

Everything in [0.3.4](https://github.com/harshdvaid24/muon/releases/tag/v0.3.4) applies.
