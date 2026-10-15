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

/// The resolved ERiC functions. Every field is non-NULL after a successful CEricLoad().
typedef struct CEricAPI {
    CEricMtInstanzErzeugen EricMtInstanzErzeugen;
    CEricMtInstanzFreigeben EricMtInstanzFreigeben;
    CEricMtRueckgabepufferErzeugen EricMtRueckgabepufferErzeugen;
    CEricMtRueckgabepufferFreigeben EricMtRueckgabepufferFreigeben;
    CEricMtRueckgabepufferInhalt EricMtRueckgabepufferInhalt;
    CEricMtRueckgabepufferLaenge EricMtRueckgabepufferLaenge;
    CEricMtVersion EricMtVersion;
} CEricAPI;

/// Loads libericapi.dylib from `libraryPath` (absolute, file-system representation) with
/// RTLD_NOW | RTLD_GLOBAL and fills `api`. The library stays loaded for the life of the process;
/// loading the same path again is cheap. Thread-safe.
///
/// Returns 0 on success. On failure returns -1 and writes a NUL-terminated message (dlerror or the
/// missing symbol) into `error`.
int CEricLoad(const char *libraryPath, CEricAPI *api, char *error, size_t errorSize);

#endif /* CERIC_H_ */
