import Foundation

/// A generated, fictional dataset for demos, screenshots and simulator runs (never real records).
public enum SampleData {
    struct Generator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state >> 33
        }
        mutating func amount(_ low: Int, _ high: Int) -> Decimal {
            Decimal(low * 100 + Int(next() % UInt64((high - low) * 100))) / 100
        }
    }

    static let clients = ["Northwind Analytics GmbH", "Blue Harbor Studio", "Kestrel Labs Ltd", "Lindqvist & Partner"]
    static let software = ["GitHub", "Figma", "Notion", "1Password", "Linear", "Fastmail"]

    /// Loads two years of sample income and expenses (the previous year in full, the current year to `today`).
    @MainActor
    public static func load(into store: RecordStore, today: String) throws {
        guard let now = ISODate.components(today) else { return }
        var g = Generator(state: 42)
        for year in [now.year - 1, now.year] {
            let lastMonth = year == now.year ? now.month : 12
            for month in 1...lastMonth {
                let day = min(28, year == now.year && month == now.month ? now.day : 28)
                let date = ISODate.make(year, month, min(day, 3 + Int(g.next() % 20)))
                // One or two invoices a month.
                for n in 0..<(1 + Int(g.next() % 2)) {
                    let client = clients[Int(g.next() % UInt64(clients.count))]
                    let net = Decimal(4000 + Int(g.next() % 70) * 100)
                    let domestic = !client.hasSuffix("Ltd")
                    let vat = domestic ? Money.rounded(net * Decimal(string: "0.19")!) : 0
                    let paid = !(year == now.year && month >= now.month - 1 && n == 0)
                    var fields: [String: FieldInput] = [
                        "description": .text("\(client) \(year % 100)\(String(format: "%02d", month))-\(n + 1)"),
                        "date": .text(date), "gross_amount": .text(Money.plainString(net + vat)),
                        "client_region": .text(domestic ? "Germany" : "Outside of the European Union"),
                        "payment_status": .text(paid ? "Paid" : "Unpaid"),
                        "vat_rates": .vatRates(domestic ? [VatRowInput(rate: "19", amount: Money.plainString(vat))] : []),
                    ]
                    // Paid at the end of the month, or by today for this month's invoices.
                    if paid { fields["payment_date"] = .text(min(ISODate.make(year, month, 28), today)) }
                    try store.create(.income, fields: fields, document: pdf(title: "Invoice", lines: [
                        client, "Consulting services \(Dates.monthName(month)) \(year)",
                        "Net \(Money.format(net))", "VAT \(Money.format(vat))", "Total \(Money.format(net + vat))",
                    ]))
                }
                try expense(store, date, "Coworking desk \(Dates.monthName(month))", "Rent", 350, vat: true)
                for _ in 0..<(2 + Int(g.next() % 3)) {
                    let name = software[Int(g.next() % UInt64(software.count))]
                    try expense(store, date, "\(name) subscription", "Software", g.amount(8, 60), vat: g.next() % 2 == 0,
                                region: "Outside of the European Union")
                }
                if g.next() % 3 == 0 {
                    try store.create(.expenses, fields: [
                        "description": .text("Client lunch"), "date": .text(date), "gross_amount": .text("71.40"),
                        "category": .text("Business meals"), "deductible_amount": .text("49.98"),
                        "vat_rates": .vatRates([VatRowInput(rate: "19", amount: "11.40")]),
                    ])
                }
                if month % 3 == 0 {
                    try store.create(.expenses, fields: [
                        "description": .text("VAT prepayment Q\(month / 3)"), "date": .text(ISODate.make(year, month, 10)),
                        "gross_amount": .text("2400"), "category": .text(SortedMarkers.vatPaymentCategory),
                        "supplier_region": .text("Germany"),
                    ])
                }
            }
            try store.create(.expenses, fields: [
                "description": .text("AWS invoice"), "date": .text(ISODate.make(year, min(lastMonth, 6), 2)),
                "gross_amount": .text("120.00"), "currency": .text("USD"), "currency_conversion_rate": .text("0.9172"),
                "category": .text("Software"), "supplier_region": .text("Outside of the European Union"),
            ])
        }
    }

    @MainActor
    static func expense(_ store: RecordStore, _ date: String, _ description: String, _ category: String, _ gross: Decimal,
                        vat: Bool, region: String = "Germany") throws {
        let vatAmount = vat ? Money.rounded(gross - gross / Decimal(string: "1.19")!) : 0
        try store.create(.expenses, fields: [
            "description": .text(description), "date": .text(date), "gross_amount": .text(Money.plainString(gross)),
            "category": .text(category), "supplier_region": .text(region),
            "vat_rates": .vatRates(vat ? [VatRowInput(rate: "19", amount: Money.plainString(vatAmount))] : []),
        ])
    }

    enum Dates {
        static func monthName(_ m: Int) -> String {
            ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
             "November", "December"][m - 1]
        }
    }

    /// A minimal one-page PDF with a title and a few lines of Helvetica text.
    public static func pdf(title: String, lines: [String]) -> Data {
        func escape(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "(", with: "\\(")
                .replacingOccurrences(of: ")", with: "\\)").replacingOccurrences(of: "€", with: "EUR ")
        }
        var stream = "BT /F1 28 Tf 60 760 Td (\(escape(title))) Tj ET\n"
        for (i, line) in lines.enumerated() {
            stream += "BT /F1 13 Tf 60 \(710 - i * 22) Td (\(escape(line))) Tj ET\n"
        }
        stream += "0.32 0.4 0.92 RG 2 w 60 740 m 535 740 l S\n"
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
            "<< /Length \(stream.utf8.count) >>\nstream\n\(stream)endstream",
        ]
        var out = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (i, obj) in objects.enumerated() {
            offsets.append(out.utf8.count)
            out += "\(i + 1) 0 obj\n\(obj)\nendobj\n"
        }
        let xref = out.utf8.count
        out += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for o in offsets { out += String(format: "%010d 00000 n \n", o) }
        out += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        return Data(out.utf8)
    }
}
