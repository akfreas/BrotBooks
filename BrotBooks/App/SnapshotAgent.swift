#if DEBUG && os(macOS)
import AppKit
import os
import BrotBooksKit

/// Debug-only: `-snapshot YES` renders the real window hierarchy to PNGs (no screen-recording permission
/// needed) in the app container's Caches/Snapshots folder, then quits. Used for design review.
@MainActor
enum SnapshotAgent {
    private static let log = Logger(subsystem: "me.freas.BrotBooks", category: "snapshot")

    static var enabled: Bool { UserDefaults.standard.bool(forKey: "snapshot") }

    static func run(app: AppModel) async {
        guard enabled else { return }
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? await Task.sleep(for: .seconds(2))
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            NSApp.appearance = NSAppearance(named: appearance)
            let suffix = appearance == .aqua ? "light" : "dark"
            app.editor = nil
            try? await Task.sleep(for: .seconds(1.5))
            capture(NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible }, to: dir.appendingPathComponent("dashboard-\(suffix).png"))
            if let invoice = app.records(.income).first(where: { !$0.isPaid && $0.hasDocument }) ?? app.records(.income).first {
                app.open(invoice)
                try? await Task.sleep(for: .seconds(2.5))
                capture(NSApp.windows.first { $0.isSheet && $0.isVisible }, to: dir.appendingPathComponent("editor-\(suffix).png"))
                app.editor = nil
            }
        }
        log.notice("Snapshots written to \(dir.path, privacy: .public)")
        NSApp.terminate(nil)
    }

    private static func capture(_ window: NSWindow?, to url: URL) {
        guard let window, let view = window.contentView?.superview ?? window.contentView else {
            log.error("No window to capture for \(url.lastPathComponent, privacy: .public)")
            return
        }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
