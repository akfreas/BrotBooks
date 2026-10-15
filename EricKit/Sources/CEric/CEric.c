#include "CEric.h"

#include <dlfcn.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
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
        { "EricMtMakeElsterStnr", (void **)&loaded.EricMtMakeElsterStnr },
        { "EricMtPruefeSteuernummer", (void **)&loaded.EricMtPruefeSteuernummer },
        { "EricMtHoleFinanzamtLandNummern", (void **)&loaded.EricMtHoleFinanzamtLandNummern },
        { "EricMtHoleFinanzaemter", (void **)&loaded.EricMtHoleFinanzaemter },
        { "EricMtZertifikatOeffnenAusBytes", (void **)&loaded.EricMtZertifikatOeffnenAusBytes },
        { "EricMtCloseHandleToCertificate", (void **)&loaded.EricMtCloseHandleToCertificate },
        { "EricMtHoleZertifikatEigenschaften", (void **)&loaded.EricMtHoleZertifikatEigenschaften },
        { "EricMtGetErrormessagesFromXMLAnswer", (void **)&loaded.EricMtGetErrormessagesFromXMLAnswer },
        { "EricMtRegistriereFortschrittCallback", (void **)&loaded.EricMtRegistriereFortschrittCallback },
        { "EricMtRegistriereGlobalenFortschrittCallback", (void **)&loaded.EricMtRegistriereGlobalenFortschrittCallback },
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

int CEricPdfCollect(const char *pdfBezeichner, const uint8_t *pdfDaten, uint32_t pdfGroesse, void *benutzerDaten) {
    CEricPdfCollector *collector = (CEricPdfCollector *)benutzerDaten;
    if (collector == NULL || (pdfDaten == NULL && pdfGroesse > 0)) {
        return -1;
    }
    if (collector->count == collector->capacity) {
        size_t capacity = collector->capacity == 0 ? 2 : collector->capacity * 2;
        CEricPdfDocument *grown = realloc(collector->documents, capacity * sizeof(CEricPdfDocument));
        if (grown == NULL) {
            collector->failed = 1;
            return -1;
        }
        collector->documents = grown;
        collector->capacity = capacity;
    }
    uint8_t *bytes = malloc(pdfGroesse > 0 ? pdfGroesse : 1);
    char *name = strdup(pdfBezeichner != NULL ? pdfBezeichner : "");
    if (bytes == NULL || name == NULL) {
        free(bytes);
        free(name);
        collector->failed = 1;
        return -1;
    }
    if (pdfGroesse > 0) {
        memcpy(bytes, pdfDaten, pdfGroesse);
    }
    collector->documents[collector->count++] = (CEricPdfDocument){ name, bytes, pdfGroesse };
    return 0;
}

void CEricPdfCollectorFree(CEricPdfCollector *collector) {
    if (collector == NULL) {
        return;
    }
    for (size_t i = 0; i < collector->count; i++) {
        free(collector->documents[i].name);
        free(collector->documents[i].bytes);
    }
    free(collector->documents);
    *collector = (CEricPdfCollector){ 0 };
}
