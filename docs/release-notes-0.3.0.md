# Muon 0.3.0: talk, drop, paste, recall

- **Voice.** Press `⌘⇧M` (or click the mic, or the menu bar's *Talk to Muon*), say what you need and pause. Live on-device transcription (SpeechAnalyzer) fills the field and the request runs. Spoken requests get spoken replies; both are in Settings › Voice, along with *Start listening when the palette opens*. Nothing is recorded, nothing leaves the Mac.
- **Attach anything.** Drop a file or folder on the palette, press `⌘O`, or `⌘V` a copied file or image. A chip shows it; ask in plain words: *explain this*, *who is the tenant*, *what did they decide*, *total the receipts*. An empty request summarizes a document, describes an image, transcribes a recording.
- **Image paste.** `⌘V` with an image on the clipboard attaches it (kept under `~/Library/Application Support/Muon/Pasted`, newest 20).
- **Recent requests.** The empty palette lists your recent requests under the suggestions, most used first. `↑` `↓` move through both, `⇥` edits, `↩` runs. With text in the field, `↑` `↓` cycle recent requests like a shell.
- **What can you do.** `help`, `what can you do`, `list commands` show the full catalog inside the app, instantly, no model. New installs get a *What can I ask?* row.
- **Plain-text answers.** Code fences and inline backticks are stripped from on-device explanations.
- **Paths with spaces** work in writing requests too (quoted or not).

Requirements unchanged: macOS 26 on Apple Silicon with Apple Intelligence, Node.js 20+. Microphone access is asked for on first use of voice.

Full catalog and install steps: [README](https://github.com/harshdvaid24/muon#readme).
