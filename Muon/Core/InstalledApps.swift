import Foundation

/// Resolves loose app names ("vs code", "chrome") to real application names. Enumerated once per launch.
enum InstalledApps {
    static let aliases: [String: String] = [
        "vscode": "Visual Studio Code", "vs code": "Visual Studio Code", "code": "Visual Studio Code",
        "chrome": "Google Chrome", "brave": "Brave Browser", "terminal": "Terminal", "sim": "Simulator", "simulator": "Simulator",
        "settings": "System Settings", "system preferences": "System Settings", "finder": "Finder", "lm studio": "LM Studio",
    ]

    static let names: [String] = {
        let dirs = ["/Applications", "/System/Applications", "/System/Applications/Utilities", NSHomeDirectory() + "/Applications"]
        var out: [String] = []
        for d in dirs {
            for e in (try? FileManager.default.contentsOfDirectory(atPath: d)) ?? [] where e.hasSuffix(".app") {
                out.append(String(e.dropLast(4)))
            }
        }
        return Array(Set(out)).sorted()
    }()

    static func resolve(_ raw: String) -> String {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return q }
        let lower = q.lowercased()
        if let a = aliases[lower] { return a }
        if let exact = names.first(where: { $0.lowercased() == lower }) { return exact }
        if let prefix = names.first(where: { $0.lowercased().hasPrefix(lower) }) { return prefix }
        if let contains = names.first(where: { $0.lowercased().contains(lower) }) { return contains }
        return q
    }
}
