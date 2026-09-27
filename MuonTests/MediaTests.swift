import AppKit
import Foundation
import Testing
@testable import Muon

@Suite struct MediaIntentTests {
    @Test func screenshots() {
        #expect(MediaIntent.parse("read the latest screenshot") == .ocr("latest screenshot"))
        #expect(MediaIntent.parse("copy text from ~/Desktop/shot.png") == .ocr("~/Desktop/shot.png"))
        #expect(MediaIntent.parse("explain the error in this screenshot") == .explainScreenshot("latest screenshot"))
        #expect(MediaIntent.parse("describe ~/Desktop/a.png: which app is this") == .describe("~/Desktop/a.png", "which app is this"))
        #expect(MediaIntent.parse("compare ~/Desktop/a.png with ~/Designs/b.png") == .compare("~/Desktop/a.png", "~/Designs/b.png"))
        #expect(MediaIntent.parse("rename screenshots in ~/Desktop") == .renameScreenshots("~/Desktop"))
        #expect(MediaIntent.parse("rename my screenshots") == .renameScreenshots(nil))
    }
    @Test func webAndCrash() {
        guard case .webPage(let url, let ins)? = MediaIntent.parse("summarize https://example.com/post?id=1") else { Issue.record("no webPage"); return }
        #expect(url == "https://example.com/post?id=1"); #expect(ins.contains("Summarize"))
        guard case .webPage(_, let ins2)? = MediaIntent.parse("what does https://x.y/doc say about pricing") else { Issue.record("no webPage"); return }
        #expect(ins2.contains("pricing"))
        #expect(MediaIntent.parse("why did my app crash") == .crash(nil))
        #expect(MediaIntent.parse("why did Safari crash?") == .crash("safari"))
        #expect(MediaIntent.parse("show recent crashes") == .crash(nil))
    }
    @Test func notMedia() {
        #expect(MediaIntent.parse("open xcode") == nil)
        #expect(MediaIntent.parse("find pdfs about invoices") == nil)
        #expect(MediaIntent.parse("summarize ~/Documents/a.txt") == nil)   // WritingIntent handles files
    }
}

@Suite struct OCRTests {
    @Test func recognizesRenderedText() throws {
        let size = NSSize(width: 900, height: 240)
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor.white.setFill(); NSRect(origin: .zero, size: size).fill()
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 72, weight: .bold), .foregroundColor: NSColor.black]
        NSAttributedString(string: "HELLO MUON 2026", attributes: attrs).draw(at: NSPoint(x: 40, y: 80))
        img.unlockFocus()
        let tiff = img.tiffRepresentation!, rep = NSBitmapImageRep(data: tiff)!, png = rep.representation(using: .png, properties: [:])!
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "muon-ocr-\(UUID().uuidString).png")
        try png.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let text = try VisionTools.ocr(url).uppercased()
        #expect(text.contains("HELLO")); #expect(text.contains("MUON")); #expect(text.contains("2026"))
    }
    @Test func screenshotNamesRecognized() {
        #expect(VisionTools.isScreenshotName("Screenshot 2026-08-01 at 10.12.03.png"))
        #expect(VisionTools.isScreenshotName("Simulator Screenshot - iPhone 17 - 2026-08-01.png"))
        #expect(!VisionTools.isScreenshotName("2026-08-01-invoice-acme.png"))
    }
}

@Suite struct CrashLogTests {
    @Test func summarizesIpsReport() {
        let body: [String: Any] = ["procName": "WeatherApp", "exception": ["type": "EXC_CRASH", "signal": "SIGABRT"],
                                   "termination": ["indicator": "abort()"], "faultingThread": 0,
                                   "threads": [["frames": [["imageIndex": 0, "symbol": "main"], ["imageIndex": 1, "symbol": "abort"]]]],
                                   "usedImages": [["name": "WeatherApp"], ["name": "libsystem_c.dylib"]]]
        let raw = "{\"app_name\":\"WeatherApp\"}\n" + String(decoding: try! JSONSerialization.data(withJSONObject: body), as: UTF8.self)
        let s = CrashLogs.summarize(raw)
        #expect(s.contains("process: WeatherApp")); #expect(s.contains("SIGABRT")); #expect(s.contains("crashed thread 0")); #expect(s.contains("WeatherApp  main"))
    }
}
