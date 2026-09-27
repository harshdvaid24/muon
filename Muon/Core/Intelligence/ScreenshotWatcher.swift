import Foundation

/// Opt-in: when a new screenshot lands in the screenshots folder, name it by its content.
/// A kqueue on one folder costs nothing while idle; work happens only when a file appears.
final class ScreenshotWatcher {
    static let shared = ScreenshotWatcher()
    static let settingKey = "autoNameScreenshots"
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var pending: DispatchWorkItem?
    private var seen = Set<String>()
    private let queue = DispatchQueue(label: "muon.screenshots")

    var isOn: Bool { Settings.d.bool(forKey: Self.settingKey) }

    func apply() { isOn ? start() : stop() }

    func start() {
        guard source == nil else { return }
        let folder = VisionTools.screenshotsFolder()
        fd = open(folder, O_EVTONLY)
        guard fd >= 0 else { return }
        seen = Set((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [])
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: queue)
        src.setEventHandler { [weak self] in self?.scheduleScan(folder) }
        src.setCancelHandler { [weak self] in if let fd = self?.fd, fd >= 0 { close(fd) }; self?.fd = -1 }
        src.resume()
        source = src
    }

    func stop() { source?.cancel(); source = nil }

    private func scheduleScan(_ folder: String) {
        pending?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.scan(folder) }
        pending = w
        queue.asyncAfter(deadline: .now() + 2.5, execute: w)   // let macOS finish writing the file
    }

    private func scan(_ folder: String) {
        let now = Set((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [])
        let new = now.subtracting(seen).filter { !$0.hasPrefix(".") && VisionTools.isScreenshotName($0) }
        seen = now
        guard !new.isEmpty else { return }
        Task {
            for name in new {
                let path = folder + "/" + name
                guard let newName = try? await VisionTools.proposeName(for: path), newName != name else { continue }
                let (msg, isError) = (try? await MCPClient.shared.call("renameItem", args: ["path": path, "newName": newName])) ?? ("tool server unavailable", true)
                if isError { continue }
                Undo.record(title: "Auto-named a screenshot", moves: [Undo.Move(from: path, to: folder + "/" + newName)])
                Notifier.notify(title: "Screenshot named", body: "\(newName) — open Muon and type “undo” to revert.")
                _ = msg
            }
        }
    }
}
