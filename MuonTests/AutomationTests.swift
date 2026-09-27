import Foundation
import Testing
@testable import Muon

@Suite struct RuleTests {
    @Test func parsesSchedules() {
        let a = Rules.parse("every monday at 9 move the screenshots in ~/Downloads into ~/Downloads/Archive")
        #expect(a?.schedule == .weekly(weekday: 2, hour: 9))
        #expect(a?.query == "move the screenshots in ~/Downloads into ~/Downloads/Archive")
        #expect(Rules.parse("every day at 6pm archive the pdfs on my desktop")?.schedule == .daily(hour: 18))
        #expect(Rules.parse("every week trash zips in downloads older than 30 days")?.schedule == .weekly(weekday: 2, hour: 9))
        #expect(Rules.parse("every monday open xcode") == nil)            // only deterministic cleanups become rules
        #expect(Rules.parse("move the screenshots in ~/Downloads into ~/Downloads/Archive") == nil)
    }
    @Test func dueLogic() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let monday10 = cal.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 10))!   // a Monday
        var r = Rule(id: "t", query: "q", schedule: .weekly(weekday: 2, hour: 9), createdAt: cal.date(byAdding: .day, value: -8, to: monday10)!)
        #expect(Rules.isDue(r, now: monday10, calendar: cal))                          // 9:00 today passed, never run
        r.lastRun = cal.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 9, minute: 30))
        #expect(!Rules.isDue(r, now: monday10, calendar: cal))                         // already ran after 9:00
        let sunday = cal.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 12))!
        r.lastRun = cal.date(byAdding: .day, value: -3, to: sunday)
        #expect(!Rules.isDue(r, now: sunday, calendar: cal))                           // last Monday's slot was before lastRun
        let daily = Rule(id: "d", query: "q", schedule: .daily(hour: 8), lastRun: cal.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 8, minute: 5)), createdAt: sunday)
        #expect(Rules.isDue(daily, now: monday10, calendar: cal))
        #expect(!Rules.isDue(daily, now: cal.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 7))!, calendar: cal))
    }
}

@Suite struct UndoTests {
    @Test func planOnlyIncludesFilesStillThere() throws {
        let dir = NSTemporaryDirectory() + "muon-undo-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir + "/Archive", withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: dir + "/Archive/a.png", contents: Data())
        let rec = Undo.Record(title: "t", moves: [.init(from: dir + "/a.png", to: dir + "/Archive/a.png"), .init(from: dir + "/b.png", to: dir + "/Archive/b.png")], at: Date())
        let plan = Undo.plan(rec)
        #expect(plan.count == 1); #expect(plan.first?.from == dir + "/Archive/a.png"); #expect(plan.first?.toFolder == dir)
    }
}

@Suite struct ProactiveTests {
    @Test func clipboardTriageIsRegexOnly() {
        TextTools.copy("TypeError: Cannot read properties of undefined (reading 'map')\n    at Forecast (Forecast.tsx:12:5)")
        #expect(Proactive.clipboardSuggestions().first?.id == "clip-error")
        TextTools.copy("https://developer.apple.com/documentation/foundationmodels")
        #expect(Proactive.clipboardSuggestions().first?.id == "clip-url")
        TextTools.copy("नमस्ते, कल की बैठक सुबह दस बजे है। कृपया समय पर आएं और रिपोर्ट साथ लाएं।")
        #expect(Proactive.clipboardSuggestions().first?.id == "clip-translate")
        TextTools.copy("short")
        #expect(Proactive.clipboardSuggestions().isEmpty)
    }
}

@Suite struct LayaTests {
    @Test func routesEnglishConfidently() async {
        guard await Laya.isReachable() else { return }
        let h = await Laya.route("open xcode")
        // Laya is a hint only: zero-shot families drift between checkpoints, so assert the shape, not the exact family.
        #expect(h != nil); #expect(Laya.families.keys.contains(h?.family ?? "")); #expect(h?.multilingual == false)
        let hi = await Laya.route("डाउनलोड में डुप्लिकेट फाइलें ढूंढो")
        #expect(hi?.multilingual == true)
    }
}
