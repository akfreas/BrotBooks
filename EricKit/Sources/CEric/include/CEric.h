#ifndef CERIC_H_
#define CERIC_H_

// Runtime binding to ERiC. EHB 4.2.3 requires libericapi.dylib to be loaded on macOS with
// dlopen(absolute path, RTLD_GLOBAL) instead of being linked, so this module exposes only the ERiC
// types and constants plus a table of function pointers resolved by CEricLoad(). The ERiC function
// declarations themselves (eric/ericmtapi.h) are deliberately not part of the module: calling them
// directly would need the dylib at link time.
//
// To use another EricMt* function: add a typedef and a field below, then add the symbol to the
// table in CEric.c. The typedef must match the declaration in eric/ericmtapi.h.

#include <stddef.h>
#include <stdint.h>
#include "eric/eric_types.h"
#include "eric/eric_fehlercodes.h"
#include "eric/ericdef.h"

typedef EricInstanzHandle (*CEricMtInstanzErzeugen)(const char *pluginPfad, const char *logPfad);
typedef int (*CEricMtInstanzFreigeben)(EricInstanzHandle instanz);
typedef EricRueckgabepufferHandle (*CEricMtRueckgabepufferErzeugen)(EricInstanzHandle instanz);
typedef int (*CEricMtRueckgabepufferFreigeben)(EricInstanzHandle instanz, EricRueckgabepufferHandle handle);
typedef const char *(*CEricMtRueckgabepufferInhalt)(EricInstanzHandle instanz, EricRueckgabepufferHandle handle);
typedef uint32_t (*CEricMtRueckgabepufferLaenge)(EricInstanzHandle instanz, EricRueckgabepufferHandle handle);
typedef int (*CEricMtVersion)(EricInstanzHandle instanz, EricRueckgabepufferHandle rueckgabeXmlPuffer);
typedef int (*CEricMtBearbeiteVorgang)(EricInstanzHandle instanz, const char *datenpuffer, const char *datenartVersion,
                                       uint32_t bearbeitungsFlags, const eric_druck_parameter_t *druckParameter,
                                       const eric_verschluesselungs_parameter_t *cryptoParameter,
                                       EricRueckgabepufferHandle rueckgabeXmlPuffer,
                                       EricRueckgabepufferHandle serverantwortXmlPuffer);
typedef int (*CEricMtHoleFehlerText)(EricInstanzHandle instanz, int fehlerkode, EricRueckgabepufferHandle rueckgabePuffer);
typedef int (*CEricMtMakeElsterStnr)(EricInstanzHandle instanz, const char *steuernrBescheid, const char *landesnr,
                                     const char *bundesfinanzamtsnr, EricRueckgabepufferHandle steuernrPuffer);
typedef int (*CEricMtPruefeSteuernummer)(EricInstanzHandle instanz, const char *steuernummer);
typedef int (*CEricMtHoleFinanzamtLandNummern)(EricInstanzHandle instanz, EricRueckgabepufferHandle rueckgabeXmlPuffer);
typedef int (*CEricMtHoleFinanzaemter)(EricInstanzHandle instanz, const char *finanzamtLandNummer,
                                       EricRueckgabepufferHandle rueckgabeXmlPuffer);

/// The resolved ERiC functions. Every field is non-NULL after a successful CEricLoad().
typedef struct CEricAPI {
    CEricMtInstanzErzeugen EricMtInstanzErzeugen;
    CEricMtInstanzFreigeben EricMtInstanzFreigeben;
    CEricMtRueckgabepufferErzeugen EricMtRueckgabepufferErzeugen;
    CEricMtRueckgabepufferFreigeben EricMtRueckgabepufferFreigeben;
    CEricMtRueckgabepufferInhalt EricMtRueckgabepufferInhalt;
    CEricMtRueckgabepufferLaenge EricMtRueckgabepufferLaenge;
    CEricMtVersion EricMtVersion;
    CEricMtBearbeiteVorgang EricMtBearbeiteVorgang;
    CEricMtHoleFehlerText EricMtHoleFehlerText;
    CEricMtMakeElsterStnr EricMtMakeElsterStnr;
    CEricMtPruefeSteuernummer EricMtPruefeSteuernummer;
    CEricMtHoleFinanzamtLandNummern EricMtHoleFinanzamtLandNummern;
    CEricMtHoleFinanzaemter EricMtHoleFinanzaemter;
} CEricAPI;

/// Loads libericapi.dylib from `libraryPath` (absolute, file-system representation) with
/// RTLD_NOW | RTLD_GLOBAL and fills `api`. The library stays loaded for the life of the process;
/// loading the same path again is cheap. Thread-safe.
///
/// Returns 0 on success. On failure returns -1 and writes a NUL-terminated message (dlerror or the
/// missing symbol) into `error`.
int CEricLoad(const char *libraryPath, CEricAPI *api, char *error, size_t errorSize);

// MARK: - PDF collection

/// One PDF that ERiC handed to `CEricPdfCollect`. `bytes` is owned by the collector (malloc'd).
typedef struct CEricPdfDocument {
    char *name;
    uint8_t *bytes;
    uint32_t length;
} CEricPdfDocument;

/// Collects the PDFs ERiC produces when `eric_druck_parameter_t.pdfCallback` is `CEricPdfCollect` and
/// `pdfCallbackBenutzerdaten` points to a zero-initialized collector. Free with `CEricPdfCollectorFree`.
typedef struct CEricPdfCollector {
    CEricPdfDocument *documents;
    size_t count;
    size_t capacity;
    /// Set when copying a PDF failed (out of memory); the callback then returned non-zero.
    int failed;
} CEricPdfCollector;

/// An `EricPdfCallback` that copies each PDF into the `CEricPdfCollector` passed as `benutzerDaten`.
/// Returns 0, or -1 when memory runs out (ERiC then aborts and logs the code).
int CEricPdfCollect(const char *pdfBezeichner, const uint8_t *pdfDaten, uint32_t pdfGroesse, void *benutzerDaten);

/// Frees the documents of `collector` and zeroes it.
void CEricPdfCollectorFree(CEricPdfCollector *collector);

#endif /* CERIC_H_ */
