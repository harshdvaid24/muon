# Muon 0.3.4: exact figures, start your coding assistant by project name

- **Exact figures from documents.** *"find the largest transaction"*, *"smallest payment"*, *"how much did I spend in total"* on a statement or invoice: Muon computes the answer from the text (running balances and total rows excluded), shows it first, and lets the model only explain what the document is. Small models no longer misread tables.
- **Dense documents no longer fail.** Text that overflows the on-device window (tables, numbers) is retried in smaller parts automatically instead of "Exceeded model context window size".
- **Start your coding assistant by project name.** *"start claude code for kathak"*, *"start agent for kathak app"*, *"open codex in weather-app"*: the project opens in VS Code and a Terminal window in that folder starts the interactive assistant. Only claude, codex, gemini and aider can be started; you drive the session.

Everything in [0.3.3](https://github.com/harshdvaid24/muon/releases/tag/v0.3.3) applies.
