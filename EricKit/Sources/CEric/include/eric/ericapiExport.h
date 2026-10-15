/*
 * Copyright © LfSt Bayern, Muenchen, IuK 111, 2006
 */

#ifndef ERIC_API_EXPORT_H_
#define ERIC_API_EXPORT_H_

/**
 * @file
 * @details Attribute für dynamische Bibliotheken
 *
 * Diese Deklarationen sind für Windows-Plattformen relevant.
 */

#include "platform.h"



/**
 * @details Dieses Makro ist nur für die Kompilierung unter Windows von Belang. Auf allen anderen Plattformen ist es leer definiert.
 * 
 * Unter Windows gibt es bei Einbindung der ericapiExport.h in fremden Code an, dass die deklarierten Funktionen zu importieren sind (dllimport).       
 *
 * @see 
 *      - ::ETKAPI_DECL 
 */
#if defined(WINDOWS_OS) && !defined(ERICAPI_DLL)
#define ERICAPI_IMPORT __declspec(dllimport)
#else
#define ERICAPI_IMPORT
#endif

#endif /* ERIC_API_EXPORT_H_ */
