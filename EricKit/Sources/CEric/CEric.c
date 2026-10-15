#include "CEric.h"

#include <dlfcn.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;

int CEricLoad(const char *libraryPath, CEricAPI *api, char *error, size_t errorSize) {
    if (libraryPath == NULL || api == NULL) {
        snprintf(error, errorSize, "CEricLoad: NULL argument");
        return -1;
    }
    pthread_mutex_lock(&lock);
    // dlopen reference-counts, so a repeated load returns the same handle. It is never closed:
    // ERiC is meant to stay loaded until the process exits.
    void *handle = dlopen(libraryPath, RTLD_NOW | RTLD_GLOBAL);
    if (handle == NULL) {
        const char *message = dlerror();
        snprintf(error, errorSize, "%s", message ? message : "dlopen failed");
        pthread_mutex_unlock(&lock);
        return -1;
    }

    CEricAPI loaded;
    struct { const char *name; void **slot; } symbols[] = {
        { "EricMtInstanzErzeugen", (void **)&loaded.EricMtInstanzErzeugen },
        { "EricMtInstanzFreigeben", (void **)&loaded.EricMtInstanzFreigeben },
        { "EricMtRueckgabepufferErzeugen", (void **)&loaded.EricMtRueckgabepufferErzeugen },
        { "EricMtRueckgabepufferFreigeben", (void **)&loaded.EricMtRueckgabepufferFreigeben },
        { "EricMtRueckgabepufferInhalt", (void **)&loaded.EricMtRueckgabepufferInhalt },
        { "EricMtRueckgabepufferLaenge", (void **)&loaded.EricMtRueckgabepufferLaenge },
        { "EricMtVersion", (void **)&loaded.EricMtVersion },
        { "EricMtBearbeiteVorgang", (void **)&loaded.EricMtBearbeiteVorgang },
        { "EricMtHoleFehlerText", (void **)&loaded.EricMtHoleFehlerText },
    };
    for (size_t i = 0; i < sizeof(symbols) / sizeof(symbols[0]); i++) {
        void *symbol = dlsym(handle, symbols[i].name);
        if (symbol == NULL) {
            snprintf(error, errorSize, "symbol %s not found in %s", symbols[i].name, libraryPath);
            pthread_mutex_unlock(&lock);
            return -1;
        }
        *symbols[i].slot = symbol;
    }
    *api = loaded;
    pthread_mutex_unlock(&lock);
    return 0;
}
