import XCTest

/// One test per happy path, on iPhone and iPad. Sample data is generated for 2025 and 2026 with "today" pinned
/// to 2026-10-10, so the amounts below are stable. Screenshots are attached as "<device>-NN-<feature>".
final class HappyPathTests: BrotBooksUITestCase {

    // MARK: Dashboard

    func test00EmptyState() {
        launch(empty: true)
        XCTAssertTrue(element("dashboard.empty").exists)
        XCTAssertTrue(app.buttons["Import Sorted Export…"].firstMatch.exists)
        XCTAssertTrue(app.buttons["New Expense"].firstMatch.exists)
        screenshot("00-empty-state")
    }

    func test01Dashboard() {
        launch()
        XCTAssertEqual(text("dashboard.period"), "Jan 1, 2026 – Oct 10, 2026")
        XCTAssertEqual(text("dashboard.taxTotal"), "€51,680.33")
        XCTAssertEqual(text("dashboard.incomeCard.net"), "€124,600.00")
        XCTAssertEqual(text("dashboard.incomeCard.previous"), "€114,000.00 same period 2025")
        XCTAssertEqual(text("dashboard.expensesCard.net"), "€4,104.38")
        XCTAssertTrue(element("dashboard.taxCard").exists)
        screenshot("01-dashboard")
        let chart = element("dashboard.profitCard")
        if !isPad { app.swipeUp() }
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
        XCTAssertEqual(text("dashboard.profitTotal"), "€120,495.62")
        XCTAssertTrue(element("dashboard.chart").exists, "The profit chart didn't render")
        screenshot("01-dashboard-chart")
    }

    func test02YearSwitching() {
        launch()
        XCTAssertEqual(text("dashboard.taxTotal"), "€51,680.33")
        pickYear(2025)
        waitForText("dashboard.period", contains: "Dec 31, 2025")
        XCTAssertEqual(text("dashboard.period"), "Jan 1, 2025 – Dec 31, 2025")
        XCTAssertNotEqual(text("dashboard.taxTotal"), "€51,680.33")
        XCTAssertNotEqual(text("dashboard.incomeCard.net"), "€124,600.00")
        XCTAssertTrue(text("dashboard.incomeCard.previous").hasSuffix("in 2024"))
        screenshot("02-year-2025")
        pickYear(2026)
        waitForText("dashboard.taxTotal", contains: "€51,680.33")
    }

    // MARK: Browsing

    func test03BrowseIncome() {
        launch()
        go(to: .income)
        XCTAssertEqual(text("records.header"), "17 records, €142,460.00")
        XCTAssertTrue(row(0).label.contains("Blue Harbor Studio 2610-2"))
        screenshot("03-income-list")
        search("Kestrel")
        waitForText("records.header", contains: "records,")
        XCTAssertLessThan(rows.count, 17)
        XCTAssertGreaterThan(rows.count, 0)
        for i in 0..<rows.count { XCTAssertTrue(rows.element(boundBy: i).label.contains("Kestrel Labs")) }
        screenshot("03-income-search")
        row(0).tap()
        openDocumentAndCheckPreview(kind: "income")
    }

    func test04BrowseExpenses() {
        launch()
        go(to: .expenses)
        XCTAssertTrue(row(0).exists)
        screenshot("04-expenses-list")
        search("Coworking")
        waitForText("record.row.0", contains: "Coworking desk")
        for i in 0..<rows.count { XCTAssertTrue(rows.element(boundBy: i).label.contains("Coworking desk")) }
        // One coworking desk a month, January to October (the list is lazy, so count via its header).
        waitForText("records.header", contains: "10 records, €3,500.00")
        screenshot("04-expenses-search")
        clearSearch()
        search("No such vendor")
        XCTAssertTrue(element("records.empty").waitForExistence(timeout: 5))
        screenshot("04-expenses-no-results")
        clearSearch()
        row(0).tap()
        XCTAssertTrue(element("editor.save").waitForExistence(timeout: 5))
        screenshot("04-expense-editor")
    }

    /// From an open income editor: the PDF preview (beside the form on iPad, one tap away on iPhone).
    private func openDocumentAndCheckPreview(kind: String) {
        XCTAssertTrue(element("editor.save").waitForExistence(timeout: 5))
        XCTAssertTrue(element("editor.paymentStatus").exists)
        screenshot("03-\(kind)-editor")
        if !isPad { tap("editor.document") }
        XCTAssertTrue(element("document.preview").waitForExistence(timeout: 10), "No PDF preview")
        XCTAssertTrue(element("document.share").waitForExistence(timeout: 5), "No share button for the PDF")
        screenshot("03-\(kind)-document")
    }

    // MARK: Editing

    func test05EditAndSave() {
        launch()
        go(to: .expenses)
        search("Coworking desk October")
        waitForText("record.row.0", contains: "Coworking desk October")
        XCTAssertTrue(row(0).label.contains("−€350.00"))
        row(0).tap()
        XCTAssertEqual(text("editor.net"), "Net, €294.12")
        replaceText("field.description", with: "Coworking desk October, team room")
        replaceText("field.gross_amount", with: "476.00")
        screenshot("05-edit-changes")
        tapSave()
        clearSearch()
        search("team room")
        waitForText("record.row.0", contains: "Coworking desk October, team room")
        XCTAssertTrue(row(0).label.contains("−€476.00"))
        screenshot("05-edit-saved-list")
        row(0).tap()
        XCTAssertEqual(text("editor.gross"), "Gross (EUR), €476.00")
        XCTAssertEqual(text("editor.vat"), "VAT, €55.88")
        // Net is recalculated from the new gross: 476.00 − 55.88 VAT.
        XCTAssertEqual(text("editor.net"), "Net, €420.12")
        screenshot("05-edit-recalculated")
        tap("editor.cancel")
        go(to: .dashboard)
        // Expenses net went up by the edit: 4,104.38 − 294.12 + 420.12.
        waitForText("dashboard.expensesCard.net", contains: "€4,230.38")
    }

    func test06MarkAsPaid() {
        launch()
        go(to: .income)
        let unpaid = rows.matching(NSPredicate(format: "label CONTAINS 'Unpaid'"))
        XCTAssertEqual(unpaid.count, 2, "The sample data has two unpaid invoices")
        // From the editor.
        unpaid.firstMatch.tap()
        waitForText("editor.paymentStatus", contains: "Unpaid")
        screenshot("06-unpaid-invoice")
        tap("editor.markPaid")
        XCTAssertTrue(element("editor.notice").waitForExistence(timeout: 5))
        waitForText("editor.paymentStatus", contains: "Paid")
        XCTAssertFalse(text("editor.paymentStatus").contains("Unpaid"))
        screenshot("06-marked-paid-editor")
        tap("editor.cancel")
        XCTAssertEqual(unpaid.count, 1)
        // From a swipe action.
        let last = unpaid.firstMatch
        last.swipeRight()
        let action = app.buttons["Mark as Paid"].firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 5), "No Mark as Paid swipe action")
        screenshot("06-swipe-mark-paid")
        action.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 0"), object: unpaid)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed, "An invoice is still unpaid")
        screenshot("06-all-paid")
    }

    func test07NewExpenseAndIncome() {
        launch()
        go(to: .expenses)
        tap("newExpense")
        XCTAssertTrue(app.navigationBars["New Expense"].waitForExistence(timeout: 5))
        replaceText("field.description", with: "Ergonomic chair")
        replaceText("field.category", with: "Office equipment")
        replaceText("field.gross_amount", with: "399.00")
        screenshot("07-new-expense-form")
        tapSave()
        waitForText("record.row.0", contains: "Ergonomic chair")
        XCTAssertTrue(row(0).label.contains("−€399.00"))
        screenshot("07-new-expense-list")

        go(to: .dashboard)
        tap("toolbar.menu")
        tap("newIncome")
        XCTAssertTrue(app.navigationBars["New Income"].waitForExistence(timeout: 5))
        replaceText("field.description", with: "Seeadler Reisen 2610-1")
        replaceText("field.gross_amount", with: "2380.00")
        screenshot("07-new-income-form")
        tapSave()
        go(to: .income)
        waitForText("record.row.0", contains: "Seeadler Reisen 2610-1")
        XCTAssertTrue(row(0).label.contains("+€2,380.00"))
        XCTAssertTrue(row(0).label.contains("Unpaid"))
        screenshot("07-new-income-list")
    }

    func test08RemoveAndRestore() {
        launch()
        go(to: .expenses)
        let first = row(0)
        let description = "Coworking desk October"
        search(description)
        waitForText("record.row.0", contains: description)
        XCTAssertEqual(rows.count, 1)
        first.swipeLeft()
        let remove = app.buttons["Remove"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5), "No Remove swipe action")
        screenshot("08-swipe-remove")
        remove.tap()
        XCTAssertTrue(element("records.empty").waitForExistence(timeout: 5))
        tap("records.removedToggle")
        let removed = element("record.removed.0")
        XCTAssertTrue(removed.waitForExistence(timeout: 5))
        XCTAssertTrue(removed.label.contains(description) && removed.label.contains("Removed"))
        screenshot("08-removed-section")
        removed.swipeLeft()
        let restore = app.buttons["Restore"].firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout: 5), "No Restore swipe action")
        restore.tap()
        waitForText("record.row.0", contains: description)
        XCTAssertFalse(element("records.removedToggle").exists)
        screenshot("08-restored")
    }

    // MARK: Import

    func test09ImportSortedExport() {
        launch(fixtures: [.sortedExport: "ui_sorted_export.zip"])
        tap("toolbar.menu")
        tap("importSortedExport")
        XCTAssertTrue(element("import.confirm").waitForExistence(timeout: 15), "No import preview")
        waitForText("import.intro", contains: "ui_sorted_export.zip")
        XCTAssertTrue(text("import.expenses.new").hasSuffix("2"))
        XCTAssertTrue(text("import.income.new").hasSuffix("1"))
        XCTAssertTrue(text("import.expenses.documents").hasSuffix("2"))
        screenshot("09-import-preview")
        tap("import.confirm")
        XCTAssertTrue(element("import.done").waitForExistence(timeout: 15), "The import didn't finish")
        waitForText("import.intro", contains: "Imported")
        XCTAssertTrue(text("import.income.new").hasSuffix("1"))
        screenshot("09-import-result")
        tap("import.done")
        // 124,600.00 + 5,000.00 net from the imported invoice.
        waitForText("dashboard.incomeCard.net", contains: "€129,600.00")
        go(to: .income)
        search("Fernweh")
        waitForText("record.row.0", contains: "Fernweh Media GmbH 2609-1")
        XCTAssertEqual(rows.count, 1)
        screenshot("09-imported-record")
        row(0).tap()
        if !isPad { tap("editor.document") }
        XCTAssertTrue(element("document.preview").waitForExistence(timeout: 10), "The imported PDF didn't open")
    }

    func test13ImportInvoices() {
        launch(invoices: ["invoice_text.pdf", "invoice_photo.heic", "invoice_photo_rotated.jpg"])
        XCTAssertEqual(text("dashboard.taxTotal"), "€51,680.33")
        XCTAssertEqual(text("dashboard.expensesCard.net"), "€4,104.38")
        tap("toolbar.menu")
        tap("importInvoices")
        XCTAssertTrue(element("invoiceImport.panel").waitForExistence(timeout: 10), "No import progress panel")
        screenshot("13-import-progress")
        XCTAssertTrue(element("invoiceImport.review").waitForExistence(timeout: 30), "The import didn't finish")
        waitForText("invoiceImport.status", contains: "3 drafts ready to review")
        // The stub has canned results for the PDF and the HEIC photo, and nothing for the JPEG.
        waitForText("invoiceImport.row.0", contains: "Ready")
        waitForText("invoiceImport.row.1", contains: "Ready")
        waitForText("invoiceImport.row.2", contains: "Needs attention")
        screenshot("13-import-done")
        tap("invoiceImport.review")
        XCTAssertTrue(element("invoiceImport.panel").waitForNonExistence(timeout: 5))
        // Review Drafts opens the editor on the first draft, over the Drafts section.
        waitForText("review.counter", contains: "1 of 3")
        tap("editor.cancel")
        XCTAssertTrue(element("review.counter").waitForNonExistence(timeout: 5))
        waitForText("records.drafts", contains: "(3)")
        for n in 0..<3 { XCTAssertTrue(element("record.draft.\(n)").waitForExistence(timeout: 5), "No draft \(n)") }
        let labels = (0..<3).map { element("record.draft.\($0)").label }.joined(separator: " | ")
        XCTAssertTrue(labels.contains("Nordlicht Cloud Hosting – Oct 2026"), labels)
        XCTAssertTrue(labels.contains("Druckerei Beispiel – business cards"), labels)
        XCTAssertTrue(labels.contains("invoice_photo_rotated.jpg"), labels)
        screenshot("13-drafts")
        // Drafts don't count toward any total.
        go(to: .dashboard)
        XCTAssertEqual(text("dashboard.taxTotal"), "€51,680.33")
        XCTAssertEqual(text("dashboard.expensesCard.net"), "€4,104.38")
    }

    func test14ReviewAndApprove() {
        launch(invoices: ["invoice_photo.png", "invoice_photo.heic"])
        importInvoices(drafts: 2, review: true)
        // Review Drafts opens the editor on the first draft (newest first): the photo whose VAT didn't add up.
        XCTAssertTrue(element("review.approveNext").waitForExistence(timeout: 10), "Review Drafts didn't open the editor")
        waitForText("review.counter", contains: "1 of 2")
        XCTAssertTrue(app.navigationBars["Papierhaus Elbe – printer paper"].exists)
        if isPad {
            XCTAssertTrue(element("document.preview").waitForExistence(timeout: 10), "No PDF beside the form")
        } else {
            tap("editor.document")
            XCTAssertTrue(element("document.preview").waitForExistence(timeout: 10), "No PDF preview")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(reveal("review.approveNext").exists)
        }
        waitForText("flag.vat_rates", contains: "VAT didn't add up to the total")
        XCTAssertFalse(element("flag.gross_amount").exists)
        screenshot("14-review-flagged")
        tap("vat.add")
        replaceText("vat.amount.0", with: "19.00")
        XCTAssertTrue(element("flag.vat_rates").waitForNonExistence(timeout: 5), "The marker stayed after the fix")
        screenshot("14-review-fixed")
        tapApproveNext {
            let counter = self.element("review.counter")
            return counter.exists && counter.label.contains("2 of 2")
        }
        // The next draft; Skip leaves it a draft and closes the review after the last one.
        waitForText("review.counter", contains: "2 of 2")
        XCTAssertTrue(app.navigationBars["Druckerei Beispiel – business cards"].waitForExistence(timeout: 5))
        screenshot("14-review-next")
        tap("review.skip")
        XCTAssertTrue(element("review.counter").waitForNonExistence(timeout: 5), "The review didn't close")
        waitForText("records.drafts", contains: "(1)")
        // 4,104.38 + 100.00 net from the approved invoice (119.00 with 19.00 VAT).
        go(to: .dashboard)
        waitForText("dashboard.expensesCard.net", contains: "€4,204.38")
    }

    func test15ApproveSelected() {
        launch(invoices: ["invoice_text.pdf", "invoice_photo.heic", "invoice_photo_rotated.jpg"])
        importInvoices(drafts: 3, review: false)
        go(to: .expenses)
        waitForText("records.drafts", contains: "(3)")
        let clean = draftRow("Nordlicht Cloud Hosting"), medium = draftRow("Druckerei Beispiel"),
            blank = draftRow("invoice_photo_rotated.jpg")
        XCTAssertTrue(clean.label.contains("Looks complete"), clean.label)
        XCTAssertFalse(medium.label.contains("Looks complete"), medium.label)
        // A blank draft shows a placeholder amount, not €0.00.
        XCTAssertTrue(blank.label.contains("—") && !blank.label.contains("€0.00"), blank.label)
        screenshot("15-drafts-looks-complete")
        tap("records.edit")
        for row in [clean, medium, blank] { row.tap() }
        screenshot("15-drafts-selected")
        tap("records.approveSelected")
        // Every approval still runs validation: the blank draft stays a draft.
        let alert = app.alerts["1 draft not approved"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "No alert for the draft that wasn't approved")
        screenshot("15-approve-selected-result")
        alert.buttons["OK"].tap()
        waitForText("records.drafts", contains: "(1)")
        XCTAssertTrue(draftRow("invoice_photo_rotated.jpg").exists)
        go(to: .dashboard)
        // 4,104.38 + 100.00 + 50.00 net from the two approved invoices.
        waitForText("dashboard.expensesCard.net", contains: "€4,254.38")
    }

    func test16ApproveValidation() {
        launch(invoices: ["invoice_scanned.pdf"])
        importInvoices(drafts: 1, review: true)
        XCTAssertTrue(element("review.approveNext").waitForExistence(timeout: 10), "Review Drafts didn't open the editor")
        waitForText("review.counter", contains: "1 of 1")
        waitForText("flag.currency_conversion_rate", contains: "Foreign currency – enter the rate")
        tap("review.approveNext")
        waitForText("issue.currency_conversion_rate", contains: "Enter the conversion rate to EUR")
        XCTAssertTrue(element("review.counter").exists, "A draft without a rate was approved")
        XCTAssertTrue(element("editor.draftPill").exists)
        screenshot("16-approve-validation")
        replaceText("field.currency_conversion_rate", with: "0.9")
        XCTAssertTrue(element("flag.currency_conversion_rate").waitForNonExistence(timeout: 5))
        tapApproveNext { !self.element("review.counter").exists }
        XCTAssertTrue(element("review.counter").waitForNonExistence(timeout: 5), "The review didn't close")
        XCTAssertFalse(element("records.drafts").exists)
        search("Orbit Tools")
        waitForText("record.row.0", contains: "Orbit Tools – team plan Sep 2026")
    }

    func test17SwipeApprove() {
        launch(invoices: ["invoice_text.pdf", "invoice_photo_rotated.jpg"])
        importInvoices(drafts: 2, review: false)
        go(to: .expenses)
        waitForText("records.drafts", contains: "(2)")
        // A tap on a draft opens it; a tap on an approved expense still opens that one.
        draftRow("Nordlicht Cloud Hosting").tap()
        XCTAssertTrue(element("editor.approve").waitForExistence(timeout: 5), "Tapping a draft didn't open it")
        tap("editor.cancel")
        row(0).tap()
        XCTAssertTrue(element("editor.save").waitForExistence(timeout: 5), "Tapping an expense didn't open it")
        XCTAssertFalse(element("editor.approve").exists)
        tap("editor.cancel")
        XCTAssertTrue(element("editor.save").waitForNonExistence(timeout: 5))

        draftRow("Nordlicht Cloud Hosting").swipeRight()
        let approve = app.buttons["Approve"].firstMatch
        XCTAssertTrue(approve.waitForExistence(timeout: 5), "No Approve swipe action")
        screenshot("17-swipe-approve")
        approve.tap()
        waitForText("records.drafts", contains: "(1)")
        // An incomplete draft opens in the editor with what's missing.
        draftRow("invoice_photo_rotated.jpg").swipeRight()
        app.buttons["Approve"].firstMatch.tap()
        waitForText("issue.gross_amount", contains: "Enter the gross amount")
        screenshot("17-swipe-approve-incomplete")
        tap("editor.cancel")
        XCTAssertTrue(element("editor.save").waitForNonExistence(timeout: 5))
        // Remove soft-deletes a draft like any record; it can be restored.
        draftRow("invoice_photo_rotated.jpg").swipeLeft()
        let remove = app.buttons["Remove"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5), "No Remove swipe action")
        remove.tap()
        XCTAssertTrue(element("records.drafts").waitForNonExistence(timeout: 5))
        // The Removed section is at the end of the list (on iPad, past the sidebar's list).
        let list = recordsList
        for _ in 0..<15 where !(element("records.removedToggle").exists && element("records.removedToggle").isHittable) {
            list.swipeUp()
        }
        tap("records.removedToggle")
        let removed = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'record.removed.' AND label CONTAINS 'invoice_photo_rotated.jpg'"))
            .firstMatch
        XCTAssertTrue(removed.waitForExistence(timeout: 5), "The removed draft isn't in the Removed section")
        // Scroll to the end of the list, out from under the iPhone tab bar.
        list.swipeUp()
        screenshot("17-removed-draft")
        removed.swipeLeft()
        let restore = app.buttons["Restore"].firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout: 5), "No Restore swipe action")
        restore.tap()
        // Back in the Drafts section at the top of the list.
        for _ in 0..<15 where !element("records.drafts").exists { list.swipeDown() }
        waitForText("records.drafts", contains: "(1)")
        go(to: .dashboard)
        // 4,104.38 + 100.00 net from the approved invoice.
        waitForText("dashboard.expensesCard.net", contains: "€4,204.38")
    }

    /// Imports the invoices handed to `launch(invoices:)` and finishes with Review Drafts or Done.
    private func importInvoices(drafts: Int, review: Bool) {
        tap("toolbar.menu")
        tap("importInvoices")
        XCTAssertTrue(element("invoiceImport.review").waitForExistence(timeout: 30), "The import didn't finish")
        waitForText("invoiceImport.status", contains: drafts == 1 ? "1 draft ready" : "\(drafts) drafts ready")
        tap(review ? "invoiceImport.review" : "invoiceImport.done")
        XCTAssertTrue(element("invoiceImport.panel").waitForNonExistence(timeout: 5))
    }

    /// Taps Approve & Next until `done` holds (one retry: the first tap can be swallowed while a text field gives up
    /// the keyboard).
    private func tapApproveNext(file: StaticString = #filePath, line: UInt = #line, until done: () -> Bool) {
        // The iPad's floating number pad can cover the button; a tap outside it puts it away.
        if isPad { element("review.counter").tap() }
        tap("review.approveNext", file: file, line: line)
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline && !done() { RunLoop.current.run(until: Date().addingTimeInterval(0.25)) }
        if !done(), element("review.approveNext").exists {
            tap("review.approveNext", file: file, line: line)
        }
    }

    /// The Income or Expenses list (not the iPad sidebar).
    private var recordsList: XCUIElement {
        app.collectionViews.containing(NSPredicate(format: "identifier BEGINSWITH 'record.'")).firstMatch
    }

    /// The Drafts section row whose label contains `text`.
    private func draftRow(_ text: String) -> XCUIElement {
        let e = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'record.draft.' AND label CONTAINS %@", text)).firstMatch
        XCTAssertTrue(e.waitForExistence(timeout: 10), "No draft row with \"\(text)\"")
        return e
    }

    // MARK: Settings and appearance

    func test11Settings() {
        launch()
        tap("toolbar.menu")
        tap("openSettings")
        waitForText("settings.storage", contains: "This device only")
        waitForText("settings.icloud", contains: "Off (local store requested)")
        screenshot("11-settings")
        tap("settings.done")
        XCTAssertTrue(element("settings.done").waitForNonExistence(timeout: 5))
    }

    func test12DarkMode() {
        launch(dark: true)
        XCTAssertEqual(text("dashboard.taxTotal"), "€51,680.33")
        screenshot("12-dark-dashboard")
        go(to: .income)
        row(0).tap()
        XCTAssertTrue(element("editor.save").waitForExistence(timeout: 5))
        screenshot("12-dark-editor")
    }
}
