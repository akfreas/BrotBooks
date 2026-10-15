/*
 * Copyright © LfSt Bayern, Muenchen, IuK 111, 2007
 */

#ifndef _ERIC_TYPES_H_
#define _ERIC_TYPES_H_
#include "platform.h"

/**
 * @file
 * @brief Definition von Datenstrukturen und Datentypen
 */

/**
 * @brief Handle auf eine ERiC-Instanz.
 *
 * ERiC-Instanzen werden von der Multithreading-API angelegt,
 * verwendet und wieder freigegeben, siehe ericmtapi.h.
 *
 * Alle API-Funktionen der Multithreading-API nehmen einen Zeiger auf eine
 * ERiC-Instanz entgegen und verrichten ihre Aufgaben auf dieser ERiC-Instanz.
 * Die ERiC-Instanz enthält sämtliche veränderlichen Zustände des ERiC.
 * Dies sind ERiC-Einstellungen, Plugin- und Log-Verzeichnis, Proxyeinstellungen,
 * Zertifikatshandle, Rückgabepuffer, etc.
 *
 * Es können mehrere ERiC-Instanzen parallel angelegt werden. Jede dieser
 * ERiC-Instanzen ist unabhängig von allen anderen ERiC-Instanzen. Verfügen
 * mehrere Threads jeweils über ihre eigene ERiC-Instanz, können sie diese
 * parallel verwenden. Dazu müssen die Threads den API-Funktionen der
 * Multithreading-API ihre jeweils eigene ERiC-Instanz übergeben.
 *
 * ERiC-Instanzen sollten nicht für jede Verarbeitung eines Steuerfalls
 * neu erstellt und konfiguriert werden.
 * Siehe hierzu @typeDokumentation{ERiC-Entwicklerhandbuch.pdf},
 * Kap. "Hinweise zum optimierten Einsatz von ERiC-Instanzen und Plugins"
 *
 * ERiC-Instanzen können zwischen Threads ausgetauscht werden. Eine
 * ERiC-Instanz darf aber nicht in zwei Threads gleichzeitig verwendet werden.
 *
 * @see
 *       - ::EricMtInstanzErzeugen()
 *       - ::EricMtInstanzFreigeben()
 *       - @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kap. "Hinweise zum optimierten Einsatz von ERiC-Instanzen und Plugins" 
 */
typedef struct EricInstanz *EricInstanzHandle;

/**
 * @brief Der Datentyp byteChar wird immer dann verwendet, wenn an diesem Parameter
 *        keine UTF-8 codierte Daten erwartet werden.
 *        Diese Daten werden ungeprüft verwendet.
 *        <b>Zum Beispiel:</b> Pfade
 */
typedef char byteChar;


/**
 * @brief Integer-Typ für Zertifikat-Handles.
 */
typedef uint32_t EricZertifikatHandle;


/**
 * @brief Bearbeitungsflags für die Anwendungsfälle von EricBearbeiteVorgang().
 *
 * Welche Anwendungsfälle von der jeweiligen Datenart unterstützt werden,
 * ist dem @typeDokumentation{ERiC-Entwicklerhandbuch.pdf} zu entnehmen.
 */
typedef enum
{
    /**
     * @brief Der Datensatz soll validiert werden.
     */
    ERIC_VALIDIERE = 1L << 1,

    /**
     * @brief Der Datensatz soll an den ELSTER Annahmeserver versendet werden.
     */
    ERIC_SENDE = 1L << 2,

    /**
     * @brief Der Datensatz soll gedruckt werden.
     */
    ERIC_DRUCKE = 1L << 5,

    /**
     * @brief Der Datensatz soll auf Hinweise hin geprüft werden.
     */
    ERIC_PRUEFE_HINWEISE = 1L << 7,

    /**
     * @brief   Der Datensatz soll validiert werden, ohne dabei die Prüfbedingung
     *          "ERiC_DV_Freigabedatum_pruefen" auszuführen.
     *          Dies ist nur möglich, wenn kein Versand stattfindet.

     *          Das Flag kann nicht zusammen mit ERIC_SENDE oder ERIC_VALIDIERE
     *          angegeben werden.
     *
     * @note    Zur Prüfbedingung "ERiC_DV_Freigabedatum_pruefen" siehe das Dokument
     *          @typeDatenarten{Zusatzinformationen_zur_Plausibilitaetspruefung.pdf} im ERiC-Dokumentationspaket.
     */
    ERIC_VALIDIERE_OHNE_FREIGABEDATUM = 1L << 8,
} eric_bearbeitung_flag_t;


/* Vorwärts-Deklaration. Anwender der ERiC API verwenden ausschließlich
   Zeiger auf Instanzen dieses Datentyps. */
struct EricReturnBufferApi;


/**
 * @brief Handle zur Verwaltung und Verwendung von Rückgabepuffern.
 *
 * Viele ERiC API-Funktionen geben Informationen an ihren Aufrufer zurück,
 * indem sie Daten in sogenannte Rückgabepuffer schreiben.
 * Solche Rückgabepuffer müssen mit ::EricRueckgabepufferErzeugen() angelegt
 * werden. Das bei dieser Erzeugung generierte Puffer-Handle wird vom Aufrufer
 * an die API-Funktion übergeben, die den Puffer leert bevor sie dann in den
 * Puffer schreibt. Ein einmal generiertes Puffer-Handle kann damit auch für
 * mehrere aufeinanderfolgende Aufrufe von ERiC API-Funktionen wiederverwendet
 * werden.
 * Mittels ::EricRueckgabepufferLaenge() kann danach die Anzahl der in den
 * Puffer geschriebenen Bytes ermittelt werden.
 * Mit ::EricRueckgabepufferInhalt() kann der Pufferinhalt abgefragt werden.
 * Jeder Rückgabepuffer muss nach seiner Verwendung mit
 * ::EricRueckgabepufferFreigeben() wieder freigegeben werden.
 *
 * Die Struktur EricReturnBufferApi kapselt die Rückgabepuffer-Implementierung.
 * Anwender der ERiC API verwenden ausschließlich Zeiger auf Instanzen dieser
 * Struktur und müssen daher deren Felder nicht kennen.
 *
 * Rückgabepuffer sind der Singlethreading-API bzw. einer ERiC-Instanz der
 * Multithreading-API fest zugeordnet. Die Funktionen der ERiC API, die einen
 * Rückgabepuffer entgegennehmen, geben den Fehlercode
 * ::ERIC_GLOBAL_PUFFER_UNGLEICHER_INSTANZ zurück, wenn der übergebene
 * Rückgabepuffer: @mAbsatz
 *      - mit der Singlethreading-API erzeugt worden ist und dann mit der
 *        Multithreading-API verwendet wird
 *      - mit der Multithreading-API erzeugt worden ist und dann mit der
 *        Singlethreading-API verwendet wird
 *      - mit einer ERiC-Instanz erzeugt worden ist und dann mit einer
 *        anderen Instanz verwendet wird.
 *
 * @see
 *      - ::EricRueckgabepufferErzeugen()
 *      - ::EricRueckgabepufferLaenge()
 *      - ::EricRueckgabepufferInhalt()
 *      - ::EricRueckgabepufferFreigeben()
 *      - @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kap. "Rückgabepuffer der ERiC Programmierschnittstelle" 
 */
typedef struct EricReturnBufferApi* EricRueckgabepufferHandle;

/**
* @brief Typ der Callback-Funktion zur Übergabe eines PDFs an die Anwendung.
*
* Wenn diese Callback-Funktion im @c eric_druck_parameter_t angegeben wird
* werden PDFs vom ERiC nicht in eine Datei geschrieben, sondern an diese
* Callback-Funktion übergeben.
*
* @param[in] pdfBezeichner
*      @parblock
*              Bezeichner für das PDF.
*              Für ein PDF, das Inhalte aus einem Nutzdatenblock enthält,
*              wird hier das Nutzdatenticket aus dem Nutzdatenblock übergeben,
*              für sonstige PDFs das Wort "Uebertragungsprotokoll".
*
*              Bei der Erstellung mehrerer PDFs ermöglicht das Nutzdatenticket
*              die Zuordnung eines PDFs zu einem bestimmten Nutzdatenblock.
*      @endparblock
* @param[in] pdfDaten Der Inhalt des PDFs.
*                     Zu beachten: es handelt sich um binäre Daten,
*                     die Nullbytes enthalten können.
*
* @param[in] pdfGroesse Die Größe der @c pdfDaten in Bytes.
*
* @param[in] benutzerDaten Der Datenzeiger, der dem ERiC von der Anwendung im
*                          @c eric_druck_parameter_t übergeben wurde.
*
* @return
*      - 0, wenn kein Fehler aufgetreten ist.
*        Ein beliebiger Wert ungleich 0, wenn ein Fehler aufgetreten ist.
*        Der zurückgegebene Wert wird im Fehlerfall in die Datei eric.log
*        protokolliert.
*
* @see
*      - ::EricBearbeiteVorgang()
*      - eric_druck_parameter_t
*
*/
typedef int(STDCALL *EricPdfCallback)(
    const char *pdfBezeichner,
    const uint8_t *pdfDaten,
    uint32_t pdfGroesse,
    void *benutzerDaten);

/**
 * @brief Diese Struktur enthält alle für den Druck notwendigen Informationen.
 *
 * Der Anwendungsentwickler muss diese Struktur allokieren und nach Verwendung
 * wieder freigeben.
 *
 */
typedef struct
{
    /**
    * @brief Version dieser Struktur. Die Version muss derzeit 4 sein.
    *        Bei Änderungen dieser Struktur wird dieser Wert inkrementiert.
    *
    * @note Bei einem Wert ungleich 4 wird #ERIC_GLOBAL_UNGUELTIGE_PARAMETER_VERSION zurückgegeben und eine Fehlermeldung in die Logdatei geschrieben.
    */
    uint32_t version;

    /**
     * @brief Soll ein Vorschau-PDF erstellt werden?
     *
     * @details Anwendungsfälle: @mAbsatz
     * - vorschau = 1: Ein Vorschau-PDF wird erzeugt und als solches gekennzeichnet.
     * - vorschau = 0: Es wird kein Vorschau-PDF erzeugt.
     *
     * @note Bei Werten ungleich 0 oder 1 wird #ERIC_GLOBAL_UNGUELTIGER_PARAMETER zurückgegeben und eine Fehlermeldung in die Logdatei geschrieben.
     *
     */
    uint32_t vorschau;

    /**
     * @brief Soll die PDF-Datei für einen doppelseitigen Ausdruck mit Heftrand zum Lochen vorbereitet werden?
     *
     * @details Anwendungsfälle: @mAbsatz
     * - duplexDruck = 1: Die geraden Seiten werden für einen Heftrand zum Lochen nach links eingerückt. Für Details siehe @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}.
     * - duplexDruck = 0: Es erfolgt keine Einrückung der geraden Seiten. Das erstellte PDF ist nur zum blattweisen Ausdruck der Seiten vorgesehen.
     *
     * @note Bei Werten ungleich 0 oder 1 wird #ERIC_GLOBAL_UNGUELTIGER_PARAMETER zurückgegeben und eine Fehlermeldung in die Logdatei geschrieben.
     */
    uint32_t duplexDruck;

    /**
     * @brief Pfad der erzeugten PDF-Datei.
     *
     * Pfade müssen auf Windows in der für Dateifunktionen benutzten ANSI-Codepage,
     * auf Linux, AIX und Linux Power in der für das Dateisystem benutzten Locale und auf macOS in der
     * "decomposed form" von UTF-8 übergeben werden.
     * Weiterführende Informationen hierzu, sowie zu nicht erlaubten Zeichen in
     * Pfaden und Pfadtrennzeichen, relative Pfadangabe, etc. siehe
     * @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kap. "Übergabe von Pfaden an ERiC API-Funktionen".
     *
     * <b>Windows-Beispiel:</b> \c "c:\\test\\ericprint.pdf" @mLB<a>Soll
     * eine PDF-Datei angelegt werden, ist der \c pdfName zwingend erforderlich.
     *
     * <b>Besonderheiten bei Sammeldaten:</b> @mLB<a>Für
     * Sammeldaten wird dem PDF-Dateinamen vor der Dateiendung das Nutzdatenticket
     * angefügt: @mLB<tt><PDF-Dateiname>_<Nutzdatenticket>.pdf</tt>
     *
     * Optional kann der PDF-Dateiname den Platzhalter "%t" enthalten, der dann
     * durch das Nutzdatenticket ersetzt wird: @mLB<tt>"%t_ericprint.pdf"</tt> --> <tt>"<Nutzdatenticket>_ericprint.pdf"</tt>
     *
     * @note Es ist sicherzustellen, dass alle PDF-Dateien im Dateisystem
     * erstellt bzw. geschrieben werden können. Falls es beim Erstellen der
     * PDF-Dokumente einen Fehler gibt oder falls diese nicht geschrieben
     * werden können, wird die Bearbeitung abgebrochen, eine Log-Ausgabe
     * erstellt, aus der hervorgeht, welcher Steuerfall nicht gedruckt werden
     * konnte, und eine Fehlermeldung an den Aufrufer zurückgeliefert.
     */
    const byteChar* pdfName;

    /**
     * @brief Fußtext der auf dem Ausdruck verwendet werden soll (optional).
     * @details Wenn der übergebene Text länger als #ERIC_MAX_LAENGE_FUSSTEXT
     * Zeichen ist, dann bricht der Druck mit Fehlerkode
     * #ERIC_PRINT_FUSSTEXT_ZU_LANG ab!
     *
     * @note Fachliche Informationen sind im @typeDokumentation{ERiC-Entwicklerhandbuch.pdf} nachzulesen.
     */
    const char* fussText;

    /**
     * @brief Optionale Angabe einer Callback-Funktion
     *        für die Übergabe eines PDFs vom ERiC an die Anwendung.
     *        Wenn hier eine Callback-Funktion angegeben wird, schreibt der ERiC PDFs
     *        nicht in eine Datei, sondern ruft stattdessen die Callback-Funktion auf.
     *        Wenn hier NULL angegeben wird, schreibt der ERiC die PDFs in Dateien.
     */
    EricPdfCallback pdfCallback;

    /**
     * @brief Zeiger auf Benutzerdaten, der bei einem Aufruf des @c pdfCallback
     *        vom ERiC als Parameter unverändert wieder an die Anwendung mitgegeben wird.
     */
    void *pdfCallbackBenutzerdaten;
} eric_druck_parameter_t;


/**
 * @brief Für die Signatur oder Authentifizierung benötigte
 * Informationen.
 *
 * Diese Struktur ist vom Anwender zu allokieren und samt
 * Inhalt auch wieder freizugeben.
 */
typedef struct
{
    /**
    * @brief Version dieser Struktur. Muss derzeit immer 3 sein.
    *        Bei Änderungen dieser Struktur wird dieser Wert inkrementiert.
    *
    * @note Bei einem Wert ungleich 3 wird #ERIC_GLOBAL_UNGUELTIGE_PARAMETER_VERSION zurückgegeben und eine Fehlermeldung in die Logdatei geschrieben.
    *
    */
    uint32_t version;

    /**
     * @brief Verweis auf den KeyStore, siehe EricGetHandleToCertificate().
     */
    EricZertifikatHandle zertifikatHandle;

    /**
     * @brief PIN für den KeyStore.
     */
    const byteChar *pin;
} eric_verschluesselungs_parameter_t;


/**
 * @brief Struktur mit Informationen zur Erzeugung von Zertifikaten mit EricCreateKey().
 *
 * Die Elemente der Struktur beschreiben den Anwender, für den ein Schlüssel erstellt werden soll.
 * Unbenutzte Parameter müssen mit NULL oder Leerstring initialisiert werden.
 *
 * Diese Struktur und ihre Elemente sind vom Anwender zu allokieren und samt Inhalt auch wieder freizugeben.
 * Alle Elemente sind vom Anwender zu initialisieren.
 *
 */
typedef struct
{
    /**
     * @brief Version dieser Struktur. Muss derzeit immer 1 sein.
     *        Bei Änderungen dieser Struktur wird dieser Wert inkrementiert.
     *
     * @note Bei einem Wert ungleich 1 wird #ERIC_GLOBAL_UNGUELTIGE_PARAMETER_VERSION zurückgegeben und eine Fehlermeldung in die Logdatei geschrieben.
     *
     */
    uint32_t version;

    /**
     * @brief Name des Anwenders.
     *
     * Die Angabe des Namens ist obligatorisch.
     * Der Parameter darf nicht mit NULL oder einem Leerstring belegt werden.
     */
    const char* name;

    /**
     * @brief Land (Länderkürzel) des Anwenders. \b Beispiel: "DE".
     *
     * Die Angabe dieses Wertes ist optional.
     */
    const char* land;

    /**
     * @brief Wohnort des Anwenders, inklusive PLZ. \b Beispiel: "D-10179 Berlin".
     *
     * Die Angabe dieses Wertes ist optional.
     */
    const char* ort;

    /**
     * @brief Straßenangabe mit Hausnummer des Anwenders mit Zusätzen, \b Beispiel: "Musterstraße 123 Zugang im Rückgebäude".
     *
     * Die Angabe dieses Wertes ist optional.
     */
    const char* adresse;

    /**
     * @brief E-Mail-Adresse des Anwenders.
     *
     * Die Angabe dieses Wertes ist optional.
     */
    const char* email;

    /**
     * @brief Name der Organisation.
     *
     * Die Angabe dieses Wertes ist optional.
     * Wenn \c organisation und \c abteilung nicht angegeben werden, wird "ELSTER" verwendet.
     */
    const char* organisation;

    /**
     * @brief Name der Abteilung (organizational unit) der Organisation.
     *
     * Die Angabe dieses Wertes ist optional.
     * Wenn \c organisation und \c abteilung nicht angegeben werden, wird "ERiC" verwendet.
     */
    const char* abteilung;

    /**
     * @brief Beschreibung, welche für den Anwender im Zertifikat abgelegt wird.
     *
     * Die Angabe dieses Wertes ist optional.
     */
    const char* beschreibung;
} eric_zertifikat_parameter_t;

    /**
     * ::eric_log_level_t ist ein Parameter für Funktionen vom Typ ::EricLogCallback.
     * Der Loglevel kann zum Filtern für das ERiC Protokoll verwendet werden, siehe
     * @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kap. "Das ERiC Protokoll eric.log".
     */
typedef enum
{
    /// Fehler, der zum Programmabbruch führt.
    ERIC_LOG_ERROR = 4,
    /// Hinweise auf Zustände, die zu Fehlern führen können.
    ERIC_LOG_WARN = 3,
    /// Grobe Informationen über den Programmablauf und Werte.
    ERIC_LOG_INFO = 2,
    /// Feingranulare Informationen über den Programmablauf und Werte.
    ERIC_LOG_DEBUG = 1,
    /// Sehr feingranulare Informationen über den Programmablauf und Werte.
    ERIC_LOG_TRACE = 0
} eric_log_level_t;

/**
 * @brief Typ der Callback-Funktion zum Logging.
 *
 * Wenn registriert, wird diese Callback-Funktion
 * für jeden Log-Eintrag mit folgenden Parametern aufgerufen.
 *
 * @param kategorie Kategorie des Logeintrags. Beinhaltet das Modul, welches
 *                  den Log-Eintrag ausgibt. Zum Beispiel "eric.ctrl2". Kann
 *                  zum Filtern verwendet werden. Alle Log-Nachrichten besitzen
 *                  eine Kategorie. Der Zeiger ist nur innerhalb dieser
 *                  Funktion gültig.
 *
 * @param loglevel Log-Level des Logeintrags. Kann zum Filtern verwendet werden.
 *
 * @param nachricht Enthält die Log-Nachricht als Zeichenkette. Der Zeiger ist
 *                  nur innerhalb dieser Funktion gültig.
 *
 * @param benutzerdaten Der Zeiger, der bei der Registrierung mit
 *                      ::EricRegistriereLogCallback() übergeben worden ist,
 *                      wird in diesem Parameter vom ERiC unverändert
 *                      übergeben.
 *
 * @see
 *      - ::EricRegistriereLogCallback()
 *
 */
typedef void(STDCALL *EricLogCallback)(
    const char* kategorie,
    eric_log_level_t loglevel,
    const char* nachricht,
    void* benutzerdaten);

enum
{
    /**
     * @brief \c id, die beim Einlesen des XMLs von Fortschrittcallbacks
     *        ausgegeben wird.
     */
    ERIC_FORTSCHRITTCALLBACK_ID_EINLESEN    = 10,

    /**
     * @brief \c id, die gemeldet wird, wenn die Daten zum Versand noch
     *        vorbereitet werden müssen.
     */
    ERIC_FORTSCHRITTCALLBACK_ID_VORBEREITEN = 20,

    /**
     * @brief \c id, die beim Validieren der Eingangsdaten von
     *        Fortschrittcallbacks ausgegeben wird.
     */
    ERIC_FORTSCHRITTCALLBACK_ID_VALIDIEREN  = 30,

    /**
     * @brief \c id, die beim Versand der Ausgangsdaten von
     *       Fortschrittcallbacks ausgegeben wird.
     */
    ERIC_FORTSCHRITTCALLBACK_ID_SENDEN      = 40,

    /**
     * @brief \c id, die beim Druck der Eingangsdaten von
     *        Fortschrittcallbacks ausgegeben wird.
     */
    ERIC_FORTSCHRITTCALLBACK_ID_DRUCKEN     = 50
};

/**
 * @brief Typ der Callback-Funktionen, die am ERiC für Fortschrittanzeigen
 *        registriert werden können.
 *
 * @param id Aktueller Verarbeitungsschritt
 *
 * @param pos Aktueller Fortschritt bezogen auf \c max
 *
 * @param max Maximalwert des aktuellen Fortschritts \c pos
 *
 * @param benutzerdaten
 *      @parblock
 *              Der Zeiger, der bei der Registrierung mit
 *              ::EricRegistriereGlobalenFortschrittCallback() oder
 *              ::EricRegistriereFortschrittCallback() übergeben
 *              worden ist, wird in diesem Parameter vom ERiC
 *              unverändert übergeben.
 *      @endparblock
 *
 * Es gilt stets, dass: @mAbsatz
 *           - \c pos größer oder gleich 0 und kleiner oder gleich \c max ist
 *           - \c max ist immer größer als 0
 */
typedef void (STDCALL *EricFortschrittCallback)(
    uint32_t id,
    uint32_t pos,
    uint32_t max,
    void *benutzerdaten);

#endif /*ERIC_TYPES_H_*/
