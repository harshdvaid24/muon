import Foundation

/// "what can you do", "help", "commands": the catalog, answered without a model. Mirrors README › Everything you can ask.
enum Help {
    static func matches(_ q: String) -> Bool {
        let n = Memory.normalize(q)
        guard !n.isEmpty, n.count <= 60 else { return false }
        let exact: Set<String> = ["help", "commands", "command list", "usage", "capabilities", "features", "examples", "what can you do", "what all can you do",
                                  "what can i ask", "what can i ask you", "what can i do", "what do you do", "what are you", "what can you help with", "what can you help me with",
                                  "how do i use you", "how do i use this", "how does this work", "show commands", "list commands", "list all commands", "show me what you can do",
                                  "what should i ask", "what can you do for me"]
        if exact.contains(n) { return true }
        return n.range(of: #"^(what (all |else )?can (you|i|muon) (do|ask|say|help)( for me| here| with this)?|(show|list|give)( me)?( all)?( the| your| some)? (commands|examples|capabilities|features|options)|how (do|can) i use (you|this|muon)|what (do|can) you (do|help)( with)?)$"#, options: .regularExpression) != nil
    }

    static let sections: [(title: String, examples: [String])] = [
        ("Writing (copy text in any app first, or add “: your text”)", [
            "fix grammar", "make this professional  ·  casual  ·  friendly  ·  concise", "shorten  ·  expand  ·  simplify  ·  bullet points",
            "summarize this  ·  summarize this in one line", "explain this  (errors, stack traces, code, jargon)",
            "reply saying I'll be there at 5", "extract the action items", "draft an email about the delayed shipment", "summarize: <text>"]),
        ("Documents and web", [
            "analyse statement.pdf from downloads and give me a brief  (a file name is enough)", "check invoice.pdf in documents: what is the total",
            "summarize ~/Documents/lease.pdf", "what does ~/Documents/lease.pdf say about the deposit", "ask ~/notes.txt: who is the owner",
            "summarize https://example.com/post", "what is typescript  ·  search the web for swift concurrency", "open github.com",
            "Drop a file on this window, press ⌘O or the paperclip, ⌘V a copied file, or right-click it in Finder › Open With › Muon, then ask"]),
        ("Screenshots and images", [
            "read the latest screenshot", "explain the error in this screenshot", "copy text from ~/Desktop/shot.png",
            "describe ~/Desktop/a.png: which app is this", "compare ~/Desktop/actual.png with ~/Designs/expected.png", "rename my screenshots",
            "⌘V a copied image, then ask"]),
        ("Voice", [
            "⌘⇧M (or the mic) and speak; it runs when you pause", "transcribe ~/Downloads/call.m4a", "meeting notes from ~/Downloads/standup.mp4"]),
        ("Expenses and crashes", [
            "total the receipts in ~/Documents/Receipts", "why did my app crash  ·  why did Safari crash"]),
        ("Developer", [
            "start claude code for weather-app  (a new VS Code window for that project with Claude Code in its terminal; also codex · gemini · aider)",
            "run ~/Projects/weather-app on iPhone 17  ·  run weather-app on pixel 9", "which simulators do I have", "is my build done  ·  job status",
            "what changed  ·  commit this  ·  push", "clean the metro caches", "pair my watch 192.168.1.20:41234 code 123456", "install ~/Downloads/app.apk on my phone",
            "build a signed apk for weather-app", "list the workflows in weather-app  ·  trigger the release workflow in weather-app on main",
            "search code for TODO in ~/Projects/weather-app", "open weather-app in vs code  ·  open weather-app in xcode", "list my projects"]),
        ("Files, disk and apps", [
            "what is taking space in ~/Downloads", "find duplicate files in ~/Downloads", "how much disk space is free",
            "move the screenshots in ~/Downloads into ~/Downloads/Archive", "trash zips in downloads older than 30 days", "archive the pdfs on my desktop",
            "find pdfs about invoices", "find package.json in ~/Projects/weather-app", "what is inside ~/Downloads", "reveal ~/Downloads/report.pdf in finder",
            "open xcode  ·  quit spotify", "which apps are using the most memory", "in safari open a new private window", "what menus does notes have"]),
        ("Automation and memory", [
            "every monday move the screenshots in ~/Downloads older than 30 days into ~/Downloads/Archive", "undo",
            "save macro morning  (then type “morning” to replay)", "Open the empty palette for “For you” suggestions and your recent requests"]),
        ("Keys", [
            "⇧⌥Space open  ·  ↩ run or allow  ·  esc close or cancel", "↑ ↓ move through suggestions and recent requests  ·  ⇥ edit a recent one",
            "⌘O attach a file  ·  ⌘V paste an image or file  ·  ⌘⇧M talk"]),
    ]

    static var text: String {
        sections.map { s in s.title.uppercased() + "\n" + s.examples.map { "  " + $0 }.joined(separator: "\n") }.joined(separator: "\n\n")
    }
}
