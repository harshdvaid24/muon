# Muon 0.3.2: name a file, get an analysis

- **A file name is enough.** *"check sampleStatement.pdf from downloads, analyse it and give me a brief"* now finds the file (in the folder you name, else Downloads, Documents, Desktop, then every allowed folder; case-insensitive; a few levels deep), reads it and answers. Before, the model just opened it. *"open x.pdf from downloads"* still opens it.
- **Analyse, review, brief.** New writing rules: *analyse this*, *review this document and give me a brief*, *give me a brief*, *quick summary of this*. Analysis answers with a short brief, key facts and figures, and anything unusual.
- **Attach button.** A paperclip next to the mic opens the file picker (same as ⌘O or dropping a file).
- **Faster on medium documents.** A few pages are processed on-device in parts instead of waiting for LM Studio to load a model; when the local model is already loaded it still gets the whole text. Over-long paragraphs (PDF tables) are split safely and partial analyses are merged.

Everything in [0.3.1](https://github.com/harshdvaid24/muon/releases/tag/v0.3.1) applies.
