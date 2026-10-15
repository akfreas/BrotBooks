#ifndef OTTO_H_
#define OTTO_H_

#include "otto_statuscode.h"
#include "otto_types.h"

#include <stdint.h>


// Definiere Windows-x86 cdecl-Aufrufkonvention
#ifndef C_DECL
#  if defined(_WIN32) && !defined(_WIN64)
#    define C_DECL __cdecl
#  else
#    define C_DECL
#  endif
#endif


/**
 * @file
* @brief Deklaration der Otto-Funktionen
 *
 */

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Erstellt und initialisiert eine neue Otto-Instanz.
 *
 * Otto-Instanzen sind nicht an ihre Ersteller-Threads gebunden.
 * Sie dürfen zwar _nicht gleichzeitig_ in mehreren
 * Threads verwendet werden, aber sie dürfen wechselnd von verschiedenen
 * Threads verwendet werden. Das heißt insbesondere, dass sie von neuen
 * Threads wiederverwendet werden können.
 *
 * Otto-Instanzen sind in dem Sinne threadsicher, dass verschiedene
 * Otto-Instanzen zeitgleich in verschiedenen Threads verwendet werden können.
 * Jedoch darf ein- und dieselbe Otto-Instanz nicht zeitgleich in mehreren
 * Threads verwendet werden.
 *
 * @param[in]  logPfad
 *             Optionaler Pfad zur Log-Datei otto.log. Ist der
 *             Wert gleich @c NULL, wird das betriebssystemspezifische
 *             Verzeichnis für temporäre Dateien verwendet.
 *
 * @param[in]  logCallback
 *             Callback-Funktion, die gegebenenfalls von Otto bei der
 *             Protokollierung von Meldungen aufgerufen wird.
 *             Siehe ::OttoLogCallback
 *             Der Parameter darf @c NULL sein.
 *
 * @param[in]  logCallbackBenutzerdaten
 *      @parblock
 *              Beliebiger Zeiger auf Daten, den Otto beim Aufruf eines
 *              @p logCallback an den Callback weiterreicht.
 *
 *              Über diesen Weg kann sich eine Anwendung eigene Daten an
 *              ihre Log-Callback-Funktion übergeben lassen.
 *              Der Parameter darf @c NULL sein.
 *      @endparblock
 * @param[out] instanz
 *             Handle der erzeugten Otto-Instanz
 *
 * @note
 *     @parblock
 *             Kann kein otto.log angelegt werden, wird eine entsprechende
 *             Fehlermeldung auf die Konsole (stderr) geschrieben und an den
 *             Windows-Ereignisdienst bzw. den syslogd-Dienst (Linux, AIX, macOS)
 *             geschickt.
 *
 *             Für Linux, AIX und macOS ist zu beachten, dass der syslogd-Dienst
 *             gegebenenfalls erst noch zu aktivieren und für die Protokollierung
 *             von Meldungen der Facility "User" zu konfigurieren ist.
 *
 *             Suchkriterien für Otto-Meldungen in der Windows-Ereignisansicht
 *             sind "ERiC (Elster Rich Client)" als Quelle und "Anwendung"
 *             als Protokoll.
 *
 *             Suchkriterien für ERiC-Meldungen in den Systemlogdateien
 *             unter Linux, AIX und macOS sind die Facility "User" und
 *             der Ident "ERiC (Elster Rich Client)".
 *     @endparblock
 *
 * @return
 *             - siehe otto_statuscode.h
 *
 * @see
 *             - OttoInstanzFreigeben()
 *             - OttoLogCallback
 */
OttoStatusCode C_DECL OttoInstanzErzeugen(const byteChar *logPfad,
                                          OttoLogCallback logCallback,
                                          void *logCallbackBenutzerdaten,
                                          OttoInstanzHandle *instanz);

/**
 * @brief      Gibt eine Otto-Instanz frei.
 *
 * Die freigegebene Otto-Instanz sowie alle eventuell noch daran
 * gebundenen Objekte dürfen nach der Freigabe nicht mehr verwendet
 * werden.
 *
 * @param[in]  instanz
 *             Handle der Otto-Instanz, die freigegeben werden soll.
 *
 * @return
 *             - siehe otto_statuscode.h
 *
 * @see
 *             - OttoInstanzErzeugen()
 */
OttoStatusCode C_DECL OttoInstanzFreigeben(OttoInstanzHandle instanz);

/**
 * @brief      Erstellt ein Otto-Zertifikatsobjekt für ein Sicherheitstoken.
 *
 * Das Zertifikatsobjekt ist an die Otto-Instanz gebunden, für die es erzeugt
 * wurde, und darf nicht zusammen mit einer anderen Otto-Instanz oder mit
 * Objekten anderer Otto-Instanzen verwendet werden.
 * Soll ein Sicherheitstoken von mehreren Otto-Instanzen verwendet werden, so
 * sind hierfür mehrere Zertifikatsobjekte zu erstellen: für jede Instanz eines.
 *
 * @param[in]  instanz
 *             Handle der Otto-Instanz, die das Zertifikatsobjekt verwenden soll.
 *
 * @param[in]  zertifikatsPfad
 *      @parblock
 *              Pfad zum Sicherheitstoken, folgende Angaben sind möglich: @mAbsatz
 *              1. Clientseitig erzeugtes Zertifikat: @mLB<a>Pfad
 *                Verzeichnis, in dem sich die Zertifikats-Datei (.cer)
 *                und die Datei mit dem privaten Schlüssel (.p12) befinden.
 *                Diese Sicherheitstokens wurden mit EricMtCreateKey() bzw. EricCreateKey() erzeugt.
 *                Der Pfad zum Verzeichnis ist bei clientseitig erzeugten
 *                Zertifikaten relativ zum aktuellen Arbeitsverzeichnis oder absolut
 *                anzugeben.
 *              2. Software-Portalzertifikat: @mLB<a>Pfad
 *                zur Software-Zertifikatsdatei (i.d.R. mit der Endung .pfx).
 *                Der Pfad zur Datei ist bei Software-Zertifikaten relativ zum
 *                aktuellen Arbeitsverzeichnis oder absolut anzugeben.
 *              3. Sicherheitsstick: @mLB<a>Pfad
 *                zur Treiberdatei, siehe (*). Bitte beachten, dass der Treiber
 *                betriebssystemabhängig sein kann. Weitere Informationen in der
 *                Anleitung zum Sicherheitsstick oder unter
 *                \linkExt{https://www.sicherheitsstick.de,https://www.sicherheitsstick.de}.
 *              4. Signaturkarte: (**) @mLB<a>Pfad
 *                zur Treiberdatei, welcher einen Zugriff auf die
 *                Signaturkarte ermöglicht, siehe (*). Weitere Informationen in
 *                der Anleitung zur Signaturkarte.
 *              5. Elektronischer Personalausweis (nPA) oder Aufenthaltstitel (eAT): @mLB<a>Die
 *                URL des eID-Clients wie zum Beispiel der AusweisApp 2.
 *                In den meisten Fällen lautet diese URL: http://127.0.0.1:24727/eID-Client
 *                Optional kann auf die folgende Weise noch ein Testmerker angehängt werden:
 *                http://127.0.0.1:24727/eID-Client?testmerker=520000000. @mLB<a>Zu
 *                den verfügbaren Testmerkern siehe @typeDokumentation{ERiC-Entwicklerhandbuch.pdf},
 *                Kap. "Testunterstützung bei der ERiC-Anbindung".
 *
 *                <B>Wichtig:</B>
 *                Das Ad-hoc-Zertifikat, das in diesem Fall für den elektronischen
 *                Personalausweis erzeugt wird, ist nur 24 Stunden gültig.
 *      @endparblock
 *             (*) Wird der Dateipfad eines Treibers angegeben, ist der Suchmechanismus zu
 *             beachten, mit dem das jeweilige Betriebssystem dynamische Bibliotheken lädt.
 *             Weitere Informationen sind der Systemdokumentation zu den Betriebssystemfunktionen
 *             <tt>LoadLibrary()</tt> (Windows) bzw. <tt>dlopen()</tt> (Linux, AIX und macOS) zu entnehmen.
 *
 *             (**) Bei Signaturkarten erfolgt eine PIN-Abfrage nicht beim Aufruf von
 *             OttoZertifikatOeffnen(), sondern beim Aufruf von OttoPruefsummeSignieren(),
 *             OttoEmpfangBeginnen() und OttoEmpfangBeginnenAbholzertifikat().
 *
 *             Pfade müssen auf Windows in der für Datei-Funktionen benutzten ANSI-Codepage,
 *             auf Linux, AIX und Linux Power in der für das Dateisystem benutzten Locale
 *             und auf macOS in der "decomposed form" von UTF-8 übergeben werden.
 *             Bitte weitere Betriebssystemspezifika bzgl. nicht erlaubter Zeichen in
 *             Pfaden und Pfadtrennzeichen beachten.
 *
 *             Für Details zu Pfaden im ERiC siehe @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kapitel
 *             "Übergabe von Pfaden an ERiC API-Funktionen".
 *
 * @param[in]  zertifikatsPasswort
 *             Das Passwort oder die PIN des Sicherheitstokens.
 *             Bei Tokens, bei denen das Passwort oder die PIN nicht von der Anwendung
 *             übergeben, sondern separat über einen Treiber (z. B. von einem Kartenlesegerät)
 *             abgefragt wird, ist hier NULL zu übergeben.
 *
 * @param[out] zertifikat
 *             Handle auf das erstellte Zertifikatsobjekt
 *
 * @return
 *             - siehe otto_statuscode.h
 *
 * @see
 *             - OttoZertifikatSchliessen()
 *             - OttoZertifikatOeffnenAusBytes()
 */
OttoStatusCode C_DECL OttoZertifikatOeffnen(OttoInstanzHandle instanz,
                                            const byteChar *zertifikatsPfad,
                                            const byteChar *zertifikatsPasswort,
                                            OttoZertifikatHandle *zertifikat);

/**
 * @brief      Erstellt ein Otto-Zertifikatsobjekt für ein PKCS#12-Sicherheitstoken,
 *             das im Hauptspeicher übergeben wird.
 *
 * Das Zertifikatsobjekt ist an die Otto-Instanz gebunden, für die es erzeugt
 * wurde, und darf nicht zusammen mit einer anderen Otto-Instanz oder mit
 * Objekten anderer Otto-Instanzen verwendet werden.
 * Soll ein PKCS#12-Container von mehreren Otto-Instanzen verwendet werden, so
 * sind hierfür mehrere Zertifikatsobjekte zu erstellen: für jede Instanz eines.
 *
 * @param[in]  instanz
 *             Handle der Otto-Instanz, die das Zertifikatsobjekt verwenden soll.
 *
 * @param[in]  pkcs12Container
 *             Adresse des PKCS#12-Containers im Hauptspeicher.
 *             Es werden nur passwortgeschützte PKCS#12-Container akzeptiert.
 *
 * @param[in]  containerGroesse
 *             Größe des PKCS#12-Containers in Bytes
 *
 * @param[in]  zertifikatsPasswort
 *             Das Passwort oder die PIN des PKCS#12-Containers.
 *             Dieser Parameter darf nicht NULL sein.
 *
 * @param[out] zertifikat
 *             Handle auf das erstellte Zertifikatsobjekt
 *
 * @return
 *             - siehe otto_statuscode.h
 *
 * @see
 *             - OttoZertifikatSchliessen()
 *             - OttoZertifikatOeffnen()
 */
OttoStatusCode C_DECL OttoZertifikatOeffnenAusBytes(OttoInstanzHandle instanz,
                                                    const byteChar *pkcs12Container,
                                                    uint32_t containerGroesse,
                                                    const byteChar *zertifikatsPasswort,
                                                    OttoZertifikatHandle *zertifikat);

/**
 * @brief      Schließt das Otto-Zertifikatsobjekt zu einem Sicherheitstoken.
 * Anschließend darf das Zertifikatsobjekt nicht mehr verwendet werden.
 *
 * @param[in]  zertifikat
 *             Handle auf das Zertifikatsobjekt, das geschlossen werden soll.
 *
 * @return
 *             - siehe otto_statuscode.h
 *
 * @see
 *             - OttoZertifikatOeffnen()
 */
OttoStatusCode C_DECL OttoZertifikatSchliessen(OttoZertifikatHandle zertifikat);

/**
 * @brief      Erzeugt einen Rückgabepuffer und gibt ein Handle darauf zurück.
 *
 * Die von dieser Funktion erzeugten Rückgabepuffer werden verwendet, um
 * die Rückgabedaten von Otto-Funktionen (z. B. OttoEmpfangFortsetzen()
 * oder OttoVersandBeenden()) aufzunehmen.
 * Dazu wird das Rückgabepuffer-Handle für den Schreibvorgang
 * an die ausgebende Funktion übergeben.
 *
 * Zum Auslesen des von den API-Funktionen beschriebenen Puffers wird das
 * Rückgabepuffer-Handle an OttoRueckgabepufferInhalt() übergeben.
 * Ein einmal erzeugtes Rückgabepuffer-Handle kann für weitere nachfolgende
 * Aufrufe von Otto API-Funktionen wiederverwendet werden. Bei einer
 * Wiederverwendung eines Handles werden frühere Inhalte überschrieben.
 * Nach letztmaliger Verwendung muss jeder Rückgabepuffer mit
 * OttoRueckgabepufferFreigeben() freigegeben werden.
 *
 * Der Rückgabepuffer ist an die Otto-Instanz gebunden, für die er erzeugt
 * wurde und kann nicht zusammen mit einer anderen Otto-Instanz oder mit
 * Objekten anderen Otto-Instanzen verwendet werden.
 *
 * @param[in]  instanz
 *             Handle der Otto-Instanz, auf der diese Funktion ausgeführt werden soll.
 *
 * @param[out] rueckgabepuffer
 *             Zeiger auf das Handle des erzeugten Rückgabepuffers
 *
 * @return
 *             - siehe otto_statuscode.h
 *
 * @see
 *             - OttoRueckgabepufferGroesse()
 *             - OttoRueckgabepufferInhalt()
 *             - OttoRueckgabepufferFreigeben()
 */
OttoStatusCode C_DECL OttoRueckgabepufferErzeugen(OttoInstanzHandle instanz,
                                                  OttoRueckgabepufferHandle *rueckgabepuffer);

/**
 * @brief      Gibt die Anzahl der im Rückgabepuffer
 *             enthaltenen Bytes zurück. Das abschließende Null-Byte wird
 *             nicht mitgezählt.
 *
 * @param[in]  rueckgabepuffer
 *             Das Handle des Rückgabepuffers
 *
 * @return
 *             - Anzahl der im Rückgabepuffer enthaltenen Bytes,
 *                 wenn ein gültiges Handle übergeben wird.
 *             - 0 sonst
 *
 * @see
 *             - OttoRueckgabepufferInhalt()
 *             - OttoRueckgabepufferErzeugen()
 *             - OttoRueckgabepufferFreigeben()
 */
uint64_t C_DECL OttoRueckgabepufferGroesse(OttoRueckgabepufferHandle rueckgabepuffer);

/**
 * @brief      Gibt den Inhalt eines Rückgabepuffers zurück.
 *
 * Der zurückgegebene Zeiger verweist auf ein Byte-Array, das alle in
 * den Rückgabepuffer geschriebenen Bytes enthält.
 * Dieses Array existiert so lange im Speicher, bis der Rückgabepuffer
 * entweder (bei einer Wiederverwendung des Handles) erneut beschrieben
 * oder der Puffer explizit freigegeben wird.
 * Der Array wird immer von einem Null-Byte abgeschlossen. Wenn der
 * Rückgabepuffer keine weiteren Null-Bytes enthält, kann folglich der
 * Rückgabepufferinhalt bequem als null-terminierte Zeichenkette
 * interpretiert werden.
 *
 * @param[in]  rueckgabepuffer
 *             Das Handle des Rückgabepuffers, dessen Inhalt zurückgegeben werden soll.
 *
 * @return
 *             - Zeiger auf den Rückgabepufferinhalt, wenn ein gültiges Handle übergeben wird.
 *             - NULL sonst
 *
 * @see
 *             - OttoRueckgabepufferGroesse()
 *             - OttoRueckgabepufferErzeugen()
 *             - OttoRueckgabepufferFreigeben()
 */
const byteChar* C_DECL OttoRueckgabepufferInhalt(OttoRueckgabepufferHandle rueckgabepuffer);

/**
 * @brief      Gibt einen Rückgabepuffer frei.
 *
 * Das Handle des Rückgabepuffers darf danach nicht weiter verwendet werden.
 * Es wird daher empfohlen, Handle-Variablen nach der Freigabe explizit auf
 * @c NULL zu setzen.
 *
 * @param[in]  rueckgabepuffer
 *             Handle auf den Rückgabepuffer, der freigegeben werden soll.
 *             Dieser Rückgabepuffer darf nicht bereits freigegeben worden sein.
 *
 * @return
 *             - siehe otto_statuscode.h
 *
 * @see
 *            - OttoRueckgabepufferGroesse()
 *            - OttoRueckgabepufferInhalt()
 *            - OttoRueckgabepufferErzeugen()
 */
OttoStatusCode C_DECL OttoRueckgabepufferFreigeben(OttoRueckgabepufferHandle rueckgabepuffer);

/**
 * @brief      Erzeugt ein Objekt zur Berechnung einer Datenprüfsumme, die Otto
 * zu Beginn einer Übermittlung an den OTTER-Server senden muss.
 *
 * Das Prüfsummenobjekt ist an die Otto-Instanz gebunden, für die es erzeugt
 * wurde und darf nicht zusammen mit einer anderen Otto-Instanz oder mit
 * Objekten anderen Otto-Instanzen verwendet werden.
 *
 * @param[in]  instanz
 *             Handle der Otto-Instanz, für die das Prüfsummenobjekt erzeugt werden soll.
 *
 * @param[out] pruefsumme
 *             Handle des erzeugten Prüfsummenobjekts
 *
 * @return
 *             - siehe otto_statuscode.h
 *
 * @see
 *             - OttoPruefsummeAktualisieren()
 *             - OttoPruefsummeSignieren()
 *             - OttoPruefsummeFreigeben()
 */
OttoStatusCode C_DECL OttoPruefsummeErzeugen(OttoInstanzHandle instanz, OttoPruefsummeHandle *pruefsumme);

/**
 * @brief      Aktualisiert die Prüfsumme über Daten.
 *             Eine Prüfsumme, die bereits signiert wurde, kann nicht mehr
 *             aktualisiert werden.
 *
 * @param[in,out] pruefsumme
 *                Handle der Prüfsumme, die aktualisiert werden soll.
 *
 * @param[in]  datenBlock
 *             Zeiger auf die Daten, über die die Prüfsumme aktualisiert werden soll.
 *
 * @param[in]  datenBlockGroesse
 *             Größe der Daten, über die die Prüfsumme aktualisiert werden soll, in Bytes.
 *
 * @return
 *             - ::OTTO_OK wenn die Prüfsumme erfolgreich aktualisiert werden konnte
 *             - ::OTTO_PRUEFSUMME_FINALISIERT wenn die Prüfsumme bereits signiert wurde
 *             - weitere, siehe otto_statuscode.h
 *
 * @see
 *             - OttoPruefsummeErzeugen()
 *             - OttoPruefsummeSignieren()
 *             - OttoPruefsummeFreigeben()
 *
 */
OttoStatusCode C_DECL OttoPruefsummeAktualisieren(OttoPruefsummeHandle pruefsumme,
                                                  const byteChar *datenBlock,
                                                  uint64_t datenBlockGroesse);

/**
 * @brief      Erstellt eine Signatur über eine Prüfsumme.
 *
 * Die Signierung der Prüfsumme ist nur dann möglich,
 * wenn diese über die Mindestdatenmenge für eine Übermittlung
 * an den OTTER-Server berechnet wurde. (20 MiB)
 * Eine Prüfsumme kann nur einmalig signiert werden.
 * Danach muss das Prüfsummenobjekt freigegeben werden.
 *
 * @param[in]  pruefsumme
 *             Handle der Prüfsumme, die signiert werden soll.
 *
 * @param[in]  zertifikat
 *             Handle des Sicherheitstoken, mit dem die Prüfsumme signiert werden soll.
 *
 * @param[out] rueckgabepuffer
 *             Handle des Rückgabepuffers, in den die signierte Prüfsumme
 *             geschrieben werden soll.
 *             Die signierte Prüfsumme wird als base64-codierte Zeichenfolge übergeben.
 *
 * @return
 *             - ::OTTO_OK wenn die Prüfsumme signiert werden konnte
 *             - ::OTTO_PRUEFSUMME_FINALISIERT wenn die Prüfsumme bereits signiert wurde
 *             - ::OTTO_VERSAND_GERINGE_DATENMENGE wenn die Prüfsumme über weniger Daten gebildet wurde als für den Versand an den OTTER-Server erforderlich sind
 *             - ::OTTO_ESIGNER_NICHT_GELADEN wenn die Signaturkomponente eSigner nicht geladen werden konnte
 *             - ::OTTO_ESIGNER_VERALTET wenn die vorliegende Version der Signaturkomponente eSigner zu alt ist
 *             - ::OTTO_ESIGNER_INKOMPATIBEL wenn die vorliegende Signaturkomponente eSigner zur Otto-Bibliothek nicht kompatibel ist
 *             - Fehler der Signaturkomponente eSigner aus dem Statuscodebereich ab ::OTTO_ESIGNER_BUSY = 610405801
 *             - weitere, siehe otto_statuscode.h
 *
 * @see
 *             - OttoPruefsummeErzeugen()
 *             - OttoPruefsummeAktualisieren()
 *             - OttoPruefsummeFreigeben()
 *
 */
OttoStatusCode C_DECL OttoPruefsummeSignieren(OttoPruefsummeHandle pruefsumme,
                                              OttoZertifikatHandle zertifikat,
                                              OttoRueckgabepufferHandle rueckgabepuffer);

/**
 * @brief      Gibt ein Prüfsummenobjekt frei.
 *
 * Das Prüfsummenobjekt darf danach nicht wieder verwendet werden.
 *
 * @param[in]  pruefsumme
 *             Handle des Prüfsummenobjekts, das freigegeben werden soll.
 *
 * @return
 *             - siehe otto_statuscode.h
 *
 * @see
 *             - OttoPruefsummeErzeugen()
 *             - OttoPruefsummeAktualisieren()
 *             - OttoPruefsummeSignieren()
 */
OttoStatusCode C_DECL OttoPruefsummeFreigeben(OttoPruefsummeHandle pruefsumme);

/**
 * @brief      Initialisiert einen Datenversand an den OTTER-Server.
 *
 * Das zurückgegebene Handle des Versandobjekts wird der Funktion
 * OttoVersandFortsetzen() übergeben, um Daten blockweise hochzuladen.
 * Sind alle Daten versendet, ist OttoVersandAbschliessen() aufzurufen, womit
 * der Versand abgeschlossen wird.
 * Zum Freigeben des Versandobjekts ist OttoVersandBeenden() aufzurufen.
 *
 * Bevor der Versand begonnen werden kann, muss eine Prüfsumme über alle zu
 * versendenen Daten gebildet (siehe OttoPruefsummeErzeugen()) und mit
 * OttoPruefsummeSignieren() signiert werden.
 *
 * @note       Wurde Otto vor dem Aufruf dieser Funktion für einen Proxy mit OttoProxyKonfigurationSetzen()
 *             konfiguriert, wird der Versand über den Proxy durchgeführt. Die Proxy-Konfiguration wird
 *             intern an dem Versandobjekt gespeichert und spätere Aufrufe von OttoProxyKonfigurationSetzen()
 *             haben keinen Einfluss auf den bereits begonnenen Versand.
 *
 * @param[in]  instanz
 *             Handle der Otto-Instanz, auf der diese Funktion ausgeführt werden soll.
 *
 * @param[in]  signiertePruefsumme
 *      @parblock
 *              Signierte Prüfsumme über die Gesamtheit der Daten, die in diesem Versand
 *              versendet werden sollen.
 *
 *              Die signierte Prüfsumme wird als base64-codierte, nullterminierte Zeichenfolge erwartet,
 *              wie sie von OttoPruefsummeSignieren() zurückgeliefert wird.
 *      @endparblock
 * @param[in]  herstellerId
 *             Hersteller-ID des Softwareproduktes
 *
 * @param[out] versand
 *             Handle auf das Versandobjekt. Im Fehlerfall wird kein Versandobjekt erzeugt.
 *
 * @return
 *             - siehe otto_statuscode.h
 *
 * @see
 *             - OttoVersandFortsetzen()
 *             - OttoVersandAbschliessen()
 *             - OttoVersandBeenden()
 *             - OttoPruefsummeSignieren()
 *             - OttoProxyKonfigurationSetzen()
 */
OttoStatusCode C_DECL OttoVersandBeginnen(OttoInstanzHandle instanz,
                                          const byteChar *signiertePruefsumme,
                                          const byteChar *herstellerId,
                                          OttoVersandHandle *versand);

/**
 * @brief      Versendet einen Datenblock an den OTTER-Server.
 *
 * Otto liest den übergebenen Datenblock ein und versendet ihn an den OTTER-Server.
 * Wenn @c OTTO_OK zurückgegeben wird, kann diese Funktion erneut mit einem weiteren
 * Datenblock aufgerufen werden. Dies ist zu wiederholen, bis Otto alle zu diesem Versand
 * gehörigen Daten erhalten hat. Falls nicht @c OTTO_OK zurückgegeben wird, ist der
 * Versand fehlgeschlagen.
 *
 * Ist das Ende der Daten erreicht, muss OttoVersandAbschliessen() aufgerufen werden.
 *
 * @param[in]  versand
 *             Ein mit OttoVersandBeginnen() erzeugtes Handle
 *
 * @param[in]  datenBlock
 *             Zeiger auf die zu versendenen Daten. Falls @c NULL wird der Aufruf ignoriert.
 *
 * @param[in]  datenBlockGroesse
 *             Größe des Arrays @p datenBlock in Bytes. Falls 0 wird der Aufruf ignoriert.
 *
 * @return
 *             - ::OTTO_OK im Erfolgsfall
 *             - ::OTTO_TRANSFER_UNAUTHORIZED
 *             - ::OTTO_TRANSFER_CONNECTSERVER
 *             - ::OTTO_VERSAND_ABGESCHLOSSEN falls OttoVersandAbschliessen() bereits aufgerufen wurde
 *             - weitere, siehe otto_statuscode.h
 *
 * @see
 *             - OttoVersandAbschliessen()
 */
OttoStatusCode C_DECL OttoVersandFortsetzen(OttoVersandHandle versand,
                                            const byteChar *datenBlock,
                                            uint64_t datenBlockGroesse);

/**
 * @brief      Schließt einen Versand ab und gibt die Objekt-ID zurück
 *
 * Mit dieser Funktion wird das Ende der Daten gekennzeichnet und der Datenversand abgeschlossen.
 *
 * Im Erfolgsfall wird die vom OTTER-Server vergebene Objekt-ID zurückgegeben, über die die
 * versendeten Daten bei OTTER referenziert werden.
 *
 * @param[in]  versand
 *             Ein mit OttoVersandBeginnen() erzeugtes Handle
 *
 * @param[out] objektId
 *             Handle des Rückgabepuffers, in den die Objekt-ID geschrieben werden soll.
 *
 * @return
 *             - ::OTTO_OK im Erfolgsfall
 *             - ::OTTO_TRANSFER_UNAUTHORIZED
 *             - ::OTTO_TRANSFER_CONNECTSERVER
 *             - ::OTTO_VERSAND_GERINGE_DATENMENGE
 *             - ::OTTO_VERSAND_ABGESCHLOSSEN falls OttoVersandAbschliessen() bereits aufgerufen wurde
 *             - weitere, siehe otto_statuscode.h
 *
 */
OttoStatusCode C_DECL OttoVersandAbschliessen(OttoVersandHandle versand,
                                              OttoRueckgabepufferHandle objektId);

/**
 * @brief      Gibt ein Versandobjekt frei.
 *
 * Das Versandobjekt darf danach nicht wieder verwendet werden.
 *
 * @param[in]  versand
 *             Handle des Versandobjekts, das freigegeben werden soll.
 * @return
 *             - siehe otto_statuscode.h
 *
 * @see
 *             - OttoVersandBeginnen()
 *             - OttoVersandFortsetzen()
 *             - OttoVersandAbschliessen()
 */
OttoStatusCode C_DECL OttoVersandBeenden(OttoVersandHandle versand);

/**
 * @brief      Initialisiert eine Datenabholung vom OTTER-Server.
 *
 * Das zurückgegebene Handle des Empfangsobjekts wird der Funktion
 * OttoEmpfangFortsetzen() übergeben, um Daten blockweise abzuholen.
 * Sind alle Daten abgeholt, wird OttoEmpfangBeenden() aufgerufen, womit
 * das Empfangsobjekt wieder freigegeben wird.
 *
 * @note       Wurde eine Otto-Instanz vor dem Aufruf dieser Funktion mit OttoProxyKonfigurationSetzen()
 *             für einen Proxy konfiguriert, wird der Empfang über den Proxy durchgeführt.
 *             Die Proxy-Konfiguration wird intern an dem Empfangsobjekt gespeichert und spätere Aufrufe
 *             von OttoProxyKonfigurationSetzen() haben keinen Einfluss auf den bereits begonnenen Empfang.
 *
 * @param[in]  instanz
 *             Handle der Otto-Instanz, auf der diese Funktion ausgeführt werden soll.
 *
 * @param[in]  objektId
 *             ID des Objekts, das vom OTTER-Server abgeholt werden soll.
 *
 * @param[in]  zertifikat
 *             Handle auf ein Zertifikatsobjekt
 *
 * @param[in]  herstellerId
 *             Hersteller-ID des Softwareproduktes
 *
 * @param[out] empfang
 *             Handle auf das Empfangsobjekt. Im Fehlerfall wird kein Empfangobjekt erzeugt.
  *
 * @return
 *             - siehe otto_statuscode.h
 *
 * @see
 *             - OttoEmpfangFortsetzen()
 *             - OttoEmpfangBeenden()
 *             - OttoProxyKonfigurationSetzen()
 *
 */
OttoStatusCode C_DECL OttoEmpfangBeginnen(OttoInstanzHandle instanz,
                                          const byteChar *objektId,
                                          OttoZertifikatHandle zertifikat,
                                          const byteChar *herstellerId,
                                          OttoEmpfangHandle *empfang);

/**
 * @brief      Initialisiert eine Datenabholung vom OTTER-Server mit Angabe eines Abholzertifikats
 *
 * Die Angabe eines Abholzertifikats ist erforderlich, wenn eine
 * nicht bei ELSTER registrierte Signaturkarte zur Authentifizierung verwendet wird.
 *
 * Die Funktion darf nicht verwendet werden, wenn zur Authentifizierung ein clientseitig
 * erzeugtes Zertifikat (CEZ) verwendet wird. (Parameter @c zertifikat)
 *
 * Das zurückgegebene Handle des Empfangsobjekts wird der Funktion
 * OttoEmpfangFortsetzen() übergeben, um Daten blockweise abzuholen.
 * Sind alle Daten abgeholt, wird OttoEmpfangBeenden() aufgerufen, womit
 * das Empfangsobjekt wieder freigegeben wird.
 *
 * Ein wichtiger Unterschied zu OttoEmpfangBeginnen() besteht darin, dass der OTTER-Server die Daten auf
 * den in @p abholzertifikat enthaltenen öffentlichen Schlüssel umschlüsselt. Die Daten werden vom Otto
 * nicht entschlüsselt und OttoEmpfangFortsetzen() gibt lediglich die verschlüsselten Daten zurück.
 *
 * @note       Wurde eine Otto-Instanz vor dem Aufruf dieser Funktion mit OttoProxyKonfigurationSetzen()
 *             für einen Proxy konfiguriert, wird der Empfang über den Proxy durchgeführt.
 *             Die Proxy-Konfiguration wird intern an dem Empfangsobjekt gespeichert und spätere Aufrufe
 *             von OttoProxyKonfigurationSetzen() haben keinen Einfluss auf den bereits begonnenen Empfang.
 *
 * @param[in]  instanz
 *             Handle der Otto-Instanz, auf der diese Funktion ausgeführt werden soll.
 *
 * @param[in]  objektId
 *             ID des Objekts, das vom OTTER-Server abgeholt werden soll.
 *
 * @param[in]  zertifikat
 *             Handle auf ein Zertifikatsobjekt
 *             Es darf hier kein clientseitig erzeugtes Zertifikat (CEZ) angegeben werden.
 *
 * @param[in]  herstellerId
 *             Hersteller-ID des Softwareproduktes
 *
 * @param[in]  abholzertifikat
 *             Base64-kodierter Teil eines X.509-v3-Zertifikats im PEM-Format
 *
 * @param[out] empfang
 *             Handle auf das Empfangsobjekt. Im Fehlerfall wird kein Empfangobjekt erzeugt.
 *
 * @return
 *             - siehe otto_statuscode.h
 *
 * @see
 *             - OttoEmpfangFortsetzen()
 *             - OttoEmpfangBeenden()
 *             - OttoProxyKonfigurationSetzen()
 *
 */
OttoStatusCode C_DECL OttoEmpfangBeginnenAbholzertifikat(OttoInstanzHandle instanz,
                                                         const byteChar *objektId,
                                                         OttoZertifikatHandle zertifikat,
                                                         const byteChar *herstellerId,
                                                         const byteChar *abholzertifikat,
                                                         OttoEmpfangHandle *empfang);

/**
 * @brief      Empfängt einen Datenblock vom OTTER-Server
 *
 * Otto empfängt Daten vom OTTER-Server und gibt sie blockweise an den Aufrufer zurück.
 * Wird \c OTTO_OK zurückgegeben, kann diese Funktion erneut aufgerufen werden und weitere
 * Datenblöcke empfangen werden. Werden leere Daten zurückgegeben, ist der Empfang beendet
 * und alle Daten wurden empfangen. Dann muss OttoEmpfangBeenden() aufgerufen werden.
 *
 * @param[in]  empfang
 *             Ein mit OttoEmpfangBeginnen() erzeugtes Handle.
 *
 * @param[out] datenBlock
 *      @parblock
 *             Rückgabepuffer mit allen oder einem Teil der empfangenen Daten. Falls leer, ist der Empfang beendet.
 *
 *             Der Inhalt des Rückgabepuffers darf nicht als null-terminierte Zeichenkette interpretiert werden, da die
 *             empfangenen Daten weitere Null-Bytes enthalten können.
 *      @endparblock
 *
 * @return
 *             - ::OTTO_OK
 *             - ::OTTO_TRANSFER_UNAUTHORIZED
 *             - ::OTTO_TRANSFER_NOT_FOUND
 *             - weitere, siehe otto_statuscode.h
 *
 * @see
 *             - OttoEmpfangBeenden()
 */
OttoStatusCode C_DECL OttoEmpfangFortsetzen(OttoEmpfangHandle empfang,
                                            OttoRueckgabepufferHandle datenBlock);

/**
 * @brief      Gibt das Empfangsobjekt wieder frei.
 *
 * Das Empfangsobjekt darf nach diesem Aufruf nicht mehr verwendet werden.
 * Wird diese Funktion aufgerufen, bevor OttoEmpfangFortsetzen() einen leeren Rückgabepuffer
 * zurückgegeben hat, können die bis dahin empfangenen Daten unvollständig sein.
 *
 * @param[in]  empfang
 *             Ein mit OttoEmpfangBeginnen() erzeugtes Handle
 *
 * @return
 *             - ::OTTO_OK
 *             - ::OTTO_EMPFANG_VORZEITIG_BEENDET falls noch nicht alle Daten mit OttoEmpfangFortsetzen() empfangen wurden
 *             - weitere, siehe otto_statuscode.h
 */
OttoStatusCode C_DECL OttoEmpfangBeenden(OttoEmpfangHandle empfang);

/**
 * @brief      Holt das Datenobjekt zu einer Objekt-ID von OTTER mit einem einzigen Funktionsaufruf vollständig ab
 *
 * Diese Funktion ist eine bequemere Alternative zu der blockweisen Datenabholung über die
 * OttoEmpfang-Funktionen. Intern bündelt sie die Aufrufe der OttoEmpfangs-Funktionen,
 * wie sie sonst von der Anwendung selbst durchgeführt werden müssten.
 *
 * Der Nachteil dieser Funktion gegenüber den OttoEmpfang-Funktionen besteht darin, dass
 * die abgeholten Daten alle im Hauptspeicher von Otto gehalten werden. Sie eignet sich daher nicht
 * für die Abholung sehr großer Datenobjekte oder wenn nur sehr wenig Hauptspeicher zur Verfügung steht.
 *
 * @note       Wurde eine Otto-Instanz vor dem Aufruf dieser Funktion mit OttoProxyKonfigurationSetzen()
 *             für einen Proxy konfiguriert, wird die Abholung über den Proxy durchgeführt.
 *
 * @param[in]  instanz
 *             Handle der Otto-Instanz, auf der diese Funktion ausgeführt werden soll.
 *
 * @param[in]  objektId
 *             ID des Datenobjekts, das vom OTTER-Server abgeholt werden soll.
 *
 * @param[in]  objektGroesse
 *      @parblock
 *              Die erwartete Größe des Datenobjekts, das vom OTTER-Server abgeholt werden soll, in Bytes.
 *              Diesen Wert findet die Anwendung zusammen mit der Objekt-ID im Rückgabe-XML zu einer
 *              PostfachAnfrage.
 *
 *              Wenn die Größe zu gering angegeben wird, geht dies zwar zu Lasten der Geschwindigkeit und
 *              des Hauptspeicherbedarfs, weil dann der Rückgabepuffer von Otto intern sukzessive vergrößert
 *              werden muss, aber es führt nicht zu einem Fehler.
 *      @endparblock
 * @param[in]  zertifikatsPfad
 *      @parblock
 *              Pfad zum Sicherheitstoken, folgende Angaben sind möglich: @mAbsatz
 *              1. Clientseitig erzeugtes Zertifikat: @mLB<a>Pfad
 *                zum Verzeichnis, in dem sich die Zertifikats-Datei (.cer)
 *                und die Datei mit dem privaten Schlüssel (.p12) befinden.
 *                Diese Sicherheitstokens wurden mit EricMtCreateKey() bzw. EricCreateKey() erzeugt.
 *                Der Pfad zum Verzeichnis ist bei clientseitig erzeugten
 *                Zertifikaten relativ zum aktuellen Arbeitsverzeichnis oder absolut
 *                anzugeben.
 *              2. Software-Portalzertifikat: @mLB<a>Pfad
 *                zur Software-Zertifikatsdatei (i.d.R. mit der Endung .pfx).
 *                Der Pfad zur Datei ist bei Software-Zertifikaten relativ zum
 *                aktuellen Arbeitsverzeichnis oder absolut anzugeben.
 *              3. Sicherheitsstick: @mLB<a>Pfad
 *                zur Treiberdatei, siehe (*). Bitte beachten, dass der Treiber
 *                betriebssystemabhängig sein kann. Weitere Informationen in der
 *                Anleitung zum Sicherheitsstick oder unter
 *                \linkExt{https://www.sicherheitsstick.de,https://www.sicherheitsstick.de}.
 *              4. Signaturkarte: (*) @mLB<a>Pfad
 *                zur Treiberdatei, welcher einen Zugriff auf die
 *                Signaturkarte ermöglicht. Weitere Informationen in
 *                der Anleitung zur Signaturkarte.
 *              5. Elektronischer Personalausweis (nPA) oder Aufenthaltstitel (eAT): @mLB<a>Die
 *                URL des eID-Clients wie zum Beispiel der AusweisApp 2.
 *                In den meisten Fällen lautet diese URL: http://127.0.0.1:24727/eID-Client.
 *                Optional kann auf die folgende Weise noch ein Testmerker angehängt werden:
 *                http://127.0.0.1:24727/eID-Client?testmerker=520000000. @mLB<a>Zu
 *                den verfügbaren Testmerkern siehe @typeDokumentation{ERiC-Entwicklerhandbuch.pdf},
 *                Kap. "Testunterstützung bei der ERiC-Anbindung".
 *
 *                <B>Wichtig:</B>
 *                Das Ad-hoc-Zertifikat, das in diesem Fall für den elektronischen
 *                Personalausweis erzeugt wird, ist nur 24 Stunden gültig.
 *      @endparblock
 *             (*) Wird der Dateipfad eines Treibers angegeben, ist der Suchmechanismus zu
 *             beachten, mit dem das jeweilige Betriebssystem dynamische Bibliotheken lädt.
 *             Weitere Informationen sind der Systemdokumentation zu den Betriebssystemfunktionen
 *             <tt>LoadLibrary()</tt> (Windows) bzw. <tt>dlopen()</tt> (Linux, AIX und macOS) zu entnehmen.
 *
 *             Pfade müssen auf Windows in der für Datei-Funktionen benutzten ANSI-Codepage,
 *             auf Linux, AIX und Linux Power in der für das Dateisystem benutzten Locale
 *             und auf macOS in der "decomposed form" von UTF-8 übergeben werden.
 *             Bitte weitere Betriebssystemspezifika bzgl. nicht erlaubter Zeichen in
 *             Pfaden und Pfadtrennzeichen beachten.
 *
 *             Für Details zu Pfaden im ERiC siehe @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kapitel
 *             "Übergabe von Pfaden an ERiC API-Funktionen".
 *
 * @param[in]  zertifikatsPasswort
 *             Das Passwort oder die PIN des Sicherheitstokens.
 *             Bei Tokens, bei denen das Passwort oder die PIN nicht von der Anwendung
 *             übergeben, sondern separat über einen Treiber (z. B. von einem Kartenlesegerät)
 *             abgefragt wird, ist hier NULL zu übergeben.
 *
 * @param[in]  herstellerId
 *             Hersteller-ID des Softwareproduktes
 * @param[in]  abholzertifikat
 *      @parblock
 *              Base64-kodierter Teil eines X.509-v3-Zertifikats im PEM-Format.
 *              Die Angabe eines Abholzertifikats ist optional und nur erlaubt,
 *              wenn im Parameter zertifikatsPfad kein clientseitig erzeugtes Zertifikat (CEZ)
 *              angegeben wurde.
 *
 *              Wird ein Abholzertifikat übergeben, so werden die Abholdaten
 *              vom Server auf den öffentlichen Schlüssel des Zertifikats umgeschlüsselt.
 *              Diese Daten werden vom Otto nicht entschlüsselt und OttoDatenAbholen() gibt
 *              lediglich die verschlüsselten Daten zurück.
 *
 *              Wenn eine nicht bei ELSTER registrierte Signaturkarte zur Authentifizierung
 *              verwendet wird, muss dieser Parameter gesetzt werden,
 *              ansonsten kann hier NULL übergeben werden.
 *      @endparblock
 * @param[out] abholDaten
 *             Rückgabepuffer mit den abgeholten Daten.
 *             Der Inhalt des Rückgabepuffers darf nicht als null-terminierte Zeichenkette interpretiert werden,
 *             da die abgeholten Daten weitere Null-Bytes enthalten können.
 *
 * @return
 *             - ::OTTO_OK
 *             - ::OTTO_TRANSFER_UNAUTHORIZED
 *             - ::OTTO_TRANSFER_NOT_FOUND
 *             - weitere, siehe otto_statuscode.h
 */
OttoStatusCode C_DECL OttoDatenAbholen(OttoInstanzHandle instanz,
                                       const byteChar *objektId,
                                       uint32_t        objektGroesse,
                                       const byteChar *zertifikatsPfad,
                                       const byteChar *zertifikatsPasswort,
                                       const byteChar *herstellerId,
                                       const byteChar *abholzertifikat,
                                       OttoRueckgabepufferHandle abholDaten);

/**
 * @brief       Die Funktion liefert die Klartextfehlermeldung zu einem Otto-Statuscode - definiert in otto_statuscode.h
 *
 * @param[in]   statuscode Statuscode
 *
 * @return
 *              - Zeiger auf einen statischen Puffer mit der Klartextmeldung zu einem Statuscode
 *                als null-terminierte, UTF-8-kodierte Zeichenkette.
 *              - @c NULL, falls kein Text ermittelt werden konnte.
 */
const char* C_DECL OttoHoleFehlertext(OttoStatusCode statuscode);

/**
 * @brief      Konfiguriert eine Otto-Instanz für einen Proxy.
 *
 * Damit eine Otto-Instanz ihre Internetverbindungen über einen
 * Proxy aufbaut, muss ihr die Proxy-Konfiguration über diese Methode
 * mitgeteilt werden.
 * Die Konfiguration gilt dann für alle Verbindungen der Instanz nach
 * außen, d.h. für die Verbindungen zu den OTTER-Servern ebenso wie
 * für Verbindungen zum ELSTER-eID-Server bei der Verwendung eines
 * elektronischen Personalausweises oder Aufenthaltstitels.
 *
 * @param[in]  instanz
 *             Die Otto-Instanz, für die die Konfiguration gelten soll.
 *
 * @param[in]  proxyKonfiguration
 *             Die Proxy-Konfiguration, die von der Otto-Instanz verwendet werden soll.
 *             Wenn hier @c NULL übergeben wird, verwendet die Otto-Instanz keinen Proxy.
 *
 * @return
 *             - siehe otto_statuscode.h
 *
 * @see
 *             - OttoProxyKonfiguration
 */
OttoStatusCode C_DECL OttoProxyKonfigurationSetzen(OttoInstanzHandle instanz,
                                                   const OttoProxyKonfiguration* proxyKonfiguration);

/**
 * @brief      Setzt den Wert einer Otto-Einstellung für die angegebene Instanz.
 *
 *
 * Die Einstellungen gelten immer nur für die übergebene Otto-Instanz.
 *
 * Die Änderungen von Werten ist nicht immer unmittelbar wirksam.
 *
 *
 * @param[in]  instanz
 *             Die Otto-Instanz, für die eine Einstellung gesetzt werden soll.
 *
 * @param[in]  einstellungName
 *             Name der Einstellung, deren Wert gesetzt werden soll.
 *
 * @param[in]  einstellungWert
 *             Wert, auf den die Einstellung gesetzt werden soll.
 *
 * @return
 *             - ::OTTO_OK
 *             - ::OTTO_EINSTELLUNG_UNBEKANNT
 *             - ::OTTO_EINSTELLUNG_WERT_UNGUELTIG
 *             - weitere, siehe otto_statuscode.h
 *
 * @see
 *             - OttoEinstellungLesen()
 *             - @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kap. "Bedeutung der Otto-Einstellungen"
 *
 */
OttoStatusCode C_DECL OttoEinstellungSetzen(OttoInstanzHandle instanz,
                                            const char *einstellungName, const byteChar *einstellungWert);

/**
 * @brief      Liest den aktuellen Wert einer Otto-Einstellung in der angegebenen Instanz aus.
 *
 *
 * @param[in]  instanz
 *             Die Otto-Instanz, deren Einstellung ausgelesen werden soll.
 *
 * @param[in]  einstellungName
 *             Name der Einstellung, deren Wert ausgelesen werden soll.
 *
 * @param[out] einstellungWert
 *             Der ausgelesene Wert der Einstellung.
 *
 * @return
 *             - ::OTTO_OK
 *             - ::OTTO_EINSTELLUNG_UNBEKANNT
 *             - weitere, siehe otto_statuscode.h
 *
 * @see
 *             - OttoEinstellungSetzen()
 *             - @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kap. "Bedeutung der Otto-Einstellungen"
 */
OttoStatusCode C_DECL OttoEinstellungLesen(OttoInstanzHandle instanz,
                                           const char *einstellungName,
                                           OttoRueckgabepufferHandle einstellungWert);

/**
 * @brief      Gibt die Version der Otto-Bibliothek zurück.
 *
 * @note       Die Version der Otto-Bibliothek ist nicht zwingend gleich der Version
 *             des ERiC-Auslieferungspaketes, sondern kann davon abweichen.
 *
 * @return
 *             - siehe otto_statuscode.h
 */
OttoStatusCode C_DECL OttoVersion(OttoRueckgabepufferHandle rueckgabepuffer);

#ifdef __cplusplus
} // extern "C"
#endif


#endif /* OTTO_H_ */
