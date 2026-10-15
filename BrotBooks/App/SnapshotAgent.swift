#if DEBUG && os(macOS)
import AppKit
import os
import BrotBooksKit

/// Debug-only: `-snapshot YES` renders the real window hierarchy to PNGs (no screen-recording permission
/// needed) in the app container's Caches/Snapshots folder, then quits. Used for design review.
/// `-snapshotSettings YES` captures the Settings window instead (pick the tab with `-settingsTab elster`), plus
/// any sheet on it, such as the ELSTER license notice.
@MainActor
enum SnapshotAgent {
    private static let log = Logger(subsystem: "me.freas.BrotBooks", category: "snapshot")

    static var enabled: Bool { UserDefaults.standard.bool(forKey: "snapshot") }
    static var settingsEnabled: Bool { UserDefaults.standard.bool(forKey: "snapshotSettings") }

    static func run(app: AppModel, openSettings: () -> Void) async {
        if settingsEnabled { return await runSettings(openSettings: openSettings) }
        guard enabled else { return }
        let dir = snapshotDirectory
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

    private static var snapshotDirectory: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func runSettings(openSettings: () -> Void) async {
        let dir = snapshotDirectory
        let tab = UserDefaults.standard.string(forKey: "settingsTab") ?? "general"
        try? await Task.sleep(for: .seconds(1))
        openSettings()
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            NSApp.appearance = NSAppearance(named: appearance)
            let suffix = appearance == .aqua ? "light" : "dark"
            try? await Task.sleep(for: .seconds(3))
            let window = NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue.contains("Settings") == true }
                ?? NSApp.keyWindow
            log.notice("Settings window: \(window?.identifier?.rawValue ?? "none", privacy: .public) \(NSApp.windows.map { $0.identifier?.rawValue ?? "?" }, privacy: .public)")
            capture(window, to: dir.appendingPathComponent("settings-\(tab)-\(suffix).png"))
            if let sheet = window?.attachedSheet {
                capture(sheet, to: dir.appendingPathComponent("settings-\(tab)-sheet-\(suffix).png"))
            }
        }
        log.notice("Settings snapshots written to \(dir.path, privacy: .public)")
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
