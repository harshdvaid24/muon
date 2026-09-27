# Muon 0.2.0: the everyday AI, on-device

Muon is a menu bar app for macOS 26. Press `⇧⌥Space` and ask. This release turns Muon from a file and disk helper into an everyday assistant: the things people open a chatbot for, and the things they do by hand, done on your Mac with Apple's on-device model. Nothing leaves your Mac unless you ask for a web page.

![Muon demo](https://raw.githubusercontent.com/harshdvaid24/muon/main/docs/media/demo.gif)

## Highlights

- **Writing help on any text.** Copy text in any app, then `fix grammar`, `make this professional` (or casual, friendly, polite, confident, concise, clear, simple), `shorten`, `expand`, `simplify`, `bullet points`, `summarize this`, `explain this`, `reply saying I'll be there at 5`, `extract the action items`, `draft an email about …`. Every result has **Copy** and **Paste**. Paste puts the text into the app you came from. About one second, on-device.
- **Documents and scanned PDFs.** `summarize ~/Documents/lease.pdf`, `what does ~/Documents/lease.pdf say about the deposit`, `ask ~/notes.txt: who is the owner`. PDF, .docx, .txt, .md, .csv, .json and images. PDFs with only scanned pages are read with on-device OCR. Web pages too: `summarize https://…`, one read-only fetch, only when asked.
- **Screenshot intelligence.** `read the latest screenshot`, `copy text from ~/Desktop/shot.png`, `explain the error in this screenshot` (OCR plus explanation, no LM Studio needed), `describe ~/Desktop/a.png: which app is this`, `compare ~/Desktop/actual.png with ~/Designs/expected.png`, `rename my screenshots` by content. An opt-in setting names every new screenshot as it lands. Undoable.
- **Voice to meeting notes.** `transcribe ~/Downloads/call.m4a`, `meeting notes from ~/Downloads/standup.mp4`: summary, decisions and action items. On-device SpeechAnalyzer. Audio and video files.
- **Receipts to expenses.** `total the receipts in ~/Documents/Receipts`: merchant, date, total and currency per receipt, the sum, and a CSV saved after one confirmation.
- **Crash explanations.** `why did my app crash`, `why did Safari crash`: reads crash reports from the last 48 hours (`~/Library/Logs/DiagnosticReports`, read-only) and explains the crashed thread and likely cause.
- **Developer chores.** `what changed`, `commit this`, `push` (git status, diff, commit with your message, push; never force, never amend), `clean the metro caches`, `pair my watch 192.168.1.20:41234 code 123456`, `connect 192.168.1.20:41234`, `install ~/Downloads/app.apk on my phone`, `build a signed apk for weather-app`. Plus the existing run-on-device, simulators, GitHub Actions and code search.
- **For you, rules and undo.** The empty palette suggests what is worth doing: old screenshots to archive, Downloads size, duplicate space to reclaim, recent crashes to explain, and clipboard triage (an error on the clipboard offers an explanation, a URL or long text offers a summary). Computed at most once a day when you open the palette, never in the background. A cleanup you have run three times is offered as a weekly rule, or ask `every monday move the screenshots in ~/Downloads older than 30 days into ~/Downloads/Archive`. `undo` reverses the last automated move or rename.
- **Optional Laya.** `pip install "laya[serve]"` then `LAYA_PORT=8765 laya-serve` adds ~150 ms typed routing hints and language detection, so you can type requests in 100+ languages. Turn it on in Settings › Laya.
- **Tool server.** New MCP tools in `mac-tools`: `readWebPage` `writeTextFile` `gitStatus` `gitDiff` `gitCommit` `gitPush` `cleanDevCaches` `adbPair` `adbConnect` `installApp` `buildAndroidRelease`. New CLI flag: `Muon --suggest` prints the For you rows.

## Fixes

- **LM Studio reasoning.** Multi-step and long-text requests are far faster: Qwen's hidden reasoning is now switched off via `reasoning_effort`.

## Install

**Download**
1. Download `Muon.zip` from this release and move `Muon.app` to Applications.
2. Open it. Muon is ad-hoc signed, so macOS blocks it the first time: open System Settings › Privacy & Security and click **Open Anyway** (or run `xattr -dr com.apple.quarantine /Applications/Muon.app`).
3. Press `⇧⌥Space`. Check your setup any time with `/Applications/Muon.app/Contents/MacOS/Muon --diagnose`.

**Homebrew**

```bash
brew install --cask harshdvaid24/tap/muon
```

**Requirements:** macOS 26 on Apple Silicon with Apple Intelligence on, and Node.js 20+ (`brew install node`). Optional: [LM Studio](https://lmstudio.ai) with `qwen/qwen3.5-9b@4bit` (or the 4B fallback) for multi-step planning, image understanding and very long text. Everything else works without it.

## Known limitations

- The app is ad-hoc signed. First launch needs System Settings › Privacy & Security › **Open Anyway**.
- The on-device tier needs Apple Intelligence. Without it, everything routes to LM Studio.
- Image understanding and very long text need LM Studio.
- Run-on-device supports React Native. For native Xcode projects, Muon opens the workspace so you can press Run.
- Android runs need an emulator created in Android Studio, or a connected phone.
- The multi-step planner with the 4B model can take 30 to 60 s on a busy Mac.
- CI tests the tool server. The macOS 26 app is built locally.

Full catalog of requests, the safety model and the tiers: [README](https://github.com/harshdvaid24/muon#readme).
