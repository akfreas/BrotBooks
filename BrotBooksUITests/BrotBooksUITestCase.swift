import XCTest

/// Shared launch, navigation and screenshot helpers for the BrotBooks UI tests.
///
/// Every test launches the app with `-uiTesting YES`: an in-memory store with generated sample data, "today" pinned
/// to 2026-10-10, no animations and no iCloud, so each test starts from the same clean state and never touches real
/// data. iPads run in landscape so the sidebar is visible.
@MainActor
class BrotBooksUITestCase: XCTestCase {
    var app: XCUIApplication!

    var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    var device: String { isPad ? "ipad" : "iphone" }

    override func setUp() async throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = isPad ? .landscapeLeft : .portrait
    }

    override func tearDown() async throws {
        app?.terminate()
        app = nil
    }

    enum Fixture: String {
        case sortedExport = "UITEST_SORTED_EXPORT"
    }

    /// Launches a fresh app. `fixtures` stand in for the file picker of the matching import menu item; `invoices`
    /// (fixture filenames) stand in for the Import Invoices… picker, with the stub extractor's canned results.
    func launch(empty: Bool = false, dark: Bool = false, fixtures: [Fixture: String] = [:], invoices: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-uiAppearance", dark ? "dark" : "light"]
        if empty { app.launchArguments += ["-uiTestingEmpty", "YES"] }
        for (fixture, file) in fixtures {
            let url = Bundle(for: BrotBooksUITestCase.self).url(forResource: file, withExtension: nil)
            guard let url, let data = try? Data(contentsOf: url) else {
                XCTFail("Missing fixture \(file) in the UI test bundle")
                return
            }
            app.launchEnvironment[fixture.rawValue] = data.base64EncodedString()
            app.launchEnvironment[fixture.rawValue + "_NAME"] = file
        }
        if !invoices.isEmpty {
            var files: [[String: String]] = []
            for name in invoices {
                let url = Bundle(for: BrotBooksUITestCase.self).url(forResource: name, withExtension: nil)
                guard let url, let data = try? Data(contentsOf: url) else {
                    XCTFail("Missing fixture \(name) in the UI test bundle")
                    return
                }
                files.append(["name": name, "data": data.base64EncodedString()])
            }
            let json = try? JSONSerialization.data(withJSONObject: files)
            app.launchEnvironment["UITEST_INVOICES"] = json.flatMap { String(data: $0, encoding: .utf8) }
            app.launchArguments += ["-uiTestingExtractor", "stub"]
        }
        app.launch()
        let ready = empty ? element("dashboard.empty") : element("dashboard.taxCard")
        XCTAssertTrue(ready.waitForExistence(timeout: 20), "The dashboard didn't appear")
    }

    /// Any element by accessibility identifier.
    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Waits for an element, scrolling the frontmost list or form if it is below the fold, and taps it.
    func tap(_ identifier: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        let e = reveal(identifier, timeout: timeout)
        XCTAssertTrue(e.exists, "\(identifier) not found", file: file, line: line)
        e.tap()
    }

    /// Finds an element, scrolling up (and then back down) through the frontmost scroll view until it is on screen.
    /// Lists and forms are lazy: rows below the fold don't exist until they are scrolled to.
    @discardableResult
    func reveal(_ identifier: String, timeout: TimeInterval = 5) -> XCUIElement {
        let e = element(identifier)
        if e.waitForExistence(timeout: timeout) && e.isHittable { return e }
        // Not the PDF preview's own scroll view (beside the editor form on iPad).
        let pdf = app.descendants(matching: .any).matching(identifier: "document.preview").firstMatch
        let pdfFrame = pdf.exists ? pdf.frame : .null
        let scroller = [app.collectionViews, app.scrollViews, app.tables]
            .map { $0.allElementsBoundByIndex.filter { $0.exists && $0.isHittable && !pdfFrame.contains($0.frame) }.last }
            .compactMap { $0 }.last
        guard let scroller else { return e }
        for _ in 0..<8 where !(e.exists && e.isHittable) { scroller.swipeUp(velocity: .slow) }
        for _ in 0..<8 where !(e.exists && e.isHittable) { scroller.swipeDown(velocity: .slow) }
        return e
    }

    /// Visible text of an element: its label, or for controls with a separate value, label + value.
    func text(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) -> String {
        let e = reveal(identifier)
        XCTAssertTrue(e.exists, "\(identifier) not found", file: file, line: line)
        let value = (e.value as? String) ?? ""
        return value.isEmpty ? e.label : "\(e.label) \(value)"
    }

    func waitForText(_ identifier: String, contains needle: String, timeout: TimeInterval = 10,
                     file: StaticString = #filePath, line: UInt = #line) {
        let e = reveal(identifier, timeout: min(timeout, 5))
        let predicate = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", needle, needle)
        let found = XCTNSPredicateExpectation(predicate: predicate, object: e)
        let result = XCTWaiter().wait(for: [found], timeout: timeout)
        XCTAssertEqual(result, .completed, "\(identifier) never showed \"\(needle)\" (was \"\(e.exists ? e.label : "missing")\")",
                       file: file, line: line)
    }

    /// Attaches a full-screen screenshot named "<device>-<name>", kept even when the test passes.
    func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(device)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    enum Place: String {
        case dashboard, income, expenses

        var title: String {
            switch self {
            case .dashboard: "Dashboard"
            case .income: "Income"
            case .expenses: "Expenses"
            }
        }
    }

    /// Switches the iPhone tab or the iPad sidebar destination.
    func go(to place: Place) {
        if isSearching { clearSearch() }
        if isPad {
            var row = element("sidebar.\(place.rawValue)")
            if !row.waitForExistence(timeout: 3) {
                app.buttons["Show Sidebar"].firstMatch.tap()
                row = element("sidebar.\(place.rawValue)")
            }
            XCTAssertTrue(row.waitForExistence(timeout: 5), "No sidebar row for \(place.title)")
            row.tap()
        } else {
            let tab = app.tabBars.buttons[place.title].firstMatch
            XCTAssertTrue(tab.waitForExistence(timeout: 5), "No tab for \(place.title)")
            tab.tap()
        }
        if place != .dashboard {
            XCTAssertTrue(app.navigationBars[place.title].firstMatch.waitForExistence(timeout: 5)
                          || element("record.row.0").waitForExistence(timeout: 5),
                          "\(place.title) didn't open")
        }
    }

    /// Picks a year from the toolbar year picker.
    func pickYear(_ year: Int) {
        tap("yearPicker")
        let item = app.buttons[String(year)].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "No \(year) in the year menu")
        item.tap()
    }

    /// Types into the list's search field.
    func search(_ text: String) {
        let field = app.searchFields.firstMatch
        if !field.waitForExistence(timeout: 3) {
            // The search field hides under the navigation bar until the list is pulled down.
            app.collectionViews.firstMatch.swipeDown()
        }
        XCTAssertTrue(field.waitForExistence(timeout: 5), "No search field")
        field.tap()
        // Submitting dismisses the keyboard, so it doesn't cover the list.
        field.typeText(text + "\n")
    }

    /// True while a search is active (text in the field or the keyboard up).
    var isSearching: Bool {
        let field = app.searchFields.firstMatch
        guard field.exists else { return false }
        let value = (field.value as? String) ?? ""
        return app.keyboards.count > 0 || (!value.isEmpty && value != field.placeholderValue)
    }

    /// Clears the search text and leaves search mode (the button is "Close" on iOS 26+, "Cancel" before).
    func clearSearch() {
        let field = app.searchFields.firstMatch
        guard field.exists else { return }
        let clear = field.buttons["Clear text"].firstMatch
        if clear.exists { clear.tap() }
        for label in ["Close", "Cancel"] {
            let button = app.buttons[label].firstMatch
            if button.exists && button.isHittable {
                button.tap()
                break
            }
        }
    }

    /// Record rows of the visible list ("record.row.<n>").
    var rows: XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'record.row.'"))
    }

    /// Replaces a text field's contents: puts the cursor at the trailing end, deletes until the field is empty,
    /// types, and checks the result.
    func replaceText(_ identifier: String, with text: String, file: StaticString = #filePath, line: UInt = #line) {
        let field = reveal(identifier)
        XCTAssertTrue(field.exists, "\(identifier) not found", file: file, line: line)
        func contents() -> String {
            let value = (field.value as? String) ?? ""
            return value == field.placeholderValue ? "" : value
        }
        for _ in 0..<3 {
            scrollAboveKeyboard(field)
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
            let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: field)
            _ = XCTWaiter().wait(for: [focused], timeout: 2)
            let current = contents()
            if current.isEmpty { break }
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2))
            if contents().isEmpty { break }
        }
        XCTAssertTrue(hasFocus(field), "\(identifier) didn't get keyboard focus", file: file, line: line)
        XCTAssertEqual(contents(), "", "\(identifier) couldn't be cleared", file: file, line: line)
        field.typeText(text)
        XCTAssertEqual(field.value as? String, text, "\(identifier) didn't take the new text", file: file, line: line)
    }

    /// Gets the on-screen keyboard out of the way when it covers the element (a tap on a covered field would land
    /// on a key instead): hides it on iPad, or drags the form up.
    func scrollAboveKeyboard(_ element: XCUIElement) {
        let keyboard = app.keyboards.firstMatch
        // Frames come back in portrait coordinates while an iPad runs in landscape, so don't compare them:
        // whenever another field has the keyboard, put it away first.
        // An iPad on iOS 27 keeps an off-screen keyboard in the hierarchy (zero height, keys below the window)
        // while nothing is shown; there is nothing to put away then.
        guard keyboard.exists, keyboard.frame.height > 0, !hasFocus(element) else { return }
        let hide = keyboard.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'hide keyboard' OR label CONTAINS[c] 'dismiss' OR identifier CONTAINS[c] 'dismiss'")).firstMatch
        if hide.exists {
            guard hide.isHittable else { return }
            hide.tap()
            _ = keyboard.waitForNonExistence(timeout: 3)
            return
        }
        print("KEYBOARD keys: \(keyboard.buttons.allElementsBoundByIndex.map { "\($0.identifier)|\($0.label)" })")
    }

    func hasFocus(_ element: XCUIElement) -> Bool {
        (element.value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }

    /// Taps the editor's Save / Add and waits for the sheet to close (one retry: a tap can be swallowed while the
    /// keyboard is going away on a busy simulator).
    func tapSave(file: StaticString = #filePath, line: UInt = #line) {
        tap("editor.save", file: file, line: line)
        let save = element("editor.save")
        if !save.waitForNonExistence(timeout: 4) && save.exists && save.isEnabled { save.tap() }
        XCTAssertTrue(save.waitForNonExistence(timeout: 6), "The editor didn't close", file: file, line: line)
    }

    /// The `n`th record row; fails if it doesn't appear.
    func row(_ n: Int) -> XCUIElement {
        let e = element("record.row.\(n)")
        XCTAssertTrue(e.waitForExistence(timeout: 10), "record.row.\(n) not found")
        return e
    }
}
