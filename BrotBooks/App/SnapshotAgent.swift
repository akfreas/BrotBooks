#if DEBUG && os(macOS)
import AppKit
import PDFKit
import os
import BrotBooksKit

/// Debug-only: `-snapshot YES` renders the real window hierarchy to PNGs (no screen-recording permission
/// needed) in the app container's Caches/Snapshots folder, then quits. Used for design review.
/// `-snapshotSettings YES` captures the Settings window instead (pick the tab with `-settingsTab elster`), plus
/// any sheet on it, such as the ELSTER license notice.
/// `-snapshotVat YES` (with `-uiTesting YES -startDestination vatReturns`) seeds a test filer identity into the
/// in-memory tax profile and captures the VAT returns list, a month's detail, its validation, the preview sheet
/// and the treatment review list.
@MainActor
enum SnapshotAgent {
    private static let log = Logger(subsystem: "me.freas.BrotBooks", category: "snapshot")

    static var enabled: Bool { UserDefaults.standard.bool(forKey: "snapshot") }
    static var settingsEnabled: Bool { UserDefaults.standard.bool(forKey: "snapshotSettings") }
    static var vatEnabled: Bool { UserDefaults.standard.bool(forKey: "snapshotVat") }

    static func run(app: AppModel, openSettings: () -> Void) async {
        if settingsEnabled { return await runSettings(openSettings: openSettings) }
        if vatEnabled { return await runVat(app: app) }
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

    /// The test filer of the ERiC samples (Finanzamt 1096 is a test Finanzamt). Only into the in-memory store of
    /// `-uiTesting`, never real data.
    private static func seedTestIdentity(app: AppModel) {
        guard LaunchOptions.uiTesting, let context = app.storage?.container.mainContext,
              var settings = try? TaxProfile.load(in: context) else { return }
        settings.identity = TaxIdentity(name: "Alois Mustermann", street: "Testgasse", houseNumber: "13a",
                                        postalCode: "08151", city: "Musterstadt", phone: "0815/99999999",
                                        email: "mustermann@example.com", steuernummer: "1096081508187",
                                        finanzamt: "1096", vatID: "DE123456789")
        try? TaxProfile.save(settings, in: context)
    }

    private static func runVat(app: AppModel) async {
        let dir = snapshotDirectory
        seedTestIdentity(app: app)
        let model = VatReturnsModel.shared
        try? await Task.sleep(for: .seconds(3))
        model.reload(app)
        let window = { NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible && !$0.isSheet } }
        capture(window(), to: dir.appendingPathComponent("vat-list.png"))

        let month = UserDefaults.standard.string(forKey: "snapshotVatPeriod") ?? "2026-09"
        model.selection = month
        model.selectedKennzahl = .kz81
        try? await Task.sleep(for: .seconds(1.5))
        capture(window(), to: dir.appendingPathComponent("vat-detail.png"))

        if let item = model.selectedItem {
            model.selectedKennzahl = nil
            await model.validate(item)
            try? await Task.sleep(for: .seconds(1.5))
            capture(window(), to: dir.appendingPathComponent("vat-validation.png"))

            await model.preview(item, title: VatReturnTexts.titleString(item))
            try? await Task.sleep(for: .seconds(2.5))
            capture(NSApp.windows.first { $0.isSheet && $0.isVisible } ?? window()?.attachedSheet,
                    to: dir.appendingPathComponent("vat-preview.png"))
            // PDFView draws in a layer that the window capture leaves blank: also keep the PDF and its first page.
            if let pdf = model.preview?.data {
                try? pdf.write(to: dir.appendingPathComponent("vat-preview.pdf"))
                if let page = PDFDocument(data: pdf)?.page(at: 0) {
                    let image = page.thumbnail(of: NSSize(width: 1190, height: 1684), for: .mediaBox)
                    if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                        try? rep.representation(using: .png, properties: [:])?
                            .write(to: dir.appendingPathComponent("vat-preview-page.png"))
                    }
                }
            }
            model.preview = nil
            try? await Task.sleep(for: .seconds(1))
        }

        model.selection = "2026-12"
        try? await Task.sleep(for: .seconds(1.5))
        capture(window(), to: dir.appendingPathComponent("vat-december.png"))

        model.showingReview = true
        try? await Task.sleep(for: .seconds(2))
        capture(window(), to: dir.appendingPathComponent("vat-review.png"))
        model.showingReview = false

        // The editor's suggestion for an unconfirmed record.
        if let entry = model.review.first, let record = model.records[entry.recordUID] {
            app.open(record)
            try? await Task.sleep(for: .seconds(2.5))
            capture(NSApp.windows.first { $0.isSheet && $0.isVisible }, to: dir.appendingPathComponent("vat-editor.png"))
            app.editor = nil
        }
        log.notice("VAT snapshots written to \(dir.path, privacy: .public)")
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
