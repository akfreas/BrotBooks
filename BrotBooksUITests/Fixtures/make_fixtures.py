"""Regenerate the import fixtures used by the BrotBooks UI tests (fictional companies, 2026 dates).

Run from this directory: python3 make_fixtures.py

- ui_sorted_export.zip: a Sorted-shaped export (same layout as BrotBooksKit/Tests/.../make_sample_exports.py)
  with two expenses and one invoice.
"""

import csv
import io
import zipfile

EXPENSE_HEADERS = ["Description", "Date", "Gross amount", "Converted gross amount", "Net amount",
                   "Total VAT amount", "VAT rates", "Currency", "Currency conversion rate",
                   "Document filename", "Category", "Supplier's region", "Deductible amount",
                   "Asset lifetime (years)", "Private car - usage type", "Private car - distance driven",
                   "Private car - number of days driven to work", "Expense flat rate - start date",
                   "Expense flat rate - end date", "Business trip country", "Is a home office"]
INCOME_HEADERS = ["Description", "Date", "Gross amount", "Converted gross amount", "Net amount",
                  "Total VAT amount", "VAT rates", "Currency", "Currency conversion rate",
                  "Document filename", "Client's region", "Client's VAT number",
                  "Client is a private person (not a business)", "Sale type", "Payment status", "Payment date"]

# Fixed timestamp so regenerating gives byte-identical zips.
STAMP = (2026, 10, 10, 12, 0, 0)


def pdf(title, lines):
    """A minimal one-page PDF, the same shape as SampleData.pdf in BrotBooksKit."""
    stream = f"BT /F1 28 Tf 60 760 Td ({title}) Tj ET\n"
    for i, line in enumerate(lines):
        stream += f"BT /F1 13 Tf 60 {710 - i * 22} Td ({line}) Tj ET\n"
    stream += "0.32 0.4 0.92 RG 2 w 60 740 m 535 740 l S\n"
    objects = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        f"<< /Length {len(stream)} >>\nstream\n{stream}endstream",
    ]
    out = "%PDF-1.4\n"
    offsets = []
    for i, obj in enumerate(objects):
        offsets.append(len(out))
        out += f"{i + 1} 0 obj\n{obj}\nendobj\n"
    xref = len(out)
    out += f"xref\n0 {len(objects) + 1}\n0000000000 65535 f \n"
    for o in offsets:
        out += f"{o:010d} 00000 n \n"
    out += f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n"
    return out.encode()


def write(z, name, data):
    z.writestr(zipfile.ZipInfo(name, STAMP), data, compress_type=zipfile.ZIP_DEFLATED)


def csv_text(headers, rows):
    buf = io.StringIO()
    w = csv.DictWriter(buf, fieldnames=headers, quoting=csv.QUOTE_ALL)
    w.writeheader()
    w.writerows(rows)
    return "﻿" + buf.getvalue()


def sorted_export(path):
    blank_e = dict.fromkeys(EXPENSE_HEADERS, "")
    blank_i = dict.fromkeys(INCOME_HEADERS, "")
    expenses = [
        {**blank_e, "Description": "Drafting table", "Date": "2026-10-02", "Gross amount": "476.00",
         "Converted gross amount": "476.00", "Net amount": "400.00", "Total VAT amount": "76.00",
         "VAT rates": "19%: 76.0", "Currency": "EUR", "Document filename": "2026/2026-10-02 Drafting table a7e01.pdf",
         "Category": "Office equipment", "Supplier's region": "Germany", "Deductible amount": "476.00"},
        {**blank_e, "Description": "Train to Hamburg", "Date": "2026-09-15", "Gross amount": "89.90",
         "Converted gross amount": "89.90", "Net amount": "84.02", "Total VAT amount": "5.88",
         "VAT rates": "7%: 5.88", "Currency": "EUR", "Document filename": "2026/2026-09-15 Train to Hamburg a7e02.pdf",
         "Category": "Travel", "Supplier's region": "Germany", "Deductible amount": "89.90"},
    ]
    income = [
        {**blank_i, "Description": "Fernweh Media GmbH 2609-1", "Date": "2026-09-30", "Gross amount": "5950.00",
         "Converted gross amount": "5950.00", "Net amount": "5000.00", "Total VAT amount": "950.00",
         "VAT rates": "19%: 950.0", "Currency": "EUR",
         "Document filename": "2026/2026-09-30 Fernweh Media GmbH 2609-1 b9c01.pdf", "Client's region": "Germany",
         "Client is a private person (not a business)": "False", "Sale type": "Service",
         "Payment status": "Paid", "Payment date": "2026-10-05"},
    ]
    with zipfile.ZipFile(path, "w") as z:
        for kind, headers, rows in (("expenses", EXPENSE_HEADERS, expenses), ("income", INCOME_HEADERS, income)):
            write(z, f"{kind}/{kind}.csv", csv_text(headers, rows))
            for row in rows:
                write(z, f"{kind}/documents/{row['Document filename']}",
                      pdf("Invoice" if kind == "income" else "Receipt",
                          [row["Description"], row["Date"], f"Total EUR {row['Gross amount']}"]))


sorted_export("ui_sorted_export.zip")
