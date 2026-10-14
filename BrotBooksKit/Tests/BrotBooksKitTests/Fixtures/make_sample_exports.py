"""Regenerate the small Sorted-shaped export zips used by the Swift import tests.

Run from this directory: python3 make_sample_exports.py
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

EXPENSE_ROW = dict(zip(EXPENSE_HEADERS, [
    "Accounting software November 2021", "2021-11-04", "71.40", "71.40", "60.00", "11.40", "19%: 11.4",
    "EUR", "", "2021/2021-11-04 Accounting software November 2021 f00d1.pdf", "Software", "Germany",
    "71.40", "", "", "", "", "", "", "", "",
]))
INCOME_ROW = dict(zip(INCOME_HEADERS, [
    "Beispiel Consulting GmbH 3", "2021-12-01", "11900.00", "11900.00", "10000.00", "1900.00",
    "19%: 1900.0", "EUR", "", "2021/2021-12-01 Beispiel Consulting GmbH 3 c1e01.pdf",
    "Germany", "", "False", "Service", "Paid", "2021-12-01",
]))


def expense(ref, desc="Thing", amount="10.00"):
    return {**EXPENSE_ROW, "Description": desc, "Gross amount": amount,
            "Document filename": f"2021/2021-11-04 {desc} {ref}.pdf"}


def _csv(headers, rows):
    buf = io.StringIO()
    w = csv.DictWriter(buf, fieldnames=headers, quoting=csv.QUOTE_ALL)
    w.writeheader()
    w.writerows(rows)
    return "﻿" + buf.getvalue()


def make_export(path, expenses, income, *, docs=None, skip_docs=()):
    docs = docs or {}
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as z:
        for kind, headers, rows in (("expenses", EXPENSE_HEADERS, expenses), ("income", INCOME_HEADERS, income)):
            z.writestr(f"{kind}/{kind}.csv", _csv(headers, rows))
            for row in rows:
                fn = row["Document filename"]
                if fn not in skip_docs:
                    z.writestr(f"{kind}/documents/{fn}", docs.get(fn, f"%PDF-1.4 {fn}".encode()))
        # A stored (uncompressed) archive file, to cover both entry methods.
        z.writestr(zipfile.ZipInfo("tax-reports/vat/2021/Dezember 2021 VAT.pdf"), b"%PDF-1.4 vat",
                   compress_type=zipfile.ZIP_STORED)


quoted = expense("aaaa3", desc='Lunch, "team"', amount="23.80")
quoted["VAT rates"] = "7%: 0 | 19%: 3.8"
quoted["Description"] = 'Lunch, "team"\nwith newline'

make_export("sample_v1.zip", [expense("aaaa1"), expense("aaaa2", amount="5.00"), quoted], [INCOME_ROW],
            skip_docs={quoted["Document filename"]})
# v2: aaaa1 changed, aaaa2 gone (swept), aaaa3 unchanged, new aaaa4; aaaa1's doc missing (kept).
make_export("sample_v2.zip", [expense("aaaa1", amount="12.00"), quoted, expense("aaaa4")], [INCOME_ROW],
            skip_docs={quoted["Document filename"], expense("aaaa1")["Document filename"]})
# Empty income CSV: income must not be swept.
make_export("sample_empty_income.zip", [expense("aaaa1", amount="12.00"), quoted, expense("aaaa4")], [],
            skip_docs={quoted["Document filename"]})
