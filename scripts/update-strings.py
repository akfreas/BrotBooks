"""Merge strings extracted by the compiler into BrotBooks/Localizable.xcstrings.

Build once first (SWIFT_EMIT_LOC_STRINGS=YES writes *.stringsdata), then:
    python3 scripts/update-strings.py
Keys built at runtime (form field labels and tax assumptions from BrotBooksKit) are added as manual entries.
Existing entries and their translations are kept.
"""
import glob
import json
import os
import re

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
catalog_path = os.path.join(root, "BrotBooks", "Localizable.xcstrings")
catalog = {"sourceLanguage": "en", "strings": {}, "version": "1.0"}
if os.path.exists(catalog_path):
    catalog = json.load(open(catalog_path))

extracted = set()
for path in glob.glob(os.path.join(root, "build", "DerivedData", "Build", "Intermediates.noindex",
                                   "BrotBooks.build", "*", "BrotBooks.build", "Objects-normal", "*", "*.stringsdata")):
    for entry in json.load(open(path)).get("tables", {}).get("Localizable", []):
        extracted.add(entry["key"])

kit = os.path.join(root, "BrotBooksKit", "Sources", "BrotBooksKit")
manual = set(re.findall(r'label: "([^"]+)"', open(os.path.join(kit, "EditForm.swift")).read()))
manual |= set(re.findall(r'hint: "([^"]+)"', open(os.path.join(kit, "EditForm.swift")).read()))
taxes = open(os.path.join(kit, "Taxes.swift")).read()
block = taxes[taxes.index("assumptions = ["):taxes.index("]", taxes.index("assumptions = ["))]
manual |= set(re.findall(r'"([^"]+)"', block))
manual |= {"Paid", "Unpaid", "Service", "Germany", "European Union", "Outside of the European Union"}

strings = catalog["strings"]
for key in sorted(extracted | manual):
    entry = strings.setdefault(key, {})
    if key in manual and key not in extracted:
        entry["extractionState"] = "manual"
    else:
        entry.pop("extractionState", None)
for key in list(strings):
    if key not in extracted and key not in manual and not strings[key].get("localizations"):
        del strings[key]

json.dump(catalog, open(catalog_path, "w"), indent=2, ensure_ascii=False, sort_keys=True)
open(catalog_path, "a").write("\n")
print(f"{len(strings)} strings ({len(extracted)} extracted, {len(manual - extracted)} manual)")
