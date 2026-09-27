# Muon 0.3.1: fixes from the demo re-recording

![Muon demo](https://raw.githubusercontent.com/harshdvaid24/muon/main/docs/media/demo.gif)

- **Edit shortcuts in the palette.** ⌘A, ⌘C, ⌘X, ⌘Z now work in the field, and ⌘V pastes text (or attaches a copied file or image). A menu bar app has no Edit menu unless it builds one; Muon now does.
- **Image answers were empty.** The local vision model spent its whole budget on hidden reasoning; the vision call now turns reasoning off like the text calls do.
- **Recent requests read better.** Home shows as `~`, pasted images as *(pasted image)*.
- **New demo.** Twelve scenes on the current build: a spoken request, pasted PDF and screenshot, recent requests, the in-app catalog. README and site updated to match.

Everything in [0.3.0](https://github.com/harshdvaid24/muon/releases/tag/v0.3.0) applies: voice, attachments, image paste, recent requests, `what can you do`.
