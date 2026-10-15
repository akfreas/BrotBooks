# Plan: monthly UStVA filing via ERiC (macOS only)

ERiC 44.3.6.0. "EHB" means `ERiC-44.3.6.0/Dokumentation/ERiC-Entwicklerhandbuch.pdf`.

## Decisions

1. **Every transaction type is in scope:**
   - German B2B sales
   - EU B2B services and goods sales
   - Reverse-charge purchases from the EU (for example Irish SaaS) and from outside the EU (for example US SaaS)
   - EU goods acquisitions
   - Imports

   EU B2B sales mean a **Zusammenfassende Meldung (ZM)** is also required. ERiC supports it as data type `ZMDO` with the plugin `libcheckZMDO.dylib`, so it is included (M4b).
2. **Every filing parameter is configurable, nothing is hardcoded.** Your current values (Soll-Versteuerung, monthly UStVA, Dauerfristverlängerung, monthly ZM) are only the initial settings. They are not baked into the code. See "Tax configuration" below.
3. **Personal use first.**
   - Single user and no onboarding polish.
   - The license data-protection acknowledgment is still shown once.
   - Distribution comes later.
4. **The PIN is stored in the Keychain** together with the certificate.

## 0. Prerequisites outside the code

These block a real filing, so start them first.

1. **Get a Hersteller-ID.**
   - Register as a developer at elster.de (Benutzergruppen → Entwickler). The login arrives by e-mail after a few days.
   - Then apply through "Antragsformular für eine Hersteller-ID".
   - The ID is mandatory even for test submissions. The public demo ID 74931 is blocked (`610301202 ERIC_IO_TESTHERSTELLERID_GESPERRT`).
   - It goes into `TransferHeader/HerstellerID` and into `Kz09`.
2. **Have your ELSTER certificate ready.** You need your own `.pfx` software certificate and its PIN, the same one you use for Mein ELSTER. UStVA must be sent as `send-Auth`; unsigned sending is not allowed.
3. **Check the ERiC license obligations.** `lizenz.pdf` §5 and §15 apply even for personal use:
   - Show the DSGVO letter and the "Datenschutzhinweis der Finanzverwaltung" once, and have the user confirm them.
   - Tell the user that `eric.log` is stored locally.
   - Keep ERiC at or above the Mindestversion.
   - Don't put "ELSTER" in the product name.
4. **Plan for the yearly ERiC update.**
   - 44.3.6.0 ships only `UStVA_2026`.
   - The January 2027 return, due in February, needs the next main release with `UStVA_2027`, expected in November 2026.
   - The Mindestversion is raised every April. Older libraries get rejected by the server.
   - So updating ERiC is a recurring yearly task (§7).

## Tax configuration

All filing rules come from a `TaxConfiguration` in BrotBooksKit. The aggregator, the XML builders and the deadline calculation take it as input and contain no tax constants of their own.

**Effective-dated.** Settings are stored as `TaxSettingsPeriod` rows, each valid from a date. The usual granularity is a calendar year, because the Finanzamt sets filing frequency and the Dauerfristverlängerung per year. Changing a setting today never rewrites past periods, and older filings can be recomputed exactly as they were filed.

**Stored as a new SwiftData model (`TaxProfile`).** It is additive and CloudKit-safe, so iOS sees the same values. The certificate and PIN stay in the Keychain on this Mac.

| Setting | Values | Your initial value |
|---|---|---|
| Taxation method | Soll / Ist | Soll |
| UStVA frequency | monthly / quarterly / none (annual return only) | monthly |
| Dauerfristverlängerung | on / off, plus the Sondervorauszahlung amount (computed as 1/11 of the prior year, editable) | on |
| ZM frequency | monthly / quarterly | monthly |
| ZM threshold for warning | amount of EU goods deliveries per quarter | €50,000 |
| Steuernummer, Finanzamt, USt-IdNr, name and address | — | — |
| Test mode | on / off | on |

**Derived from the configuration, not fixed in code:**
- **Due dates:**
  - UStVA: period end + 10 days, + 1 month with Dauerfristverlängerung.
  - ZM: the 25th after the period. ZM deadlines do not move with the Dauerfristverlängerung.
  - The offsets live in a `FilingDeadlines` table, so a legal change is a data change.
- **Tax rates:** `VatRateTable` with validity ranges, such as 19/7 standard and 16/5 from Jul 2020 to Dec 2020. Reverse-charge and acquisition VAT use the rate valid on the record date and the record's own rate row when it has one.
- **Kennzahl mapping:** a table from `VatTreatment` + rate to Kennzahl, versioned per UStVA year, because Kennzahlen occasionally change between years (check `Deltadokumentation/<year>`).
- **ZM frequency check:** the app warns when a quarter's EU goods deliveries cross the configured threshold while ZM is set to quarterly. It suggests switching but never switches by itself.

**Sondervorauszahlung (UStSV).** With Dauerfristverlängerung and monthly filing, the Sondervorauszahlung must be filed by 10 Feb each year. It goes through the same UStVA data type (sample `Beispiele/UStVA_SoVZ_2026.xml`, `UStVA_Df_2026.xml` for the Dauerfristverlängerung application). The amount is credited in the December return as Kz39. Both are part of M2/M4 when the setting is on.

## 1. Architecture overview

```
BrotBooksKit (cross-platform, pure Swift, fully unit-tested)
  └─ VAT/UStVA.swift          Period, Kennzahlen, aggregation from records, Kz83
  └─ VAT/UStVAXML.swift       Builds the ElsterAnmeldung XML (element order per XSD)
  └─ VAT/Steuernummer.swift   Value type for 13-digit ELSTER format + validation

EricKit (new local package, macOS-only)
  └─ CEric (C target)         Vendored ERiC headers + shim that dlopen()s libericapi
                              with RTLD_GLOBAL and resolves EricMt* symbols
  └─ EricKit (Swift)          `actor EricService`: one EricMtInstanz for the app
                              lifetime; validate / preview / send; result parsing

BrotBooks app (#if os(macOS) only)
  └─ VAT/VatReturnsView       Sidebar destination: months, status, detail, send
  └─ VAT/ElsterSettings       Tax profile, certificate, test mode
  └─ Model: VatFiling         SwiftData record of each filing (ticket, XML, PDF)

Vendor/ERiC (gitignored, filled by scripts/vendor-eric.sh)
  └─ libericapi, libericxerces, libeSigner, plugins/{libcommonData, libcheckUStVA_2026}
```

Why it is shaped like this:
- **Kennzahlen and XML live in BrotBooksKit.** The difficult and risky logic (which record lands in which Kennzahl, rounding, Kz83) is plain Swift there, so `swift test` covers it on any platform. iOS can later show "VAT due this month" read-only from the same code.
- **EricKit is a separate macOS-only package.** The app target is multiplatform (`project.yml:45-60`). In XcodeGen it is added with `platformFilters: [macOS]`, so iOS builds never see ERiC. All app code that uses it sits in `#if os(macOS)`.
- **ERiC is loaded with `dlopen`, not linked.** EHB 4.2.3 ("Empfohlenes Vorgehen für macOS") requires `dlopen(..., RTLD_GLOBAL)` of `libericapi.dylib` by absolute path, or crashes and PDF errors follow. The C shim resolves the function pointers once. Swift calls go through a struct of `@convention(c)` pointers, and the C structs (`eric_druck_parameter_t` v4, `eric_verschluesselungs_parameter_t` v3) come from the vendored `eric_types.h`.
- **Use the multithreading API (`EricMt*`).** One instance is created at first use and freed on quit (EHB 5.3.16), owned by an actor so it is never used by two threads at once. Its log path and PDF output point into the sandbox container.

## 2. Milestones

### M1: Vendoring and bridge (prove the library loads in the signed, sandboxed app)

1. **`scripts/vendor-eric.sh <path-to-jar>`:**
   - Extract into a temporary directory.
   - Copy the 3 base dylibs, `plugins/libcommonData.dylib` and `plugins/libcheckUStVA_<years>.dylib` into `Vendor/ERiC/`. That is about 50 MB instead of the 2.1 GB plugin folder.
   - Copy `include/*.h` into `EricKit/Sources/CEric/include/eric/`. The headers are small and stay committed.
   - Write `Vendor/ERiC/VERSION`.
2. **`.gitignore`:** add `Vendor/ERiC/`, `ERiC-*/`, `*.jar`, `*.pfx`.
3. **XcodeGen post-build script, macOS only:**
   - Copy `Vendor/ERiC` to `Contents/Frameworks/ERiC/`.
   - Re-sign every dylib with `$EXPANDED_CODE_SIGN_IDENTITY --options runtime --timestamp`, or `-` for the ad-hoc `scripts/build.sh mac` path. The dylibs ship ad-hoc signed and would fail library validation under the hardened runtime (`BrotBooks.xcconfig:33`).
   - `scripts/build.sh` fails early with a clear message if `Vendor/ERiC` is missing.
4. **`EricService.version()`** calls `EricMtVersion`. Show the result in Settings ("ERiC 44.3.6.0, UStVA 2026 plugin available").
   - **Done when** this works in a signed Release build with the sandbox on.
   - Sandbox notes: the network-client permission is already on (`BrotBooks.xcconfig:32`). Log directory is `~/Library/Containers/me.freas.BrotBooks/Data/Library/Application Support/ERiC/logs`. Paths must be passed in NFD (EHB 5.3.3.3).

### M2: UStVA computation and XML (pure Swift, test-driven)

1. **`VatPeriod`:**
   - Month or quarter, mapped to `Zeitraum` `01`–`12` or `41`–`44`.
   - Due date comes from `FilingDeadlines` and the active `TaxSettingsPeriod`.
2. **New field `vatTreatment: String?` on `Expense` and `Income`.**
   - **Why a new field:** region plus VAT rows can't tell the cases apart. An Irish SaaS invoice and an Irish goods invoice look the same, and so do a US service and an import. Every transaction type is in scope, so each record needs an explicit treatment.
   - **Storage:** an additive optional property, so it is CloudKit-safe (`Models.swift:4-10`). It is app-local like `reviewStatus`, not a Sorted CSV column, so `SortedExport` and `Columns` stay unchanged.
   - **Values (`enum VatTreatment` in BrotBooksKit):**

   | Income treatment | Kennzahlen | ZM |
   |---|---|---|
   | `domestic` (rates from `vatRates`) | Kz81 (standard rate net), Kz86 (reduced rate net), Kz35/36 (other) | – |
   | `euB2BService` (§3a(2), customer liable) | Kz21 | yes, Umsatzart S |
   | `euB2BGoods` (innergemeinschaftliche Lieferung) | Kz41 | yes, Umsatzart L |
   | `exportGoods` (Ausfuhr, §4 Nr.1a) | Kz43 | – |
   | `nonEUService` (place of supply abroad) | Kz45 | – |
   | `notTaxable` (e.g. damages, private) | nothing | – |

   | Expense treatment | Kennzahlen |
   |---|---|
   | `domesticVat` | Kz66 = VAT from `vatRates` × deductible share |
   | `rcEUService` (e.g. Irish SaaS) | Kz46 net, Kz47 = rate from `VatRateTable` × net, Kz67 = Kz47 × deductible share |
   | `rcNonEUService` (e.g. US SaaS, §13b(2) Nr.1) | Kz84 net, Kz85 = rate from `VatRateTable` × net, Kz67 = Kz85 × deductible share |
   | `euGoodsAcquisition` | Kz89 (standard) or Kz93 (reduced) net, Kz61 = acquisition VAT × deductible share |
   | `importVat` (customs EUSt notice) | Kz62 = the EUSt amount |
   | `noVat` (insurance, small business supplier, foreign VAT charged) | nothing |

   - **Suggesting a treatment:** `VatTreatment.suggest(record)` derives one from the existing fields:
     - Expenses: supplier region plus whether VAT rows are present. For example, an EU supplier with no VAT suggests `rcEUService`, and a non-EU supplier with no VAT suggests `rcNonEUService`.
     - Income: client region, VAT number and private-person flag. The invoice extractor (`InvoiceDraft.swift:292-311`) sets it on import.
     - A suggestion is shown as unconfirmed until it is set explicitly. The UStVA screen blocks sending while the period has unconfirmed records.
     - Goods vs. service always needs a confirmation.
   - **Editor:** a "VAT treatment" select field in `EditForm.fields` for both kinds.
   - **Deductible share:** `deductibleAmount / convertedGross` when set (deductibleAmount is a gross amount) (car, phone, home office), otherwise 100%. Defining this rule is part of M2 and gets its own tests.
3. **`UStVAAggregator`** turns the period and records into `Kennzahlen` plus a list of `ZMLine` (customer VAT ID, Umsatzart, amount).
   - It works from `vatRates`, `vatTreatment` and the EUR conversion. `LedgerEntry` (`Summary.swift:10-47`) can't be used because it has no per-rate breakdown or region.
   - Exclude drafts, removed records and VAT settlement records (`isVatPayment` / `isVatRefund`).
   - **Period assignment** follows the configured taxation method: Soll uses the record `date`, Ist uses `paymentDate` for income (expenses always by `date`). Unpaid income under Ist stays out of the period and is listed as a warning.
   - Reverse-charge bases use the EUR value converted at the record's rate.
4. **Formatting and Kz83:**
   - Bases are cut to whole euros. Tax amounts are written with 2 decimals.
   - Zero fields are left out, which avoids the `*_Nullwertangabe_Hinweis` warnings.
   - Kz83 is computed with the formula from the 2026 form. ERiC only checks that Kz83 is present, not that it is correct, so it must be right on the app side.
5. **`UStVAXML.build(...)`:**
   - Follow `Datenarten/ElsterAnmeldung/UStVA/Beispiele/UStVA_2026.xml`.
   - Emit elements in `xs:sequence` order (note that Kz93 comes before Kz90).
   - Set the `Testmerker 700000004` in test mode and omit it in production.
   - The namespace and `version` follow the year: `.../ustva/v2026`.
6. **Tests (Swift Testing, as in `RulesAndTaxTests`):**
   - Mapping per record type.
   - Rounding.
   - Kz83 reproduces the sample's `17050.00`.
   - A golden-file XML comparison.
   - Period and due-date edge cases.
   - One fixture per `VatTreatment`, including partial deductibility and a foreign-currency reverse-charge invoice.
   - `VatTreatment.suggest` for each region/VAT combination.
   - ZM lines grouped per customer VAT ID and Umsatzart.

### M3: Validate and preview in the app

1. Add `EricService.validate(xml, year)` with `VALIDIERE | PRUEFE_HINWEISE`, which is EBV-1/8.
   - Parse `<FehlerRegelpruefung>` (Feldidentifikator, Text) into user-facing messages.
   - Use `EricMtHoleFehlerText` for other error codes.
2. Add `EricService.preview(xml)` with `VALIDIERE | DRUCKE`, `vorschau=1` (EBV-2). It receives the PDF through `pdfCallback`, so no temp files.
3. Add a new `Destination.vatReturns` sidebar entry (`RootView.swift:6-24`) under `#if os(macOS)`:
   - **List:** months of the current and previous year, each with its status: not due, due in N days, overdue, filed (test) or filed.
   - **Detail:**
     - The Kennzahlen table with a drill-down to the contributing records.
     - Warnings: drafts in the period, records with no VAT rate, foreign currency without a rate, records with an unconfirmed VAT treatment, EU B2B income without a valid-looking customer VAT ID.
     - Toggles for Kz10 (correction), Kz22, Kz26 and Kz29.
     - Buttons "Validate" and "Preview PDF".
4. **Settings gets an "ELSTER" section**, macOS only:
   - **Steuernummer:** entered in the regional format and converted with `EricMtMakeElsterStnr`, then checked with `EricMtPruefeSteuernummer`.
   - **Finanzamt:** picked from `EricMtHoleFinanzaemter`.
   - **Your details:** name and address (DatenLieferant), USt-IdNr (required for the ZM).
   - **Filing settings:** the effective-dated table from "Tax configuration", edited per year with "Add settings from <date>".
   - **Test mode toggle**, on by default.
   - Stored in the `TaxProfile` SwiftData model, not `@AppStorage`, so the settings sync and carry their history.
   - The Hersteller-ID comes from `Config/BrotBooks.xcconfig` (`ELSTER_HERSTELLER_ID`), passed through Info.plist. It is not a user setting.
5. Show the license data-protection acknowledgment sheet before the first use of ELSTER features. Remember that it was accepted.

### M4: Certificate and test-mode sending

1. **Certificate import:**
   - The user picks a `.pfx` with `fileImporter`; `ENABLE_USER_SELECTED_FILES=readonly` already allows this.
   - The bytes are stored in the Keychain as a non-synced item.
   - The app opens it with `EricMtZertifikatOeffnenAusBytes`, so it never needs a sandbox file path afterwards.
   - It shows the holder and validity from `EricMtHoleZertifikatEigenschaften`.
2. **PIN:** stored in the Keychain next to the certificate (generic password item, `kSecAttrSynchronizable = false`, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`). Sending still requires an explicit confirmation sheet. A wrong-PIN error (`610201106`) clears the stored PIN and prompts again, and `610201107` (PIN locked) says so clearly.
3. **`EricService.send(xml, cert, pin)`** uses `VALIDIERE | SENDE | DRUCKE` (EBV-6).
   - Success means `rc == ERIC_OK` and the server answer `TransferHeader/RC/Rueckgabe/Code == 0`.
   - Store the `TransferTicket`, the request XML, the server response and the protocol PDF.
   - On timeout or connection errors (`610101278/279/271`), first check whether a ticket came back. Never resend automatically, because a second UStVA for the same month is a duplicate filing.
4. **New SwiftData model `VatFiling`.** It is additive and CloudKit-safe; every field is optional.
   - Fields: period, Kennzahlen JSON, ticket, timestamp, isTest, isCorrection, response XML, PDF stored through `DocumentStore`.
   - iOS can show filing history read-only from this model.
5. **Send flow in the UI:**
   - A confirmation sheet shows the Finanzamt, Steuernummer, period, Kz83 and a TEST or PRODUCTION badge.
   - Then a progress indicator (from `EricMtRegistriereFortschrittCallback`), and a result screen with the ticket and a "Show protocol" button.
6. **Tests:**
   - Env-gated live tests like `FoundationModelsLiveTests`.
   - `ERIC_LIVE=1` validates generated XML for several scenarios against the real `checkUStVA_2026` plugin. This is the best guard against schema and rule mistakes.
   - `ERIC_LIVE_SEND=1` sends with Testmerker 700000004 to test Finanzamt 1096, using the test certificate `test-softidnr-pse.pfx` (PIN `123456`) and your Hersteller-ID.
   - A `-elsterTransport stub` launch option (alongside `LaunchOptions.swift`) lets you work on the UI without network or certificate.

### M4b: Zusammenfassende Meldung (ZMDO)

EU B2B sales (Kz21, Kz41) also have to be reported per customer VAT ID to the BZSt.
- **Deadline** comes from `FilingDeadlines`.
- **Frequency** comes from the configured ZM frequency, with a threshold warning.
- **Plugin:** add `libcheckZMDO.dylib` to the vendor script.

Steps:
1. **`ZMXML.build`** in BrotBooksKit, modeled on `Datenarten/ElsterExtern/ZMDO/Beispiele/ZMDO_5_send-Auth.xml`.
   - Header: `Verfahren=ElsterExtern`, `DatenArt=ZMDO`, `Empfaenger id="L"` = `BF`.
   - Body: `zm` version `000005`, with `knri` = your USt-IdNr and one `zeile` with `knre` and `betrag` (whole euros) per customer and Umsatzart.
   - Read `Applikationsbedingungen_ZMDO_2.pdf` and `Jahresdokumentation_ZMDO_2.ods` for the period codes (`mzr`), `meldeart` and correction rules.
2. **Sending:** the same `EricService.send` path with datenartVersion `ZMDO`. Store the result as a `VatFiling` with `kind = "zm"`.
3. **UI:** the VAT returns screen shows the ZM next to the UStVA for the same period, with its own status.
4. **Consistency check:** the ZM totals must match Kz21 + Kz41 of the UStVAs for the same period. Show a warning if they don't.

### M5: First real filing

1. Switch test mode off. The production badge and an extra confirmation become visible.
2. **Cross-check before sending:** for the first one or two months, compare the Kennzahlen with your current filing method, either Mein ELSTER's form or your accountant's numbers.
3. File, and keep the protocol PDF.

### M6: Maintenance

1. Each November: re-run `scripts/vendor-eric.sh` with the new jar and add `libcheckUStVA_<newYear>`.
   - Teach `UStVAXML` the new namespace and version.
   - Check `Deltadokumentation/<year>` for changes to the Kennzahlen.
2. Each April: confirm the Mindestversion.
3. Settings shows the ERiC version and a warning when a period's year has no plugin, for example "January 2027 needs ERiC with UStVA_2027".

## 3. Risks and unknowns

- **Backfilling `vatTreatment`.** Existing records have no `vatTreatment` yet. Before the first filing, run a one-time review list of all records in open periods with suggested treatments to confirm. Without it the Kennzahlen are guesses.
- **Out of scope:** OSS (EU B2C digital services above €10,000) is filed through the BZSt portal, not ERiC. Domestic §13b sales (e.g. construction) are rare and left out. Add treatments if needed.
- **Checking customer VAT IDs.** Kz21 and Kz41 only apply with a valid customer USt-IdNr. A later add-on is the BZSt eVatR check of the ID, with the result stored on the record.
- **Partly deductible expenses.** Kz66 must use the deductible share of the VAT for mixed-use items like car, phone and home office. The `deductibleAmount` field exists, but the VAT split needs a defined rule.
- **Sandbox, hardened runtime and notarization.** The ERiC docs say nothing about these. M1 exists to prove them early. Fallback: the `com.apple.security.cs.disable-library-validation` entitlement.
- **Steuernummer conversion.** The detailed per-state rules are in a PDF that is not in the package. Use ERiC's own `MakeElsterStnr` and `PruefeSteuernummer` instead of reimplementing them.
- **App size.** About 50 MB universal. It can be thinned to arm64 with `lipo` (EHB 2.4.3 allows this).

## 4. Still open

Nothing at the moment.

## 5. Implementation progress

Branch `elster-ustva`. Each unit is done by one subagent, serially. Status and handoff notes are kept here.

Known facts carried forward:
- Hersteller-ID is `27425`. It is not yet activated: the server returns `601015001`, „HerstellerID ist nicht zugelassen". The full send path to the ELSTER test server works otherwise.
- The shipped ERiC dylibs are `linker-signed`, and `dlopen` hangs in the kernel signature check (`fcntl` in `mapSegments`) until they are re-signed (`codesign --force -s -` or with the team identity). Downloaded copies also carry `com.apple.quarantine`.
- Agents must not send to ELSTER servers. Only local validation (`ERIC_VALIDIERE`) is allowed without the user present.

- [x] U1: M1, vendoring, re-signing, `EricKit` bridge, ERiC version in Settings. Committed as f31c2e8, 1d8bb69, 91880e1, 3390376, 433cdd3. Tests are green, and the mac (ad-hoc and `--signed`) and ios-sim builds succeed.
  - **Resolved:** the user added `disable-library-validation` to the Local entitlements (7672057). The ad-hoc launch then loaded ERiC, and so did the signed sandboxed launch. Original blocker: hardened-runtime library validation rejects the ad-hoc dylibs ("different Team IDs"). Options: (a) build `ENABLE_HARDENED_RUNTIME=NO` for ad-hoc builds, or (b) add `com.apple.security.cs.disable-library-validation` to `BrotBooks-Local.entitlements`. Awaiting the user's choice.
  - **Not yet verified:** the signed sandboxed launch. A container-consent prompt ("me.freas.BrotBooks would like to access data from other apps") must be allowed once by the user. A team-signed probe loads ERiC fine under the hardened runtime.
  - **Handoff:**
    - API: `public actor EricService(ericDirectory:logDirectory:versionFile:)`, `.bundled()`, `version()`, `shutdown()`. Helpers: `withInstance` and `withReturnBuffer`.
    - Adding a function: typedef and field in `CEric.h`, plus a row in `symbols[]` in `CEric.c`.
    - Paths: tests find ERiC via `$ERIC_DIR` or `<repo>/Vendor/ERiC`. The app uses `EricRuntime.shared` in `BrotBooks/VAT/EricRuntime.swift`.
    - Hersteller-ID: Info.plist key `ElsterHerstellerID` (String).
    - `update-strings.py` reformats the whole catalog, so add strings by hand.
    - Package dependencies use `destinationFilters: [macOS]`.
- [x] U2: M2a, committed as f9a7b55, 6490213, 166ff87. 128 tests green; mac and ios-sim builds succeed.
  - **Confirmed treatment:** `vatTreatment` nil means unset, and any stored value counts as confirmed. Suggestions are computed on the fly (`VatTreatmentStatus.of`).
  - **Storage:** `TaxProfile` @Model holds the identity plus `settingsPeriods` JSON. API: `TaxSettings.configuration(for: VatPeriod)`, `VatRateTable.germany`, `FilingDeadlines.germany`.
  - **Deviation from the plan:** the deductible share is `deductibleAmount / gross`, because `deductibleAmount` is a gross EUR amount.
  - **Open:** due dates are not moved off weekends and holidays (§108(3) AO). Duplicate `TaxProfile` rows across devices are not cleaned up. The editor does not show suggestions yet (U4).
- [x] U3: M2b, committed as 5179621, a1b5d9c, 365618f. BrotBooksKit 156 tests and EricKit 13 tests green; mac and ios-sim builds succeed.
  - **Live ERiC validation:** 0 errors for domestic, all treatments, refund, December with Kz39, Sondervorauszahlung (SoVZ) and Dauerfristverlängerung (Df). The only hints are the missing WIdNr, and "period in future" for December.
  - **API:** `UStVAAggregator.aggregate(_:period:configuration:sondervorauszahlung:) -> UStVAResult` (kennzahlen, contributions, zmLines, issues, blocksSending). `UStVAXML.build` / `buildSondervorauszahlung` / `buildDauerfristverlaengerung`. `EricService.validate(xml:datenartVersion:) -> EricValidationResult`.
  - **Vorsteuer share:** `VorsteuerShareRules.default` maps keywords to a policy (meals full, gifts none, phone/car/home office follow the deductible share). It is stored in `TaxProfile.vorsteuerShareRules`.
  - **Bug to fix in U4a:** the Sondervorauszahlung base must be the prior-year Kz83 sum **plus** the prior-year Sondervorauszahlung (form text for Kz38). U2 uses the Kz83 sum only.
  - **To add in U4a:** a WIdNr field on `TaxIdentity`.
- [x] U4a: M3 part 1, committed as 95f262b, 71c43fb, 1bf558b, 780b78f, 53811a7, 71d8121. BrotBooksKit 159 tests and EricKit 22 tests green; builds succeed.
  - **What works:** preview PDF via the C collector `CEricPdfCollect`; Steuernummer conversion and check; Bundesland and Finanzamt lookups; the license sheet with verbatim texts; the ELSTER settings tab (TabView in the macOS Settings scene); W-IdNr (only `DE`+9 digits in the XML); the Sondervorauszahlung base fix.
  - **Handoff:**
    - License gate: `.requiresElsterLicenseAcknowledgment()`.
    - Settings: `ElsterSettingsModel(context:)` (with `update {}`) or `TaxProfile.load(in:)`.
    - `EricService.preview(xml:datenartVersion:) -> EricPreviewResult(.pdf, .validation)`.
    - `EricRuntime.herstellerID`.
    - Sondervorauszahlung: `Sondervorauszahlung.amount(priorYearKz83Total:priorYearSondervorauszahlung:settings:)`.
    - Screenshots: `-snapshotSettings` (DEBUG) needs an unsandboxed build.
  - **Open:**
    - The test Finanzämter 1096/9198 are not in the `HoleFinanzaemter` list.
    - The settings model does not reload on CloudKit changes while the tab is open.
    - The Sondervorauszahlung default can't be computed until filings exist (U5).
- [x] U4b: M3 part 2, committed as 637e947, b28fc63, 48e0d63, f5d4f2b. BrotBooksKit 176 tests and EricKit 22 tests green; builds succeed.
  - **What's built:** the VAT returns screen (schedule from the configuration, the Sondervorauszahlung and Df items, drill-down, warnings, flags, validate, preview with Save…); the review list; the editor's "Suggested:" hint plus Confirm.
  - **Build setting:** `ENABLE_USER_SELECTED_FILES` is now `readwrite`.
  - **Seam for U5:**
    - `VatReturnsModel.filingMark(for:)` returns nil for now.
    - The Send button sits in `VatReturnDetail.header` and is disabled.
    - Kz38/Kz39 use only the override; the computed amount is still missing.
  - **Open:**
    - 2025 shows no returns, because the settings start on 2026-01-01.
    - Past periods all show as overdue until filings are recorded.
- [x] U5: M4, committed as ddc554f, e4bcee6, 5de3611, fd6e161, c8968d0. BrotBooksKit 187 tests and EricKit 41 tests green; builds succeed. Nothing was sent.
  - **What's built:**
    - the certificate import (Keychain, verified PIN, properties)
    - `EricService.send` (EBV-6), with outcomes classified by `EricSendOutcome.classify`
    - the `VatSubmitting` protocol and the stub (`-elsterTransport stub -elsterStubScenario …`)
    - the `VatFiling` model (accepted, rejected, uncertain, filedElsewhere)
    - the send sheet, with a second confirmation for production
    - "Mark as filed elsewhere", single and bulk
    - the Sondervorauszahlung computed from filings
    - the Kz10 rule for corrections
  - **Live send test** (user only): `cd EricKit && ERIC_LIVE_SEND=1 ERIC_TEST_PFX=<scratchpad>/jar/ERiC-44.3.6.0/Darwin-universal/Beispiel/ericdemo-cpp/test-softidnr-pse.pfx swift test --filter EricSendLiveTests`
  - **Open:**
    - Ad-hoc builds and `swift test` fall back to the login keychain. The data-protection keychain in the signed build is not yet verified.
    - Commit e4bcee6 alone doesn't build the app (fixed in fd6e161).
    - 2025 has no settings row.
- [ ] U6: M4b, ZM (ZMDO) XML, sending, UI, consistency check
