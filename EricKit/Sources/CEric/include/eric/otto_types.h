#ifndef OTTO_TYPES_H_
#define OTTO_TYPES_H_

/**
 * @file
 * @brief Definition von Datenstrukturen und Datentypen
 *
 */

/**
 * @brief Handle auf eine Otto-Instanz
 *
 * Jede Funktion der Otto-API ist direkt oder indirekt an eine Otto-Instanz gebunden.
 * Die Otto-Instanz enthält sämtliche veränderlichen Zustände von Otto.
 *
 * Es können mehrere Instanzen gleichzeitig existieren. Jede der
 * Instanzen ist unabhängig von allen anderen. Verfügen mehrere Threads über
 * jeweils ihre eigene Otto-Instanz, können sie diese Instanzen
 * parallel verwenden.
 *
 * Eine Otto-Instanz kann zwischen Threads ausgetauscht werden. Sie darf aber nicht
 * in zwei Threads gleichzeitig verwendet werden.
 *
 * @see
 *       - OttoInstanzErzeugen()
 *       - OttoInstanzFreigeben()
 */
typedef struct OttoInstanz *OttoInstanzHandle;

/**
 * @brief Handle auf ein Sicherheitstoken zur Authentifizierung des
 *        Daten-Übermittlers oder -Abholers
 */
typedef struct OttoZertifikat *OttoZertifikatHandle;

/** @brief Handle auf einen Otto-Rückgabepuffer
 *
 * Ein Otto-Rückgabepuffer dient zur Übergabe von Daten vom Otto an
 * die Anwendung. Die Anwendung erstellt dazu einen Otto-Rückgabepuffer
 * und übergibt dessen Handle als Parameter einer API-Funktion an den Otto.
 * Der Otto befüllt den Otto-Rückgabepuffer dann mit Daten.
 *
 * @note  Eventuell bereits im Otto-Rückgabepuffer befindliche Daten werden beim
 *        Aufruf von API-Funktionen gelöscht. Ausgenommen davon sind natürlich die
 *        API-Funktionen mit dem Präfix "OttoRueckgabepuffer", die einen Otto-Rückgabepuffer
 *        selbst behandeln.
 *
 * @see
 *        - OttoRueckgabepufferErzeugen()
 *        - OttoRueckgabepufferFreigeben()
 *        - OttoRueckgabepufferInhalt()
 *        - OttoRueckgabepufferGroesse()
 */
typedef struct OttoRueckgabepuffer *OttoRueckgabepufferHandle;

/**
 * @brief Handle auf eine Otto-Prüfsumme
 *
 * Um die Datenintegrität sicherzustellen, ist beim Versand von Daten
 * an den OTTER-Server eine Prüfsumme über die Daten zu übermitteln.
 *
 * Diese Prüfsumme ist schon beim Verbindungsaufbau an die Server zu
 * übermitteln und kann daher nicht während der Datenübertragung
 * implizit gebildet werden, sondern muss vorab explizit berechnet werden.
 */
typedef struct OttoPruefsumme *OttoPruefsummeHandle;

/**
 * @brief Handle auf ein Otto-Versandobjekt
 *
 * Über ein Versandobjekt können Daten blockweise an die OTTER-Server
 * übermittelt werden.
 */
typedef struct OttoVersand *OttoVersandHandle;

/**
 * @brief Handle auf ein Otto-Empfangsobjekt
 *
 * Über ein Empfangsobjekt können Daten blockweise vom OTTER-Server
 * heruntergeladen werden.
 */
typedef struct OttoEmpfang *OttoEmpfangHandle;

/**
 * @brief Aufzählung der Log-Ebenen von Otto
 *
 * Die Log-Meldungen von Otto sind in Ebenen angeordnet:
 * von der höchsten Ebene mit den wichtigsten Fehlermeldungen
 * bis hin zu niedrigsten Ebene mit einfachen Meldungen, die
 * nur bei der Suche nach Fehlerursachen interessant sind.
 *
 * Standardmäßig werden nur Meldungen der beiden höchsten Ebenen
 * (Fehler und Warnungen) protokolliert.
 *
 * Sollen auch Meldungen der niedrigeren Ebenen protokolliert werden,
 * so kann über die Funktion OttoInstanzErzeugen() ein Callback vom
 * Typ ::OttoLogCallback registriert werden, in dem die Meldungen
 * nach der Ebene gefiltert werden können.
 *
 * @see
 *    + OttoInstanzErzeugen()
 */
typedef enum {
    /// Fehler, die zum Abbruch der gewünschten Aktion führen.
    OTTOLOG_FEHLERMELDUNGEN = 4,

    /// Hinweise auf Zustände, die zu Fehlern führen können.
    OTTOLOG_WARNUNGEN = 3,

    /// Grobe Informationen über den Programmablauf und Werte.
    OTTOLOG_INFORMATIONEN = 2,

    /// Feingranulare Informationen über den Programmablauf und Werte.
    OTTOLOG_DEBUGMELDUNGEN = 1
} OttoLogEbene;

/**
 * @brief  Funktionstyp für einen Log-Callback, den eine Anwendung beim Erzeugen
 *         einer Otto-Instanz angeben kann.
 *
 * @return
 *       - 0 wenn die Log-Meldung erfolgreich entgegengenommen werden konnte,
 *         ungleich 0 im Fehlerfall.
 *         Momentan wird der Rückgabewert vom Otto jedoch ignoriert.
 */
typedef int (*OttoLogCallback)( const char *instanzId,
                                const char *logZeitpunkt,
                                OttoLogEbene logEbene,
                                const char *logNachricht,
                                void *benutzerdaten );

/**
 * @brief Der Datentyp byteChar wird immer dann verwendet, wenn an diesem Parameter
 *        keine UTF-8 codierte Daten erwartet werden. Diese Daten werden ungeprüft verwendet.
 */
typedef char byteChar;

/**
 * @brief  Diese Struktur enthält alle Informationen, die Otto benötigt,
 *         um die Verbindung zum OTTER-Server oder dem ELSTER-eID-Server über
 *         einen Proxy aufzubauen.
 */
typedef struct {

    /**
     * @brief Die Version der Struktur.
     *
     * Hier ist aktuell fest der Wert 1 zu setzen.
     */
    int version; // Aktuell immer auf 1 zu setzen

    /**
     * @brief Die URL des Proxies einschließlich Port.
     *
     * IPv6-Adressen sind in eckigen Klammern anzugeben.
     * Otto unterstützt folgende Protokolle:
     *   - http
     *   - socks4
     *   - socks5
     *   .
     * \b Beispiele:
     *   - mein.pro.xy:1234
     *   - http://203.0.113.0:1234
     *   - socks4://mein.pro.xy:1234
     *   - socks5://[2001:0DB8:AC10:FE01::]:1234
     *   .
     * Dieses Element darf nicht NULL sein.
     */
    const byteChar *url;

    /**
     * @brief Der Benutzername für eine Proxy-Authentifizierung.
     *
     * Dieses Element darf NULL sein.
     */
    const byteChar *benutzerName;

    /**
     * @brief Das Passwort für eine Proxy-Authentifizierung.
     *
     * Dieses Element darf NULL sein.
     */
    const byteChar *benutzerPasswort;

    /**
     * @brief Die Authentifizierungsmethode, mit der der Proxy arbeitet.
     *
     * Folgende Methoden werden unterstützt:
     *   - "Any"
     *   - "Basic"
     *   - "Digest"
     *   - "DigestIE"
     *   - "NTLM"
     *   - "SPNEGO"
     *   .
     * Mehrere Werte sind durch Kommas getrennt anzugeben.
     * Die Groß-, Kleinschreibung der Werte wird ignoriert.
     * Dieses Element darf NULL sein, wenn der Proxy keine
     * Authentifizierung erfordert.
     */
    const char *authentifizierungsMethode;
} OttoProxyKonfiguration;

#endif /* OTTO_TYPES_H_ */
