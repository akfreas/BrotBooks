/*
 * Copyright © LfSt Bayern, Muenchen, IuK 111, 2006
 */

#ifndef ERICAPI_C_H_
#define ERICAPI_C_H_

#include "platform.h"

#include "ericapiExport.h"
#include "eric_types.h"
#include "ericdef.h"

/**
 * @file
 * @brief Deklaration der ERiC API-Funktionen für die Singlethreading-API
 *
 */

#ifdef __cplusplus
extern "C"
{
#endif

/**
\mainpage Start

Diese API-Referenz enthält detaillierte Informationen der ERiC API-Funktionen, Typdefinitionen, Aufzählungen, Datenstrukturen und Headerdateien. Die Funktionsdeklarationen für die ERiC Multithreading-API werden in ericmtapi.h, die Deklarationen der Singlethreading-API in ericapi.h bereitgestellt.

In erictoolkit.h werden Prüffunktionen bereitgestellt, deren Funktionalität identisch zu denen in ericapi.h und ericmtapi.h ist. Die erictoolkit.h hat keine Abhängigkeiten zu anderen ERiC-Bibliotheken und kann somit unabhängig von diesen eingesetzt werden.

<H3> Suchfunktion </H3>
Die ERiC API-Referenz im HTML-Format enthält ein Suchfeld mit integrierter Filterfunktion. Damit können Sie eine gezielte Suche nach Symbolen durchführen.
@mLB<a>Voraussetzung: In Ihrem Browser ist JavaScript aktiviert.

Für eine Volltextsuche nutzen Sie bitte die PDF-Ausgabe der ERiC API-Referenz. @seeAPI-Referenz{ERiC-API-Referenz.pdf}

<H3> Dokumentation </H3>
Das Dokumentationspaket beinhaltet: @mAbsatz
+ Das @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}. Hier finden Sie sowohl allgemeine Zusatzinformationen als auch spezielle Hinweise zum Gebrauch der Bibliotheken, Datensätze, Datensatzformate und Werte.
+ Das @typeTutorial{ERiC-Tutorial.pdf}. Es illustriert detailliert die Softwareentwicklung mit ERiC an den mitgelieferten Beispielen ericdemo und ottodemo.
+ Die @typeDokumentation{ERiC-Releasenotes.pdf}. Sie enthalten die Änderungen der aktuell unterstützten ERiC Releases.
+ Die @lsDokumentation{Datenartversionmatrix.ods}. Sie enthält eine Übersicht der datenartVersionen, die ERiC unterstützt. Einige API-Funktionen verwenden die <I>datenartVersion</I> als Parameter, weitere Informationen siehe @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kap. "datenartVersion – Definition und Verwendung".
+ Diese API-Referenz sowie die Dokumentation aller Feldkennungen, Plausibilitätsprüfungen, Schemata und Schnittstellenbeschreibungen.

<H3> Encoding und Zeichensatz </H3>
Alle Daten, die an die ELSTER Annahmeserver übermittelt werden, sind in UTF-8 zu kodieren. Hierbei dürfen die zu übermittelnden Daten keine BOM (=Byte Order Mark) enthalten.

Der Datentyp <B>char</B> zeigt an, wo UTF-8 kodierte Zeichenketten zu verwenden sind. Der Datentyp ::byteChar zeigt an, wo ASCII zu verwenden ist bzw. bei Pfadangaben das betriebssystemspezifische Encoding, siehe @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kap. "Übergabe von Pfaden an ERiC API-Funktionen".

Die erlaubte Zeichenmenge lässt sich dem Datentyp <I>BaseStringSType</I> aus dem ElsterBasisSchema @lsElsterBasisSchema{headerbasis_datentypen.xsd} der Schnittstellenbeschreibung entnehmen.

Bei der Eingabe von PINs sind nur Zeichen aus dem ASCII Zeichensatz, ohne Sonder- und Steuerzeichen, erlaubt, siehe @linkExt{https://de.wikipedia.org/wiki/ASCII,https://de.wikipedia.org/wiki/ASCII}.

**/

    /**
     * @brief Diese API-Funktion ist die zentrale Schnittstellenfunktion zur Kommunikation
     *        mit dem ELSTER-Annahmeserver.
     *
     * Als Austauschformat wird XML verwendet, siehe Kap. "Datenverarbeitung mit ERiC"
     * im @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}. Dort sind die Arbeitsabläufe von Einzel- und Sammellieferung
     * beschrieben.
     *
     * Die Funktion kann Steuerdaten auf Plausibilität prüfen, an den ELSTER-Annahmeserver übertragen und
     * ausdrucken, sowie Protokolle der Übertragung erzeugen. Die ProcessingFlags im Parameter
     * @c bearbeitungsFlags definieren, welche der Schritte wie ausgeführt werden.
     *
     * Je nach Anwendungsfall können die Daten authentifiziert übertragen werden und es kann
     * ein PDF-Druck der Daten erfolgen. In diesen Fällen sind die Parameter @c cryptoParameter
     * und @c druckParameter entsprechend zu befüllen. Die möglichen Parameterkombinationen und
     * Druckkennzeichnungen können im @typeDokumentation{ERiC-Entwicklerhandbuch.pdf} nachgelesen werden.
     *
     * Es werden an bestimmten Punkten der Verarbeitung benutzerdefinierte Callback Funktionen
     * aufgerufen. Siehe hierzu \ref STSection_Fortschrittcallbacks.
     *
     * Zur Erzeugung, Verwendung und Freigabe von Rückgabepuffern siehe Dokumentation
     * zu ::EricRueckgabepufferHandle.
     *
     * @param[in] datenpuffer
     *              Enthält die zu verarbeitenden XML-Daten.
     * @param[in] datenartVersion
     *      @parblock
     *              Die @c datenartVersion ist der @lsDokumentation{Datenartversionmatrix.ods} zu entnehmen.
     *
     *              Dieser Parameter darf nicht NULL sein und muss zu den XML-Eingangsdaten passen.
     *
     *              Siehe auch @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}.
     *      @endparblock
     * @param[in] bearbeitungsFlags
     *      @parblock
     *              Oder-Verknüpfung von Bearbeitungsvorgaben.
     *              Anhand dieser Vorgaben werden die übergebenen Daten verarbeitet.
     *              Der Parameter darf nicht 0 sein, zu gültigen Werten siehe ::eric_bearbeitung_flag_t.
     *
     *              Bei welchen Anwendungsfällen welche Flags möglich oder notwendig sind,
     *              ist im @typeDokumentation{ERiC-Entwicklerhandbuch.pdf} nachzulesen.
     *      @endparblock
     * @param[in] druckParameter
     *      @parblock
     *              Parameter, der für den PDF-Druck benötigt wird, siehe
     *              ::eric_druck_parameter_t.
     *
     *              Bei welchen Anwendungsfällen der Druckparameter möglich oder notwendig ist,
     *              ist im @typeDokumentation{ERiC-Entwicklerhandbuch.pdf} nachzulesen.
     *
     *              Soll kein PDF-Druck erfolgen, so ist NULL zu übergeben.
     *      @endparblock
     * @param[in] cryptoParameter
     *      @parblock
     *              Enthält die für den authentifizierten Versand benötigten
     *              Informationen und darf nur dann übergeben werden,
     *              siehe ::eric_verschluesselungs_parameter_t.
     *
     *              Erfolgt kein authentifizierter Versand, so ist NULL zu übergeben.
     *      @endparblock
     * @param[out] rueckgabeXmlPuffer
     *      @parblock
     *              Handle auf einen Rückgabepuffer, in den beim Versand
     *              Telenummer und Ordnungsbegriff, Hinweise oder Fehler bei der
     *              Regelprüfung geschrieben werden.
     *
     *              Siehe
     *              \ref STSection_Rueckgabepuffer und ::EricRueckgabepufferHandle.
     *      @endparblock
     * @param[out] serverantwortXmlPuffer
     *      @parblock
     *              Handle auf einen Rückgabepuffer, in den beim Versand die
     *              Antwort des Empfangsservers geschrieben wird.
     *
     *              Siehe
     *              \ref STSection_Rueckgabepuffer und ::EricRueckgabepufferHandle.
     *      @endparblock
     *
     * @return
     *        - ::ERIC_OK
     *        - ::ERIC_GLOBAL_UNGUELTIGER_PARAMETER
     *        - ::ERIC_GLOBAL_NULL_PARAMETER
     *        - ::ERIC_GLOBAL_DATENARTVERSION_UNBEKANNT
     *        - ::ERIC_GLOBAL_VERSCHLUESSELUNGS_PARAMETER_NICHT_ANGEGEBEN
     *        - ::ERIC_GLOBAL_PRUEF_FEHLER
     *          Plausibilitätsfehler in den Eingabedaten, die Fehlermeldungen
     *          werden im Rückgabepuffer @c rueckgabeXmlPuffer zurückgegeben.
     *          Siehe Abschnitt \ref STSection_Plausibilitaetsfehler.
     *        - ::ERIC_GLOBAL_HINWEISE
     *          Kann nur zurückgegeben werden, falls das Bearbeitungsflag
     *          ::ERIC_PRUEFE_HINWEISE angegeben wurde.
     *          Es wurden ausschließlich Hinweise zu den Eingabedaten gemeldet,
     *          die Hinweise werden im Rückgabepuffer @c rueckgabeXmlPuffer zurückgegeben.
     *          Siehe Abschnitt \ref STSection_Hinweise.
     *        - ::ERIC_GLOBAL_DATENSATZ_ZU_GROSS
     *          Die maximal zulässige Größe des XML-Eingangsdatensatzes oder des zu übermittelnden,
     *          komprimierten, verschlüsselten und base64-kodierten Datenteils,
     *          siehe @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kap. "Größenbegrenzung der
     *          Eingangsdaten", ist überschritten.
     *        - ::ERIC_TRANSFER_ERR_XML_THEADER, ::ERIC_TRANSFER_ERR_XML_NHEADER
     *          Die Serverantwort enthält Fehlermeldungen. Zur Auswertung kann
     *          entweder die Serverantwort selbst ausgewertet werden oder es wird
     *          ::EricGetErrormessagesFromXMLAnswer() aufgerufen.
     *        - ::ERIC_IO_READER_SCHEMA_VALIDIERUNGSFEHLER
     *        - ::ERIC_IO_PARSE_FEHLER
     *        - ::ERIC_GLOBAL_COMMONDATA_NICHT_VERFUEGBAR
     *        - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     *        - weitere, siehe eric_fehlercodes.h
     *
     * \section STSection_Rueckgabepuffer Inhalt des Rückgabepuffers und des Serverantwortpuffers
     *
     * Der Inhalt der Pufferspeicher kann mit ::EricRueckgabepufferInhalt() abgefragt
     * und ausgewertet werden. @c rueckgabeXmlPuffer gibt im \ref STSection_Erfolgsfall oder bei
     * \ref STSection_Plausibilitaetsfehler XML-Daten nach Schema
     * @lsAPI-Rueckgabe-Schemata{Dokumentation\API-Rueckgabe-Schemata\EricBearbeiteVorgang.xsd} zurück.
     * @c serverantwortXmlPuffer gibt bei Sendevorgängen die Antwort des ELSTER-
     * Annahmeservers zurück.
     *
     * Nach dem Aufruf der Funktion müssen programmatisch folgende Fälle aufgrund des Rückgabewerts
     * unterschieden werden.
     *
     * \subsection STSection_Erfolgsfall Erfolgsfall
     *
     * Sind alle Bearbeitungsschritte fehlerfrei durchlaufen worden, dann ist
     * der Rückgabewert ::ERIC_OK und der Text im Pufferspeicher
     * @c rueckgabeXmlPuffer enthält beim Versand XML-Daten mit generierter
     * Telenummer und bei Neuaufnahmen den Ordnungsbegriff.
     *
     * \b Beispiel:
     * \code{.xml}
     * <?xml version="1.0" encoding="UTF-8"?>
     * <EricBearbeiteVorgang xmlns="http://www.elster.de/EricXML/1.1/EricBearbeiteVorgang">
     *    <Erfolg>
     *        <Telenummer>N55</Telenummer>
     *    </Erfolg>
     * </EricBearbeiteVorgang>
     * \endcode
     *
     * Beim Versand befindet sich zusätzlich im Pufferspeicher @c serverantwortXmlPuffer die Antwort
     * des ELSTER-Annahmeservers. Bei einer Datenabholung kann diese ausgewertet werden. Details
     * hierzu befinden sich im @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}
     *
     * \subsection STSection_Hinweise Hinweise
     *
     * Falls das Bearbeitungsflag ::ERIC_PRUEFE_HINWEISE angegeben worden ist, kann der
     * Rückgabewert ::ERIC_GLOBAL_HINWEISE zurückgegeben werden.
     * Der Rückgabepuffer enthält dann die gemeldeten Hinweise.
     *
     * \b Beispiel:
     * \code{.xml}
     * <?xml version="1.0" encoding="UTF-8"?>
     * <EricBearbeiteVorgang xmlns="http://www.elster.de/EricXML/1.1/EricBearbeiteVorgang">
     *    <Hinweis>
     *        <Nutzdatenticket>1075</Nutzdatenticket>
     *        <Feldidentifikator>100001</Feldidentifikator>
     *        <Mehrfachzeilenindex>1</Mehrfachzeilenindex>
     *        <LfdNrVordruck>1</LfdNrVordruck>
     *        <VordruckZeilennummer>4</VordruckZeilennummer>
     *        <SemantischerIndex>PersonA</SemantischerIndex>
     *        <Untersachbereich>5</Untersachbereich>
     *        <RegelName>testRegelName</RegelName>
     *        <FachlicheHinweisId>9995</FachlicheHinweisId>
     *        <Text>Weitere Angaben können erforderlich sein</Text>
     *    </Hinweis>
     * </EricBearbeiteVorgang>
     * \endcode
     *
     * Die einzelnen Elemente sind in der Schemadefinition
     * @lsAPI-Rueckgabe-Schemata{Dokumentation\API-Rueckgabe-Schemata\EricBearbeiteVorgang.xsd} dokumentiert.
     * Wenn die Bearbeitungsflags ::ERIC_PRUEFE_HINWEISE und ::ERIC_VALIDIERE übergeben
     * worden sind, wurden bei der Plausibilitätsprüfung keine Fehler gefunden. Es sind
     * keine Fehler im Rückgabepuffer enthalten.
     *
     * \subsection STSection_Plausibilitaetsfehler Plausibilitätsfehler
     *
     * Bei fehlgeschlagener Plausibilitätsprüfung ist der Rückgabewert
     * ::ERIC_GLOBAL_PRUEF_FEHLER, und die Fehler werden im Rückgabepuffer
     * als XML-Daten zurückgeliefert.
     *
     * \b Beispiel:
     * \code{.xml}
     * <?xml version="1.0" encoding="UTF-8"?>
     * <EricBearbeiteVorgang xmlns="http://www.elster.de/EricXML/1.1/EricBearbeiteVorgang">
     *    <FehlerRegelpruefung>
     *        <Nutzdatenticket>1075</Nutzdatenticket>
     *        <Feldidentifikator>100001</Feldidentifikator>
     *        <Mehrfachzeilenindex>1</Mehrfachzeilenindex>
     *        <LfdNrVordruck>1</LfdNrVordruck>
     *        <VordruckZeilennummer>4</VordruckZeilennummer>
     *        <SemantischerIndex>PersonA</SemantischerIndex>
     *        <Untersachbereich>5</Untersachbereich>
     *        <RegelName>testRegelName</RegelName>
     *        <FachlicheFehlerId>9995</FachlicheFehlerId>
     *        <Text>Beim Ankreuzfeld muss der Wert 'X' angegeben werden.</Text>
     *    </FehlerRegelpruefung>
     * </EricBearbeiteVorgang>
     * \endcode
     *
     * Die einzelnen Elemente sind in der Schemadefinition
     * @lsAPI-Rueckgabe-Schemata{Dokumentation\API-Rueckgabe-Schemata\EricBearbeiteVorgang.xsd} dokumentiert.
     * Wenn die Bearbeitungsflags ::ERIC_PRUEFE_HINWEISE und ::ERIC_VALIDIERE übergeben
     * worden sind, kann der Rückgabepuffer auch Hinweise enthalten.
     *
     * \subsection STSection_Serverfehlerfall Fehler in der Serverantwort
     *
     * Ist der Rückgabewert ::ERIC_TRANSFER_ERR_XML_THEADER oder
     * ::ERIC_TRANSFER_ERR_XML_NHEADER, so enthält der Serverantwortpuffer
     * Fehlermeldungen. Zur Auswertung kann entweder die Serverantwort selbst
     * ausgewertet werden oder es wird ::EricGetErrormessagesFromXMLAnswer() aufgerufen.
     *
     * \subsection STSection_Fehler Sonstige Fehler
     *
     * Bei sonstigen Fehlern ist der Inhalt der Rückgabepuffer undefiniert. Um nähere
     * Informationen über die Fehlerursache herauszufinden, kann ::EricHoleFehlerText() mit
     * dem Rückgabewert aufgerufen werden.
     *
     * \section STSection_Fortschrittcallbacks Fortschrittcallbacks
     *
     * Während der Verarbeitung eines Anwendungsfalls werden die durch die Funktionen
     * ::EricRegistriereFortschrittCallback() und ::EricRegistriereGlobalenFortschrittCallback()
     * registrierten Callbacks aufgerufen.
     *
     * @see
     *      - EricHoleFehlerText()
     *      - EricGetErrormessagesFromXMLAnswer()
     *      - EricRegistriereFortschrittCallback()
     *      - EricRegistriereGlobalenFortschrittCallback()
     *      - @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kap. "Anwendungsfälle von EricBearbeiteVorgang()"
     *      - @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kap. der jeweiligen Datenart
     *      - @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kap. "ElsterDatenabholung"
     *      - @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kap. "Größenbegrenzung der Eingangsdaten"
     *      - @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kap. "Funktionen für Fortschrittcallbacks"
     *
     */
    ERICAPI_IMPORT int STDCALL EricBearbeiteVorgang(
        const char* datenpuffer,
        const char* datenartVersion,
        uint32_t bearbeitungsFlags,
        const eric_druck_parameter_t* druckParameter,
        const eric_verschluesselungs_parameter_t* cryptoParameter,
        EricRueckgabepufferHandle rueckgabeXmlPuffer,
        EricRueckgabepufferHandle serverantwortXmlPuffer);

    /**
     * @brief Beendet den Singlethreading-ERiC
     *
     * Die Verarbeitung mit der ERiC Singlethread-API ist beendet, als letztes muss EricBeende() aufgerufen werden.
     *
     * @return
     *          - ::ERIC_OK
     *          - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     *          - ::ERIC_GLOBAL_UNKNOWN
     * 
     * @see
     *          - EricInitialisiere()
     */
    ERICAPI_IMPORT int STDCALL EricBeende(void);

    /**
     * @brief Die PIN für ein clientseitig erzeugtes Zertifikat (CEZ) wird geändert.
     *
     * Die Funktion ändert die bei der Funktion EricCreateKey() angegebene PIN
     * und entsprechend hierfür die Prüfsumme in der Datei \c eric.sfv.
     * Falls die Datei \c eric.sfv nicht vorhanden ist, wird sie, wie bei EricCreateKey(), erstellt.
     * Eine PIN-Änderung von einem Portalzertifikat (POZ) ist nicht möglich.
     *
     * Pfade müssen auf Windows in der für Datei-Funktionen benutzten ANSI-Codepage,
     * auf Linux, AIX und Linux Power in der für das Dateisystem benutzten Locale und auf macOS in der
     * "decomposed form" von UTF-8 übergeben werden.
     * Bitte weitere Betriebssystemspezifika bzgl. nicht erlaubter Zeichen in
     * Pfaden und Pfadtrennzeichen beachten.
     *
     * Für Details zu Pfaden im ERiC siehe @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kapitel
     * "Übergabe von Pfaden an ERiC API-Funktionen"
     *
     * @param[in] psePath
     *            In dem angegebenen Pfad liegt das Schlüsselpaar
     *            \c eric_private.p12 und \c eric_public.cer
     * @param[in] oldPin
     *            Bisherige PIN.
     * @param[in] newPin
     *            Neue PIN. Die Mindestlänge beträgt 4 Stellen. Zulässige
     *            Zeichen sind alle ASCII-Zeichen ohne die Steuerzeichen.
     *
     * @return
     *         - ::ERIC_OK
     *         - ::ERIC_GLOBAL_UNGUELTIGER_PARAMETER
     *         - ::ERIC_GLOBAL_UNGUELTIGER_PARAMETER
     *         - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     *         - ::ERIC_GLOBAL_UNKNOWN
     *         - ::ERIC_CRYPT_PIN_STAERKE_NICHT_AUSREICHEND
     *         - ::ERIC_CRYPT_PIN_ENTHAELT_UNGUELTIGE_ZEICHEN
     *         - ::ERIC_CRYPT_E_PSE_PATH
     *         - ::ERIC_CRYPT_NICHT_UNTERSTUETZTES_PSE_FORMAT
     *         - ::ERIC_CRYPT_ERROR_CREATE_KEY
     *
     *
     * @see
     *         - EricCreateKey()
     *         - @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kap. "Zuordnung der API-Funktionen zur Verwendung von POZ, CEZ und AHZ"
     */
    ERICAPI_IMPORT int STDCALL EricChangePassword(
        const byteChar* psePath,
        const byteChar* oldPin,
        const byteChar* newPin);

    /**
     * @brief Die Bundesfinanzamtsnummer wird überprüft.
     *
     * Wird eine 13-stellige Steuernummer im
     * ELSTER-Steuernummernformat angegeben, so wird nur die
     * Bundesfinanzamtsnummer (= die ersten 4 Stellen der
     * 13-stelligen Steuernummer) geprüft.
     *
     * Eine Prüfung der Steuernummer selbst findet nicht statt
     * (hierfür EricPruefeSteuernummer() verwenden).
     *
     * @param[in] steuernummer
     *            13-stellige Steuernummer im ELSTER Steuernummernformat bzw.
     *            4-stellige Bundesfinanzamtsnummer.
     * @return
     *         - ::ERIC_OK
     *         - ::ERIC_GLOBAL_BUFANR_UNBEKANNT:
     *           Die Bundesfinanzamtsnummer ist unbekannt oder ungültig.
     *         - ::ERIC_GLOBAL_NULL_PARAMETER:
     *           Es wurde keine Bundesfinanzamtsnummer übergeben (Parameter ist NULL).
     *         - ::ERIC_GLOBAL_COMMONDATA_NICHT_VERFUEGBAR
     *         - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     *         - ::ERIC_GLOBAL_UNKNOWN
     *
     * @see
     *      - EricPruefeSteuernummer()
     *      - Pruefung_der_Steuer_und_Steueridentifikatsnummer.pdf, siehe \linkExt{https://www.elster.de/elsterweb/entwickler/infoseite/schnittstellenbeschreibungen,Entwicklerbereich} bei \linkExt{https://www.elster.de/eportal/start,ELSTER}.
     */
    ERICAPI_IMPORT int STDCALL EricPruefeBuFaNummer(
        const byteChar* steuernummer);

    /**
     * @brief Das @c xml wird gegen das Schema der @c datenartVersion validiert.
     *
     * Das verwendete Schema kann nachgeschlagen werden unter @lsDatenarten{Dokumentation\\Datenarten\\}\<verfahren>\\\<datenart>\\Schema\\
     *
     * Nicht unterstützte Datenartversionen: @mAbsatz
     *  - ElsterKMV
     *  - alle Bilanz Datenartversionen
     *
     * @param[in]  xml
     *             XML-Zeichenfolge
     * @param[in]  datenartVersion
     *      @parblock
     *              Die @c datenartVersion ist der @lsDokumentation{Datenartversionmatrix.ods} zu entnehmen.
     *              Dieser Parameter darf nicht NULL sein und muss zu den XML-Eingangsdaten passen.
     *
     *              Siehe auch @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}.
     *      @endparblock
     * @param[out] fehlertextPuffer
     *      @parblock
     *              Handle auf einen Rückgabepuffer, in den
     *              Fehlertexte geschrieben werden.
     *
     *              Zur Erzeugung, Verwendung und Freigabe von Rückgabepuffern
     *              siehe Dokumentation zu ::EricRueckgabepufferHandle.
     *      @endparblock
     *
     * @return
     *         - ::ERIC_OK
     *         - ::ERIC_GLOBAL_NULL_PARAMETER
     *         - ::ERIC_GLOBAL_FUNKTION_NICHT_UNTERSTUETZT: Schemavalidierung wird für die übergebene @c datenartVersion nicht unterstützt.
     *         - ::ERIC_GLOBAL_COMMONDATA_NICHT_VERFUEGBAR
     *         - ::ERIC_GLOBAL_DATENARTVERSION_UNBEKANNT
     *         - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     *         - ::ERIC_IO_READER_SCHEMA_VALIDIERUNGSFEHLER: @mLB<a>Die Fehlerbeschreibung steht im <tt>fehlertextPuffer.</tt>
     *         - ::ERIC_IO_PARSE_FEHLER: @mLB<a>Die Fehlerbeschreibung steht im <tt>fehlertextPuffer.</tt>
     *         - weitere, siehe eric_fehlercodes.h
     */
    ERICAPI_IMPORT int STDCALL EricCheckXML(
        const char* xml,
        const char* datenartVersion,
        EricRueckgabepufferHandle fehlertextPuffer);

    /**
     * @brief Das Zertifikat-Handle @c hToken wird freigegeben.
     *
     * Diese Funktion gibt das übergebene Zertifikat-Handle frei.
     * Zertifikat-Handles sollten möglichst frühzeitig, d.h. wenn sie nicht
     * mehr benötigt werden, mit EricCloseHandleToCertificate() freigegeben
     * werden, spätestens jedoch zum Programmende bzw. vor dem Entladen der
     * ericapi Bibliothek.
     *
     * Das Ad Hoc-Zertifikat eines neuen Personalausweises sollte immer genau
     * dann freigegeben werden, wenn es nicht mehr benötigt wird, jedoch spätestens
     * vor Ablauf der 24 Stunden, die das Ad Hoc-Zertifikat gültig ist.
     *
     * Tritt ein Fehler auf, kann die Fehlermeldung mit EricHoleFehlerText()
     * ausgelesen werden.
     *
     * @param[in] hToken
     *            Zertifikat-Handle wie von der Funktion
     *            EricGetHandleToCertificate() zurückgeliefert.
     * @return
     *         - ::ERIC_OK
     *         - ::ERIC_CRYPT_E_INVALID_HANDLE
     *         - ::ERIC_GLOBAL_UNGUELTIGER_PARAMETER
     *         - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     *         - ::ERIC_GLOBAL_UNKNOWN
     *         
     * @note Die folgenden Rückgabewerte gelten nur bei Verwendung des neuen Personalausweises.
     * @return
     *         - ::ERIC_TRANSFER_EID_CLIENTFEHLER
     *         - ::ERIC_TRANSFER_EID_FEHLENDEFELDER
     *         - ::ERIC_TRANSFER_EID_IDENTIFIKATIONABGEBROCHEN
     *         - ::ERIC_TRANSFER_EID_NPABLOCKIERT
     *         - ::ERIC_TRANSFER_EID_IDNRNICHTEINDEUTIG
     *         - ::ERIC_TRANSFER_EID_KEINCLIENT
     *         - ::ERIC_TRANSFER_EID_KEINKONTO
     *         - ::ERIC_TRANSFER_EID_SERVERFEHLER
     *         - ::ERIC_TRANSFER_ERR_CONNECTSERVER
     *         - ::ERIC_TRANSFER_ERR_NORESPONSE
     *         - ::ERIC_TRANSFER_ERR_PROXYAUTH
     *         - ::ERIC_TRANSFER_ERR_PROXYCONNECT
     *         - ::ERIC_TRANSFER_ERR_SEND
     *         - ::ERIC_TRANSFER_ERR_SEND_INIT
     *         - ::ERIC_TRANSFER_ERR_TIMEOUT
     *
     * @see
     *         - EricGetHandleToCertificate()
     *         - EricZertifikatOeffnenAusBytes()
     *         - EricGetPinStatus()
     *         - @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kap. "Authentifizierung mit dem neuen Personalausweis (nPA)"
     */
    ERICAPI_IMPORT int STDCALL EricCloseHandleToCertificate(
        EricZertifikatHandle hToken);

    /**
     * @brief Es werden die Kryptomittel für ein clientseitig erzeugtes
     *        Zertifikat (CEZ) in einem Verzeichnis des Dateisystems
     *        erstellt.
     *
     * Im angegebenen Verzeichnis @c pfad sind nach Ausführung
     * der Funktion EricCreateKey() drei Dateien erstellt worden: @mAbsatz
     * - \c eric_public.cer: @mLB<a>Enthält das Zertifikat mit den Daten aus \c zertifikatInfo 
     *   und darin den öffentlichen Schlüssel.
     * - \c eric_private.p12: @mLB<a>Enthält den privaten Schlüssel.
     *   Der Zugriff ist über die @c pin geschützt.
     * - \c eric.sfv: @mLB<a>Enthält die Prüfsumme der Dateien \c eric_public.cer und \c eric_private.p12.
     *   Die Integrität dieser beiden Dateien kann damit jederzeit überprüft werden.
     *
     * Ein CEZ kann unter anderem für die
     * Bescheiddaten-Rückübermittlung verwendet werden.
     * Weitere Informationen zur Datenabholung lesen Sie bitte im
     * @typeDokumentation{ERiC-Entwicklerhandbuch.pdf} nach.
     *
     * @param[in] pin
     *      @parblock
     *              PIN (Passwort), mit der auf den privaten Schlüssel
     *              zugegriffen werden kann.
     *
     *              Die Mindestlänge beträgt 4 Stellen. Zulässige
     *              Zeichen sind alle ASCII-Zeichen ohne die
     *              Steuerzeichen.
     *      @endparblock
     * @param[in] pfad
     *      @parblock
     *              Pfad (1), in dem die Kryptomittel erzeugt werden sollen.
     *              Das durch den angegebenen
     *              Pfad bezeichnete Verzeichnis muss im Dateisystem
     *              bereits existieren und beschreibbar sein.
     *
     *              Es gibt folgende Möglichkeiten: @mAbsatz
     *              - Absoluter Pfad: Empfehlung.
     *              - Relativer Pfad: Wird an das Arbeitsverzeichnis
     *                angehängt.
     *              - Leere Zeichenkette: In diesem Fall wird das
     *                Arbeitsverzeichnis verwendet.
     *      @endparblock
     * @param[in] zertifikatInfo
     *            Daten, die zur Identifikation des Schlüsselinhabers
     *            im Zertifikat abgelegt werden.
     *
     * (1) Pfade müssen auf Windows in der für Datei-Funktionen benutzten ANSI-Codepage,
     * auf Linux, AIX und Linux Power in der für das Dateisystem benutzten Locale und auf macOS in der
     * "decomposed form" von UTF-8 übergeben werden.
     * Bitte weitere Betriebssystemspezifika bzgl. nicht erlaubter Zeichen in
     * Pfaden und Pfadtrennzeichen beachten.
     *
     * Für Details zu Pfaden im ERiC siehe @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kapitel
     * "Übergabe von Pfaden an ERiC API-Funktionen".
     *
     * @return
     * - ::ERIC_OK
     * - ::ERIC_GLOBAL_NULL_PARAMETER
     * - ::ERIC_GLOBAL_UNGUELTIGE_PARAMETER_VERSION
     * - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     * - ::ERIC_GLOBAL_UNKNOWN
     * - ::ERIC_CRYPT_ZERTIFIKATSPFAD_KEIN_VERZEICHNIS
     * - ::ERIC_CRYPT_ZERTIFIKATSDATEI_EXISTIERT_BEREITS
     * - ::ERIC_CRYPT_PIN_STAERKE_NICHT_AUSREICHEND
     * - ::ERIC_CRYPT_PIN_ENTHAELT_UNGUELTIGE_ZEICHEN
     * - ::ERIC_CRYPT_ERROR_CREATE_KEY
     *
     * @see
     *     - EricChangePassword()
     *     - @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kap. "Zertifikate und Authentifizierungsverfahren"
     *     - @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kap. "Übergabe von Pfaden an ERiC API-Funktionen"
     */
    ERICAPI_IMPORT int STDCALL EricCreateKey(
        const byteChar* pin,
        const byteChar* pfad,
        const eric_zertifikat_parameter_t* zertifikatInfo);

    /**
     * @brief Diese Funktion erzeugt einen TransferHeader.
     *
     * Dieser ist der oberste Header in der Datenstruktur.
     * Er enthält Felder für die Kommunikation zwischen Server
     * und Client. Es wird nur die Kombination
     * NutzdatenHeader-Version "11" und TransferHeader-Version "11" unterstützt.
     *
     * Zur Erzeugung, Verwendung und Freigabe von Rückgabepuffern siehe Dokumentation
     * zu ::EricRueckgabepufferHandle.
     *
     * @param[in] xml
     *      @parblock
     *              XML-Datensatz, für den der \<TransferHeader>-Block erzeugt werden soll.
     *
     *              Es kann entweder ein komplettes Elster-XML oder nur der Datenteil übergeben werden.
     *
     *              ERiC nimmt bei diesem Parameter keine Konvertierung von Sonderzeichen in Entitätenreferenzen vor.
     *
     *              Attribute, die in den Start-Tags der Elemente \<Elster>
     *              bzw. \<DatenTeil> im übergebenen XML-Datensatz definiert werden, werden nicht in
     *              das Rückgabe-XML übernommen.
     *
     *              Namespace-Definitionen, die in den Start-Tags der Elemente \<Elster>
     *              bzw. \<DatenTeil> im übergebenen XML-Datensatz definiert werden, führen zu einem ::ERIC_IO_PARSE_FEHLER.
     *
     *              Im Rückgabe-XML werden im Start-Tag des Elements \<Elster> die URI "http://www.elster.de/elsterxml/schema/v11" als
     *              Default-Namensraum definiert. 
     *
     *              Die dem Element \<DatenTeil>
     *              untergeordneten Elemente aus dem übergebenen XML-Datensatz werden
     *              unverändert übernommen.
     *
     *              Der allgemeine Aufbau des Elster-XMLs wird im
     *              @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kap. "Datenverarbeitung mit ERiC" 
     *              beschrieben.
     *      @endparblock
     * @param[in] verfahren
     *            Name des Verfahrens, z.B:
     *            'ElsterAnmeldung', siehe @typeDokumentation{ERiC-Entwicklerhandbuch.pdf},
     *            Tabelle "Eigenschaften der Datenart" im
     *            jeweiligen Kapitel zur Datenart.
     * @param[in] datenart
     *            Name der Datenart, z.B.:'LStB' oder 'UStVA',
     *            siehe @typeDokumentation{ERiC-Entwicklerhandbuch.pdf},
     *            Tabelle "Eigenschaften der Datenart" im
     *            jeweiligen Kapitel zur Datenart.
     * @param[in] vorgang
     *            Name der Übertragungsart, z.B.
     *            'send-NoSig', siehe @typeDokumentation{ERiC-Entwicklerhandbuch.pdf},
     *            Tabelle "Eigenschaften der Datenart" im
     *            jeweiligen Kapitel zur Datenart.
     * @param[in] testmerker
     *      @parblock
     *              Für eine Testübertragung muss der entsprechende Testmerker angegeben werden,
     *              siehe @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kap. "Testunterstützung bei der ERiC-Anbindung".
     *
     *              Falls ein Echtfall übertragen werden soll, muss der Wert NULL angegeben werden.
     *      @endparblock
     * @param[in] herstellerId
     *            Hersteller-ID des Softwareproduktes.
     * @param[in] datenLieferant
     *      @parblock
     *              Der Wert entspricht dem XML-Element \<DatenLieferant>, wie es im
     *              Schema des Transferheaders der ElsterBasis-XML-Schnittstelle
     *              definiert ist.
     *
     *              ERiC konvertiert bei diesem Parameter Sonderzeichen in Entitätenreferenzen.
     *      @endparblock
     * @param[in] versionClient
     *      @parblock
     *              Angabe von Versionsinformation, die in der Serverantwort
     *              auch zurückgegeben wird und ausgewertet werden kann.
     *              Der Wert NULL entspricht "keine Angabe von Versionsinformation",
     *              d.h. es wird kein XML-Element \<VersionClient> im \<TransferHeader>-Block erzeugt.
     *
     *              ERiC konvertiert bei diesem Parameter Sonderzeichen in Entitätenreferenzen.
     *      @endparblock
     * @param[in] publicKey
     *      @parblock
     *              Öffentlicher Schlüssel für die Transportverschlüsselung beim Verfahren
     *              ElsterLohn. Bei anderen Verfahren sollte NULL übergeben werden.
     *
     *              Dieser Wert kann mit dem Rückgabewert von ::EricGetPublicKey() befüllt
     *              werden.
     *              Der Inhalt dieses Parameters wird in das \<TransportSchluessel>-Element
     *              der Rückgabe-XML geschrieben.
     *      @endparblock
     * @param[out] xmlRueckgabePuffer
     *      @parblock
     *              Handle auf einen Rückgabepuffer, in den
     *              das Elster-XML mit dem erzeugten TransportHeader geschrieben wird,
     *              siehe ::EricRueckgabepufferHandle.
     *
     *              Es wird immer ein vollständiger
     *              Elster-XML-Datensatz mit dem \<Elster>-Element als Wurzel-Element
     *              zurückgeliefert. Bzgl. der darin enthaltenen XML-Namespace-Definitionen sind
     *              die bei der Beschreibung des Parameters "xml" genannten Einschränkungen
     *              zu berücksichtigen.
     *      @endparblock
     *
     * @return
     *         - ::ERIC_OK
     *         - ::ERIC_GLOBAL_NULL_PARAMETER
     *         - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     *         - ::ERIC_TRANSFER_ERR_XML_ENCODING: Die übergebenen XML-Daten sind
     *                  nicht UTF-8 kodiert.
     *         - ::ERIC_IO_PARSE_FEHLER
     *         - ::ERIC_IO_DATENTEILNOTFOUND
     *         - ::ERIC_IO_DATENTEILENDNOTFOUND
     *         - weitere, siehe eric_fehlercodes.h
     *
     *
     * @see
     *     - ERiC-Returncodes und Fehlertexte sind in eric_fehlercodes.h zu finden.
     *     - @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kap. "Datenverarbeitung mit ERiC"
     *     - @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kap. "Anwendungsfälle von EricBearbeiteVorgang()"             
     */
    ERICAPI_IMPORT int STDCALL EricCreateTH(
        const char* xml, const char* verfahren,
        const char* datenart, const char* vorgang,
        const char* testmerker, const char* herstellerId,
        const char* datenLieferant, const char* versionClient,
        const byteChar* publicKey,
        EricRueckgabepufferHandle xmlRueckgabePuffer);

    /**
     * @brief Erzeugt einen Version 4 Universally Unique Identifier (UUID) gemäß RFC 4122.
     *
     * @param[out] uuidRueckgabePuffer Handle auf einen Rückgabepuffer, in den die erzeugte UUID geschrieben wird.
     * @return
     *         - ::ERIC_OK
     *         - ::ERIC_GLOBAL_NULL_PARAMETER
     *         - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     *         - ::ERIC_GLOBAL_UNKNOWN
     */
    ERICAPI_IMPORT int STDCALL EricCreateUUID(
        EricRueckgabepufferHandle uuidRueckgabePuffer);

    /**
     *  @brief Es werden die mit der Datenabholung abgeholten und verschlüsselten Daten entschlüsselt.
     *
     *  Falls während der Bearbeitung ein Fehler auftritt,
     *  liefert die Funktion EricHoleFehlerText() den
     *  dazugehörigen Fehlertext.
     *
     * @param[in] zertifikatHandle Handle auf das zum Entschlüsseln zu verwendende Zertifikat.
     * @param[in] pin PIN zum Zugriff auf das Zertifikat.
     * @param[in] base64Eingabe
     *      @parblock
     *              Base64-kodierte verschlüsselte Daten oder Anhänge, welche mit dem Verfahren
     *              ElsterDatenabholung abgeholt wurden.
     *
     *              Die Abholdaten befinden sich im Element @mLB<tt>/Elster[1]/DatenTeil[1]/Nutzdatenblock/Nutzdaten[1]/Datenabholung[1]/Abholung[1]/Datenpaket</tt>
     *
     *              Die optionalen Anhänge befinden sich im Element @mLB<tt>/Elster[1]/DatenTeil[1]/Nutzdatenblock/Nutzdaten[1]/Datenabholung[1]/Abholung[1]/Anhaenge[1]/Anhang[1]/Dateiinhalt</tt>
     *      @endparblock
     * @param[out] rueckgabePuffer
     *      @parblock
     *              Handle auf einen Rückgabepuffer, in den
     *              die entschlüsselten Daten geschrieben werden. Im Fehlerfall ist der Inhalt des Rückgabepuffers undefiniert.
     *
     *              Zur Erzeugung, Verwendung und Freigabe von Rückgabepuffern
     *              siehe ::EricRueckgabepufferHandle.
     *      @endparblock
     * @return
     *  - ::ERIC_OK
     *  - ::ERIC_GLOBAL_NULL_PARAMETER
     *  - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     *  - ::ERIC_GLOBAL_ERR_DEKODIEREN
     *  - ::ERIC_GLOBAL_UNKNOWN
     *  - Ein Zertifikatsfehler aus dem Statuscodebereich von ::ERIC_CRYPT_E_INVALID_HANDLE = 610201101 bis 610201212
     *
     * @see
     *      - EricHoleFehlerText()
     *      - @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kap. "ElsterDatenabholung"
     */
    ERICAPI_IMPORT int STDCALL EricDekodiereDaten(
        EricZertifikatHandle zertifikatHandle,
        const byteChar* pin,
        const byteChar* base64Eingabe,
        EricRueckgabepufferHandle rueckgabePuffer);

    /**
     * @brief Alle Einstellungen werden auf den jeweiligen Standardwert zurückgesetzt.
     *
     * Die Standardwerte sind im Dokument @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kap. "Vorbelegung der ERiC-Einstellungen"
     * zu finden.
     *
     *
     * @return
     *    -    ::ERIC_OK
     *    -    ::ERIC_GLOBAL_UNKNOWN
     *    -    ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     *
     * @see
     *      - EricEinstellungSetzen()
     *      - EricEinstellungLesen()
     *      - EricEinstellungZuruecksetzen()
     *      - @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kap. "Bedeutung der ERiC-Einstellungen"
     */
    ERICAPI_IMPORT int STDCALL EricEinstellungAlleZuruecksetzen(
        void);

    /**
     * @brief Der Wert der API-Einstellung @c name wird im @c rueckgabePuffer zurückgeliefert.
     *
     * @param[in] name Name der API-Einstellung, NULL-terminierte Zeichenfolge.
     * @param[out] rueckgabePuffer 
     *      @parblock
     *              Handle auf einen Rückgabepuffer, in den
     *              der Wert der API-Einstellung geschrieben wird.
     *
     *              Zur Erzeugung, Verwendung und Freigabe von Rückgabepuffern
     *              siehe ::EricRueckgabepufferHandle.
     *      @endparblock
     *
     * @return
     * - ::ERIC_OK
     * - ::ERIC_GLOBAL_EINSTELLUNG_NAME_UNGUELTIG
     * - ::ERIC_GLOBAL_NULL_PARAMETER
     * - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     * - ::ERIC_GLOBAL_UNKNOWN
     *
     * @see
     *      - EricEinstellungSetzen()
     *      - EricEinstellungZuruecksetzen()
     *      - EricEinstellungAlleZuruecksetzen()
     *      - @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kap. "Bedeutung der ERiC-Einstellungen"
     */
    ERICAPI_IMPORT int STDCALL EricEinstellungLesen(
        const char* name,
        EricRueckgabepufferHandle rueckgabePuffer);

    /**
     * @brief Die API-Einstellung @c name wird auf den @c wert gesetzt.
     *
     * Nach dem Laden der ERiC-Bibliotheken hat jede API-Einstellung
     * ihren Standardwert. Mit dieser Funktion kann der Wert
     * verändert werden. Der Wertebereich der jeweiligen API-Einstellung
     * ist zu beachten.
     *
     * Bei Pfad-Einstellungen muss auf Windows der Wert in der für Datei-Funktionen
     * benutzten ANSI-Codepage, auf Linux, AIX und Linux Power in der für das Dateisystem benutzten Locale
     * und auf macOS in der "decomposed form" von UTF-8 übergeben werden.
     * Bitte weitere Betriebssystemspezifika bzgl. nicht erlaubter Zeichen in
     * Pfaden und Pfadtrennzeichen beachten.
     *
     * Für Details zu Pfaden im ERiC siehe @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kapitel
     * "Übergabe von Pfaden an ERiC API-Funktionen"
     *
     * @param[in] name Name der API-Einstellung, NULL-terminierte Zeichenfolge.
     * @param[in] wert Wert der API-Einstellung, NULL-terminierte Zeichenfolge.
     *
     * @return
     * - ::ERIC_OK
     * - ::ERIC_GLOBAL_EINSTELLUNG_NAME_UNGUELTIG
     * - ::ERIC_GLOBAL_EINSTELLUNG_WERT_UNGUELTIG
     * - ::ERIC_GLOBAL_NULL_PARAMETER
     * - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     * - ::ERIC_GLOBAL_UNKNOWN
     *
     * @see
     *      - EricEinstellungLesen()
     *      - EricEinstellungZuruecksetzen()
     *      - EricEinstellungAlleZuruecksetzen()
     *      - @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kap. "Bedeutung der ERiC-Einstellungen"
     */
    ERICAPI_IMPORT int STDCALL EricEinstellungSetzen(
        const char* name,
        const byteChar* wert);

    /**
     * @brief Der Wert der API-Einstellung @c name wird auf den Standardwert zurückgesetzt.
     *
     * Die Standardwerte sind im Dokument @typeDokumentation{ERiC-Entwicklerhandbuch.pdf},
     * Kap. "Vorbelegung der ERiC-Einstellungen" zu finden.
     *
     * @param[in] name Name der API-Einstellung, NULL-terminierte Zeichenfolge.
     *
     * @return
     * - ::ERIC_OK
     * - ::ERIC_GLOBAL_EINSTELLUNG_NAME_UNGUELTIG
     * - ::ERIC_GLOBAL_NULL_PARAMETER
     * - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     * - ::ERIC_GLOBAL_UNKNOWN
     *
     * @see
     *      - EricEinstellungSetzen()
     *      - EricEinstellungLesen()
     *      - EricEinstellungAlleZuruecksetzen()
     *      - @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kap. "Bedeutung der ERiC-Einstellungen"
     */
    ERICAPI_IMPORT int STDCALL EricEinstellungZuruecksetzen(
        const char* name);

    /**
     * @brief Alle verwendeten Plugin-Bibliotheken werden entladen und deren Speicher wird freigegeben.
     *
     * Der ERiC lädt die für die Bearbeitung notwendigen Plugin-Bibliotheken permanent
     * in den Speicher und gibt diese erst mit dem Aufruf dieser Funktion wieder frei.
     *
     * @note EricEntladePlugins() sollte erste dann aufgerufen werden, wenn die
     *       Plugin-Bibliotheken definitiv nicht mehr benötigt werden.
     *       Ein erneutes Laden der Bibliotheken ist verhältnismäßig zeitintensiv.
     *
     * Falls eine Plugin-Bibliothek nicht entladen werden kann,
     * wird dies in eric.log protokolliert. Der Returncode ist immer ::ERIC_OK.
     *
     *
     * @return
     * - ::ERIC_OK
     * - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     * - ::ERIC_GLOBAL_UNKNOWN
     *
     * @see
     * - @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kap. "Verwendung von EricEntladePlugins()"
     */
    ERICAPI_IMPORT int STDCALL EricEntladePlugins(
        void);

    /**
     * @brief Konvertiert ein Einheitswert-Aktenzeichen im ELSTER-Format in ein landesspezifisches Bescheidformat
     *
     * Konvertiert ein Einheitswert-Aktenzeichen im ELSTER-Format (z.B. 2831400190001250002) 
     * in ein landesspezifisches Einheitswert-Aktenzeichen im Bescheidformat (z.B. 3100190001250002).
     *
     * @param[in] ewAzElster Zeiger auf ein Einheitswert-Aktenzeichen im ELSTER-Format  (z.B. 2831400190001250002)
     * @param[out] ewAzBescheidPuffer 
     *      @parblock
     *              Handle auf einen Rückgabepuffer, in den
     *              das Einheitswert-Aktenzeichen im Bescheidformat (z.B. 3100190001250002) geschrieben wird.
     *
     *              Zur Erzeugung, Verwendung und Freigabe von Rückgabepuffern
     *              siehe Dokumentation zu ::EricRueckgabepufferHandle.
     *      @endparblock
     *
     * @return
     * - ::ERIC_OK
     * - ::ERIC_GLOBAL_EWAZ_UNGUELTIG
     * - ::ERIC_GLOBAL_NULL_PARAMETER
     * - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     * - ::ERIC_GLOBAL_UNKNOWN
     *
     */
    ERICAPI_IMPORT int STDCALL EricFormatEWAz(
        const byteChar *ewAzElster, 
        EricRueckgabepufferHandle ewAzBescheidPuffer);

    /**
     * @brief Die Steuernummer @c eingabeSteuernummer wird in das Bescheid-Format des jeweiligen Bundeslandes umgewandelt.
     *
     * @param[in] eingabeSteuernummer
     *            Gültige, zu formatierende Steuernummer im
     *            ELSTER-Steuernummernformat.
     * @param[out] rueckgabePuffer 
     *      @parblock
     *              Handle auf einen Rückgabepuffer, in den
     *              die formatierte Steuernummer im Bescheid-Format des
     *              jeweiligen Bundeslandes geschrieben wird.
     *
     *              Zur Erzeugung, Verwendung und Freigabe von Rückgabepuffern
     *              siehe Dokumentation zu ::EricRueckgabepufferHandle.
     *      @endparblock
     *
     * @return
     *     - ::ERIC_OK
     *     - ::ERIC_GLOBAL_NULL_PARAMETER
     *     - ::ERIC_GLOBAL_STEUERNUMMER_UNGUELTIG
     *     - ::ERIC_GLOBAL_COMMONDATA_NICHT_VERFUEGBAR
     *     - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     *     - ::ERIC_GLOBAL_UNKNOWN
     *
     * @see
     *     - Pruefung_der_Steuer_und_Steueridentifikatsnummer.pdf, siehe \linkExt{https://www.elster.de/elsterweb/entwickler/infoseite/schnittstellenbeschreibungen,Entwicklerbereich} bei \linkExt{https://www.elster.de/eportal/start,ELSTER}.
     */
    ERICAPI_IMPORT int STDCALL EricFormatStNr(
        const byteChar* eingabeSteuernummer,
        EricRueckgabepufferHandle rueckgabePuffer);

    /**
     * @brief Die Auswahlliste(n) für @c datenartVersion oder @c feldkennung wird zurückgeliefert.
     *
     * @details Anwendungsfälle: @mAbsatz
     * 1. Parameter @c feldkennung ist nicht NULL: @mLB<a>Die Funktion
     *    liefert die zur @c feldkennung und @c datenartVersion gehörige Auswahlliste.
     * 2. Parameter @c feldkennung ist NULL: @mLB<a>Die Funktion
     *    liefert alle zur @c datenartVersion gehörigen Feldkennungen mit hinterlegten Auswahllisten.
     *
     * Für die Ermittlung der Auswahllisten vieler Feldkennungen wird aus Performanzgründen Anwendungsfall 2 empfohlen.
     * Die Funktion liefert Auswahllisten zu Feldkennungen vom Format "NichtAbgeschlosseneEnumeration" zurück.
     * Diese Auswahllisten werden auch in der Jahres-/@lsDeltadokumentation{Deltadokumentation} dokumentiert.
     *
     * @param[in] datenartVersion
     *            Dieser Parameter darf nicht NULL sein.
     *            Die gültigen Datenartversionen sind in der @lsDokumentation{Datenartversionmatrix.ods} enthalten.
     * @param[in] feldkennung
     *            Feldkennung, für welche die Auswahlliste zu ermitteln ist.
     * @param[out] rueckgabeXmlPuffer
     *      @parblock
     *              Handle auf einen Rückgabepuffer, in den
     *              die angeforderten Auswahlliste(n) als XML-Daten geschrieben werden.
     *              Die XML-Daten folgen der XML Schema Definition in @lsAPI-Rueckgabe-Schemata{Dokumentation\API-Rueckgabe-Schemata\EricGetAuswahlListen.xsd}. \n 
     *
     *              Zur Erzeugung, Verwendung und Freigabe von Rückgabepuffern
     *              siehe ::EricRueckgabepufferHandle.
     *      @endparblock
     *
     * \b Beispiel:
     * \code{.xml}
     * <?xml version="1.0" encoding="UTF-8"?>
     * <EricGetAuswahlListen xmlns="http://www.elster.de/EricXML/1.0/EricGetAuswahlListen">
     *     <AuswahlListe>
     *         <Feldkennung>0104110</Feldkennung>
     *         <ListenElement>Arbeitslosengeld</ListenElement>
     *         <ListenElement>Elterngeld</ListenElement>
     *         <ListenElement>Insolvenzgeld</ListenElement>
     *         <ListenElement>Krankengeld</ListenElement>
     *         <ListenElement>Mutterschaftsgeld</ListenElement>
     *     </AuswahlListe>
     * </EricGetAuswahlListen>
     * \endcode
     *
     * @return
     *         - ::ERIC_OK
     *         - ::ERIC_GLOBAL_NULL_PARAMETER
     *         - ::ERIC_GLOBAL_KEINE_DATEN_VORHANDEN
     *         - ::ERIC_GLOBAL_DATENARTVERSION_UNBEKANNT
     *         - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     *         - ::ERIC_GLOBAL_UNKNOWN
     */
    ERICAPI_IMPORT int STDCALL EricGetAuswahlListen(
        const char* datenartVersion,
        const char* feldkennung,
        EricRueckgabepufferHandle rueckgabeXmlPuffer);

    /**
     * @brief Aus dem Antwort-XML des Finanzamtservers wird das Transferticket und Returncodes/Fehlermeldungen zurückgegeben.
     *
     * Die Funktion liefert bei erfolgreicher Ausführung: @mAbsatz
     * - Das Transferticket aus dem Antwort-XML in dem Parameter @c transferticketPuffer.
     * - Den Returncode und die Fehlermeldung aus dem Transferheader
     *   in den Parametern \c returncodeTHPuffer und <tt>fehlertextTHPuffer.</tt>
     * - Für jeden Nutzdatenheader dessen Returncode und Fehlermeldung als XML-Daten im
     *   Parameter @c returncodesUndFehlertexteNDHXmlPuffer nach XML Schema Definition
     *   @lsAPI-Rueckgabe-Schemata{Dokumentation\API-Rueckgabe-Schemata\EricGetErrormessagesFromXMLAnswer.xsd}.
     *   Enthält das Antwort-XML keine Nutzdaten, wird kein \<Fehler\> Element zurückgegeben.
     *
     * Zur Erzeugung, Verwendung und Freigabe von Rückgabepuffern siehe Dokumentation
     * zu ::EricRueckgabepufferHandle.
     *
     * @param[in] xml
     *            Antwort-XML des ELSTER-Servers, das ausgewertet
     *            werden soll. Der originale XML-Server-Datenstrom
     *            sollte unverändert übergeben werden und darf
     *            insbesondere keine Zeilenumbruchzeichen enthalten.
     * @param[out] transferticketPuffer Handle auf einen Rückgabepuffer, in den
     *            das Transferticket geschrieben wird, siehe ::EricRueckgabepufferHandle.
     * @param[out] returncodeTHPuffer Handle auf einen Rückgabepuffer, in den
     *            der Returncode aus dem Transferheader geschrieben wird, 
     *            siehe ::EricRueckgabepufferHandle.
     * @param[out] fehlertextTHPuffer Handle auf einen Rückgabepuffer, in den
     *            die Fehlermeldung aus dem Transferheader geschrieben wird, siehe
     *            ::EricRueckgabepufferHandle.
     * @param[out] returncodesUndFehlertexteNDHXmlPuffer Handle auf einen
     *            Rückgabepuffer, in den die Liste der Returncodes nach XML-Schema
     *            @lsAPI-Rueckgabe-Schemata{Dokumentation\API-Rueckgabe-Schemata\EricGetErrormessagesFromXMLAnswer.xsd}
     *            geschrieben werden, siehe ::EricRueckgabepufferHandle.
     *
     * \b Beispiel:
     * \code{.xml}
     * <?xml version="1.0" encoding="UTF-8"?>
     * <EricGetErrormessagesFromXMLAnswer xmlns="http://www.elster.de/EricXML/1.0/EricGetErrormessagesFromXMLAnswer">
     *     <Fehler>
     *       <Code>1</Code>
     *       <Meldung>Fehlermeldung 1</Meldung>
     *     </Fehler>
     *     <Fehler>
     *       <Code>2</Code>
     *       <Meldung>Fehlermeldung 2</Meldung>
     *     </Fehler>
     *     (...)
     * </EricGetErrormessagesFromXMLAnswer>
     * \endcode
     *
     * @return
     *         - ::ERIC_OK
     *         - ::ERIC_IO_PARSE_FEHLER
     *         - ::ERIC_GLOBAL_NULL_PARAMETER
     *         - ::ERIC_GLOBAL_PUFFER_ZUGRIFFSKONFLIKT
     *         - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     *         - ::ERIC_GLOBAL_UNKNOWN
     *
     * @note
     *     Diese Funktion kann nicht dafür verwendet werden, die Antwort im Datenteil
     *     aus einer dekodierten Serverantwort für Lohnsteuerbescheinigungen
     *     auszuwerten.
     *
     * @see
     *      - XML-Schema des Transferheaders: @lsElsterBasisSchema{Dokumentation\ElsterBasisSchema\Schema\th000011_extern.xsd}
     *      - XML-Schema des Nutzdatenheaders: @lsElsterBasisSchema{Dokumentation\ElsterBasisSchema\Schema\ndh000011.xsd}
     *      - @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kap. "Schnittstellenbeschreibungen",
     *        Tabelle "ELSTER > Ergänzende Softwarepakete und Dateien > Schnittstellenbeschreibungen"
     */
    ERICAPI_IMPORT int STDCALL EricGetErrormessagesFromXMLAnswer(
        const char* xml,
        EricRueckgabepufferHandle transferticketPuffer,
        EricRueckgabepufferHandle returncodeTHPuffer,
        EricRueckgabepufferHandle fehlertextTHPuffer,
        EricRueckgabepufferHandle returncodesUndFehlertexteNDHXmlPuffer);

    /**
     * @brief Für das übergebene Zertifikat in @c pathToKeystore wird das Handle @c hToken
     *        und die unterstützten PIN-Werte @c iInfoPinSupport zurückgeliefert.
     *
     * Die ERiC API benötigt Zertifikat-Handles typischerweise
     * bei kryptografischen Operationen.
     *
     * Zertifikat-Handles sollten möglichst frühzeitig, d.h. wenn sie nicht
     * mehr benötigt werden, mit EricCloseHandleToCertificate() freigegeben
     * werden, spätestens jedoch zum Programmende bzw. vor dem Entladen der
     * ericapi Bibliothek.
     *
     * @param[out] hToken
     *      @parblock
     *              Handle zu einem der folgenden Zertifikate: @mAbsatz
     *              - Portalzertifikat
     *              - clientseitig erzeugtes Zertifikat
     *              - Ad Hoc-Zertifikat für den neuen Personalausweis
     *      @endparblock
     * @param[out] iInfoPinSupport
     *      @parblock
     *              Wird in @c iInfoPinSupport ein Zeiger ungleich NULL übergeben und die Funktion mit ::ERIC_OK beendet,
     *              dann enthält @c iInfoPinSupport einen vorzeichenlosen Integer-Wert.
     *
     *              In diesem Wert ist kodiert abgelegt, ob eine PIN-Eingabe
     *              erforderlich ist und welche PIN-Statusinformationen
     *              unterstützt werden.
     *
     *              Die kodierten Werte (nachfolgend in hexadezimaler Form angegeben)
     *              können durch ein binäres ODER kombiniert werden und bedeuten im
     *              Einzelnen: @mAbsatz
     *              - \c 0x00: Keine PIN-Angabe erforderlich, kein PIN-Status unterstützt.
     *              - \c 0x01: PIN-Angabe für Signatur erforderlich.
     *              - \c 0x02: PIN-Angabe für Entschlüsselung erforderlich.
     *              - \c 0x04: PIN-Angabe für Verschlüsselung des Zertifikats erforderlich.
     *              - \c 0x08: reserviert (wird derzeit nicht verwendet)
     *              - \c 0x10: PIN-Status "Pin Ok" wird unterstützt.
     *              - \c 0x20: PIN-Status "Der letzte Versuch der Pin-Eingabe schlug fehl" wird unterstützt.
     *              - \c 0x40: PIN-Status "Beim nächsten fehlerhaften Versuch wird die Pin gesperrt" wird unterstützt.
     *              - \c 0x80: PIN-Status "Pin ist gesperrt" wird unterstützt.
     *
     *              Falls vom Aufrufer NULL übergeben wird, gibt die Funktion nichts zurück.
     *      @endparblock
     * @param[in] pathToKeystore
     *      @parblock
     *              Folgende Zertifikatstypen werden unterstützt: @mAbsatz
     *              1. Clientseitig erzeugtes Zertifikat: @mLB<a>Pfad
     *                zum Verzeichnis, in dem sich die Zertifikats-Datei (.cer)
     *                und die Datei mit dem privaten Schlüssel (.p12) befinden.
     *                Diese Kryptomittel wurden mit EricCreateKey() erzeugt.
     *                Der Pfad zum Verzeichnis ist bei clientseitig erzeugten
     *                Zertifikaten relativ zum aktuellen Arbeitsverzeichnis oder absolut
     *                anzugeben.
     *              2. Software-Portalzertifikat: @mLB<a>Pfad
     *                zur Software-Zertifikatsdatei (i.d.R. mit der Endung .pfx).
     *                Der Pfad zur Datei ist bei Software-Zertifikaten relativ zum
     *                aktuellen Arbeitsverzeichnis oder absolut anzugeben.
     *              3. Sicherheitsstick: @mLB<a>Pfad
     *                zur Treiberdatei, siehe (1). Bitte beachten, dass der Treiber
     *                betriebssystemabhängig sein kann. Weitere Informationen in der
     *                Anleitung zum Sicherheitsstick oder unter
     *                \linkExt{https://www.sicherheitsstick.de,https://www.sicherheitsstick.de}.
     *              4. Signaturkarte: @mLB<a>Pfad
     *                zur Treiberdatei, welcher einen Zugriff auf die
     *                Signaturkarte ermöglicht, siehe (1). Weitere Informationen in
     *                der Anleitung zur Signaturkarte.
     *              5. Neuer Personalausweis (nPA): @mLB<a>URL
     *                des eID-Clients wie zum Beispiel der AusweisApp 2
     *                In den meisten Fällen lautet diese URL: http://127.0.0.1:24727/eID-Client
     *                Optional kann auf die folgende Weise noch ein Testmerker angehängt werden:
     *                http://127.0.0.1:24727/eID-Client?testmerker=520000000. @mLB<a>Zu
     *                den verfügbaren Testmerkern siehe @typeDokumentation{ERiC-Entwicklerhandbuch.pdf},
     *                Kap. "Testunterstützung bei der ERiC-Anbindung".
     *                
     *                <b>Wichtig:</b> Das Ad Hoc-Zertifikat, das in diesem Fall für den neuen
     *                         Personalausweis erzeugt wird, ist nur 24 Stunden gültig.
     *      @endparblock
     *
     *      (1) Bei Sicherheitssticks und Signaturkarten ist bei der Angabe
     *      des Treibers der Suchmechanismus nach dynamischen Modulen des
     *      jeweiligen Betriebssystems zu berücksichtigen. Weitere
     *      Informationen sind z.B. unter Windows der Dokumentation der
     *      <tt>LoadLibrary()</tt> oder unter Linux und macOS der Dokumentation der
     *      <tt>dlopen()</tt> zu entnehmen.
     *
     *      Pfade müssen auf Windows in der für Datei-Funktionen benutzten ANSI-Codepage,
     *      auf Linux, AIX und Linux Power in der für das Dateisystem benutzten Locale
     *      und auf macOS in der "decomposed form" von UTF-8 übergeben werden.
     *      Bitte weitere Betriebssystemspezifika bzgl. nicht erlaubter Zeichen in
     *      Pfaden und Pfadtrennzeichen beachten.
     *
     *      Für Details zu Pfaden im ERiC siehe @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kapitel
     *      "Übergabe von Pfaden an ERiC API-Funktionen".
     *
     * @return
     *         - ::ERIC_OK
     *         - ::ERIC_GLOBAL_NULL_PARAMETER
     *         - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     *         - ::ERIC_GLOBAL_UNKNOWN
     *         - ::ERIC_CRYPT_NICHT_UNTERSTUETZTES_PSE_FORMAT
     *         - ::ERIC_CRYPT_E_MAX_SESSION
     *         - ::ERIC_CRYPT_E_PSE_PATH
     *         - ::ERIC_CRYPT_E_BUSY
     *         - ::ERIC_CRYPT_E_P11_SLOT_EMPTY
     *         - ::ERIC_CRYPT_E_NO_SIG_ENC_KEY
     *         - ::ERIC_CRYPT_E_LOAD_DLL
     *         - ::ERIC_CRYPT_E_NO_SERVICE
     *         - ::ERIC_CRYPT_E_ESICL_EXCEPTION
     * @note Die folgenden Rückgabewerte gelten nur bei Verwendung des neuen Personalausweises.
     * @return
     *         - ::ERIC_TRANSFER_EID_CLIENTFEHLER
     *         - ::ERIC_TRANSFER_EID_FEHLENDEFELDER
     *         - ::ERIC_TRANSFER_EID_IDENTIFIKATIONABGEBROCHEN
     *         - ::ERIC_TRANSFER_EID_NPABLOCKIERT
     *         - ::ERIC_TRANSFER_EID_IDNRNICHTEINDEUTIG
     *         - ::ERIC_TRANSFER_EID_KEINCLIENT
     *         - ::ERIC_TRANSFER_EID_KEINKONTO
     *         - ::ERIC_TRANSFER_EID_SERVERFEHLER
     *         - ::ERIC_TRANSFER_ERR_CONNECTSERVER
     *         - ::ERIC_TRANSFER_ERR_NORESPONSE
     *         - ::ERIC_TRANSFER_ERR_PROXYAUTH
     *         - ::ERIC_TRANSFER_ERR_PROXYCONNECT
     *         - ::ERIC_TRANSFER_ERR_SEND
     *         - ::ERIC_TRANSFER_ERR_SEND_INIT
     *         - ::ERIC_TRANSFER_ERR_TIMEOUT
     *
     * @see
     *         - EricCloseHandleToCertificate()
     *         - EricGetPinStatus()
     */
    ERICAPI_IMPORT int STDCALL EricGetHandleToCertificate(
        EricZertifikatHandle* hToken,
        uint32_t* iInfoPinSupport,
        const byteChar* pathToKeystore);

    /**
     * @brief Für das im Speicher übergebene Zertifikat wird das Handle @c hToken zurückgeliefert.
     *
     * Die ERiC API benötigt Zertifikat-Handles typischerweise
     * bei kryptografischen Operationen.
     *
     * Zertifikat-Handles sollten möglichst frühzeitig, d.h. wenn sie nicht
     * mehr benötigt werden, mit EricCloseHandleToCertificate() freigegeben
     * werden, spätestens jedoch zum Programmende bzw. vor dem Entladen der
     * Bibliothek ericapi.
     *
     * @param[out] hToken
     *      @parblock
     *              Handle zu einem der folgenden Zertifikate: @mAbsatz
     *              - Portalzertifikat
     *              - clientseitig erzeugtes Zertifikat
     *      @endparblock
     * @param[in] pkcs12Container
     *            Speicheradresse des Zertifikats im PKCS#12-Format.
     *            Es werden nur passwortgeschützte PKCS#12-Container akzeptiert.
     * @param[in] containerGroesse
     *            Größe des PKCS#12-Containers in Bytes
     * @param[in] pkcs12Passwort
     *            Das Passwort oder die PIN des PKCS#12-Containers.
     *            Dieser Parameter darf nicht NULL sein.
     * @return
     *         - ::ERIC_OK
     *         - ::ERIC_GLOBAL_NULL_PARAMETER
     *         - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     *         - ::ERIC_GLOBAL_UNKNOWN
     *         - ::ERIC_CRYPT_NICHT_UNTERSTUETZTES_PSE_FORMAT
     *         - ::ERIC_CRYPT_E_MAX_SESSION
     *         - ::ERIC_CRYPT_E_PSE_PATH
     *         - ::ERIC_CRYPT_E_BUSY
     *         - ::ERIC_CRYPT_E_P11_SLOT_EMPTY
     *         - ::ERIC_CRYPT_E_NO_SIG_ENC_KEY
     *         - ::ERIC_CRYPT_E_PIN_WRONG
     *         - ::ERIC_CRYPT_E_LOAD_DLL
     *         - ::ERIC_CRYPT_E_NO_SERVICE
     *         - ::ERIC_CRYPT_E_ESICL_EXCEPTION
     *
     * @see
     *         - EricCloseHandleToCertificate()
     *         - EricGetPinStatus()
     */
    ERICAPI_IMPORT int STDCALL EricZertifikatOeffnenAusBytes(
        EricZertifikatHandle* hToken,
        const byteChar *pkcs12Container,
        uint32_t containerGroesse,
        const byteChar *pkcs12Passwort);

    /**
     * @brief Der PIN-Status wird für ein passwortgeschütztes Kryptomittel abgefragt und in @c pinStatus zurückgegeben.
     *
     * Der PIN-Status wird für einen passwortgeschützten Bereich
     * ermittelt, der durch das übergebene Zertifikat-Handle im
     * Parameter @c hToken referenziert wird. Da bei Sicherheitssticks
     * und Signaturkarten durch ein einziges Zertifikat-Handle zwei
     * Schlüsselpaare referenziert werden können (eines für die
     * Signatur und eines für die Verschlüsselung von Daten),
     * muss grundsätzlich der Parameter @c keyType gesetzt werden.
     *
     * Mit dem Rückgabewert der Funktion kann der Endanwender
     * rechtzeitig informiert werden, falls bei einer weiteren
     * falschen PIN-Eingabe das Kryptomittel gesperrt wird. Im
     * Fehlerfall ist @c pinStatus nicht definiert.
     *
     * Der Karten- bzw. Stickhersteller ist verantwortlich,
     * dass seine Implementierung den korrekten PIN-Status
     * zurückgibt, siehe auch
     * Tabelle "PIN-Statusabfrage für POZ" im Unterkap.
     * "Das Portalzertifikat (POZ)" im Dokument
     * @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}.
     *
     * @param[in] hToken
     *      @parblock
     *            Zertifikat-Handle, für dessen passwortgeschützten
     *            Bereich der PIN-Status ermittelt werden soll.
     *
     *            Wird von der Funktion
     *            EricGetHandleToCertificate() zurückgeliefert.
     *      @endparblock
     * @param[out] pinStatus
     *      @parblock
     *            Mögliche Rückgabewerte: @mAbsatz
     *            - 0: StatusPinOk: Kein Fehlversuch oder keine
     *                 Informationen verfügbar
     *            - 1: StatusPinLocked: PIN gesperrt
     *            - 2: StatusPreviousPinError: Die letzte
     *                 PIN-Eingabe war fehlerhaft
     *            - 3: StatusLockedIfPinError: Beim nächsten
     *                 fehlerhaften Versuch wird die PIN gesperrt
     *      @endparblock
     * @param[in] keyType
     *      @parblock
     *            Mögliche Eingabewerte: @mAbsatz
     *            - 0: eSignatureKey: Schlüssel für die Signatur
     *                 von Daten
     *            - 1: eEncryptionKey: Schlüssel für die
     *                 Verschlüsselung von Daten
     *      @endparblock
     * @return
     *         - ::ERIC_OK
     *         - ::ERIC_GLOBAL_NULL_PARAMETER
     *         - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     *         - weitere, siehe eric_fehlercodes.h
     *
     * @see
     *     - EricGetHandleToCertificate()
     *     - @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kap. "Zertifikate und Authentifizierungsverfahren"
     *
     */
    ERICAPI_IMPORT int STDCALL EricGetPinStatus(
        EricZertifikatHandle hToken,
        uint32_t* pinStatus,
        uint32_t keyType);

    /**
     * @brief Es wird der öffentliche Schlüssel als base64-kodierte Zeichenkette
     *        für das übergebene Zertifikat-Handle in @c cryptoParameter zurückgeliefert.
     *        Von den beiden öffentlichen Schlüsseln, die in ELSTER-Zertifikaten enthalten sind,
     *        wird der Verschlüsselungsschlüssel (Encryption Key) zurückgegeben.
     *
     * @param[in] cryptoParameter
     *            Die Struktur enthält das Zertifikat-Handle und die PIN.
     *            Falls der Zugriff auf den öffentlichen Schlüssel keine PIN erfordert,
     *            ist PIN=NULL anzugeben.
     * @param[out] rueckgabePuffer
     *      @parblock
     *              Handle auf den Rückgabepuffer. Bei Erfolg enthält
     *              der Rückgabepuffer den öffentlichen Schlüssel als base64-kodierte Zeichenkette.
     *
     *              Zur Erzeugung, Verwendung und Freigabe von Rückgabepuffern
     *              siehe Dokumentation zu ::EricRueckgabepufferHandle.
     *      @endparblock
     *
     * @return
     *         - ::ERIC_OK
     *         - ::ERIC_GLOBAL_NULL_PARAMETER
     *         - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     *         - ::ERIC_CRYPT_E_INVALID_HANDLE
     *         - ::ERIC_CRYPT_E_P12_ENC_KEY
     *         - ::ERIC_CRYPT_E_PIN_WRONG
     *         - ::ERIC_CRYPT_E_PIN_LOCKED
     *         - weitere, siehe eric_fehlercodes.h
     *
     */
    ERICAPI_IMPORT int STDCALL EricGetPublicKey(
        const eric_verschluesselungs_parameter_t* cryptoParameter,
        EricRueckgabepufferHandle rueckgabePuffer);

    /**
     * @brief  Es wird die Klartextfehlermeldung zu dem @c fehlerkode ermittelt.
     *
     * Die Funktion liefert die Klartextfehlermeldung zu einem
     * ERiC Fehlercode - definiert in eric_fehlercodes.h
     *
     *
     * @param[in] fehlerkode
     *            Eingabe-Fehlercode, definiert in eric_fehlercodes.h.
     * @param[out] rueckgabePuffer
     *      @parblock
     *              Handle auf einen Rückgabepuffer, in den
     *              die Klartextfehlermeldung geschrieben wird.
     *
     *              Zur Erzeugung, Verwendung und Freigabe von Rückgabepuffern
     *              siehe Dokumentation zu ::EricRueckgabepufferHandle.
     *
     *              Die Klartextfehlermeldung ist gemäß UTF-8 kodiert.
     *      @endparblock
     *
     * @return
     *        - ::ERIC_OK
     *        - ::ERIC_GLOBAL_NULL_PARAMETER
     *        - ::ERIC_GLOBAL_FEHLERMELDUNG_NICHT_VORHANDEN
     *        - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     *        - ::ERIC_GLOBAL_UNKNOWN
     */
    ERICAPI_IMPORT int STDCALL EricHoleFehlerText(
        int fehlerkode,
        EricRueckgabepufferHandle rueckgabePuffer);

    /**
     * @brief Es wird die Finanzamtliste für eine bestimmte @c finanzamtLandNummer zurückgegeben.
     *
     * @param[in] finanzamtLandNummer
     *      @parblock
     *              Die Finanzamtlandnummer besteht aus den ersten zwei Stellen der
     *              Bundesfinanzamtsnummer.
     *
     *              Eine Liste aller Finanzamtlandnummern wird
     *              von ::EricHoleFinanzamtLandNummern() zurückgegeben.
     *      @endparblock
     * @param[out] rueckgabeXmlPuffer
     *      @parblock
     *              Handle auf einen Rückgabepuffer, in den
     *              die Ergebnis XML-Daten geschrieben werden.
     *              Die XML-Daten folgen der XML Schema Definition
     *              @lsAPI-Rueckgabe-Schemata{Dokumentation\API-Rueckgabe-Schemata\EricHoleFinanzaemter.xsd}.
     
     *              Zur Erzeugung, Verwendung und Freigabe von Rückgabepuffern
     *              siehe Dokumentation zu ::EricRueckgabepufferHandle.
     *      @endparblock
     *
     * \b Beispiel:
     * \code{.xml}
     * <?xml version="1.0" encoding="UTF-8"?>
     * <EricHoleFinanzaemter xmlns="http://www.elster.de/EricXML/1.0/EricHoleFinanzaemter">
     *     <Finanzamt>
     *       <BuFaNummer>2801</BuFaNummer>
     *       <Name>Finanzamt Offenburg Außenstelle Achern</Name>
     *     </Finanzamt>
     *     <Finanzamt>
     *       <BuFaNummer>2804</BuFaNummer>
     *       <Name>Finanzamt Villingen-Schwenningen Außenstelle Donaueschingen</Name>
     *     </Finanzamt>
     *     (...)
     * </EricHoleFinanzaemter>
     * \endcode
     *
     * @return
     *        - ::ERIC_OK
     *        - ::ERIC_GLOBAL_NULL_PARAMETER
     *        - ::ERIC_GLOBAL_UTI_COUNTRY_NOT_SUPPORTED
     *        - ::ERIC_GLOBAL_COMMONDATA_NICHT_VERFUEGBAR
     *        - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     *        - ::ERIC_GLOBAL_UNKNOWN
     */
    ERICAPI_IMPORT int STDCALL EricHoleFinanzaemter(
        const byteChar* finanzamtLandNummer,
        EricRueckgabepufferHandle rueckgabeXmlPuffer);

    /**
     * @brief Die Liste aller Finanzamtlandnummern wird zurückgegeben.
     *
     * @param[out] rueckgabeXmlPuffer 
     *      @parblock
     *              Handle auf einen Rückgabepuffer, in den
     *              die Ergebnis XML-Daten geschrieben werden.
     *              Die XML-Daten folgen der XML Schema Definition
     *              @lsAPI-Rueckgabe-Schemata{Dokumentation\API-Rueckgabe-Schemata\EricHoleFinanzamtLandNummern.xsd}.
     *
     *              Zur Erzeugung, Verwendung und Freigabe von Rückgabepuffern
     *              siehe Dokumentation zu ::EricRueckgabepufferHandle.
     *     @endparblock
     *
     * \b Beispiel:
     * \code{.xml}
     * <?xml version="1.0" encoding="UTF-8"?>
     * <EricHoleFinanzamtLandNummern xmlns="http://www.elster.de/EricXML/1.0/EricHoleFinanzamtLandNummern">
     *     <FinanzamtLand>
     *       <FinanzamtLandNummer>28</FinanzamtLandNummer>
     *       <Name>Baden-Württemberg</Name>
     *     </FinanzamtLand>
     *     <FinanzamtLand>
     *       <FinanzamtLandNummer>91</FinanzamtLandNummer>
     *       <Name>Bayern (Zuständigkeit LfSt - München)</Name>
     *     </FinanzamtLand>
     *     (...)
     * </EricHoleFinanzamtLandNummern>
     * \endcode
     *
     * @return
     *        - ::ERIC_OK
     *        - ::ERIC_GLOBAL_NULL_PARAMETER
     *        - ::ERIC_GLOBAL_COMMONDATA_NICHT_VERFUEGBAR
     *        - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     *        - ::ERIC_GLOBAL_UNKNOWN
     */
    ERICAPI_IMPORT int STDCALL EricHoleFinanzamtLandNummern(
        EricRueckgabepufferHandle rueckgabeXmlPuffer);

    /**
     * @brief Die @c finanzamtsdaten werden für eine Bundesfinanzamtsnummer zurückgegeben.
     *
     * Die Bundesfinanzamtsnummer kann über die Kombination der Funktionen ::EricHoleFinanzamtLandNummern()
     * und ::EricHoleFinanzaemter() ermittelt werden.
     *
     * @param[in] bufaNr
     *            Übergabe der 4-stelligen Bundesfinanzamtsnummer.
     *
     * @param[out] rueckgabeXmlPuffer
     *      @parblock
     *              Handle auf einen Rückgabepuffer, in den
     *              die Ergebnis XML-Daten geschrieben werden.
     *              Die XML-Daten folgen der XML Schema Definition
     *              @lsAPI-Rueckgabe-Schemata{Dokumentation\API-Rueckgabe-Schemata\EricHoleFinanzamtsdaten.xsd}.
     *
     *              Zur Erzeugung, Verwendung und Freigabe von Rückgabepuffern
     *              siehe Dokumentation zu ::EricRueckgabepufferHandle.
     *      @endparblock
     *
     * @return
     *        - ::ERIC_OK
     *        - ::ERIC_GLOBAL_NULL_PARAMETER: Parameter @c bufaNr ist NULL.
     *        - ::ERIC_GLOBAL_PRUEF_FEHLER: Die übergebene Bundesfinanzamtsnummer ist keine Ganzzahl.
     *        - ::ERIC_GLOBAL_KEINE_DATEN_VORHANDEN: Immer bei Testfinanzämtern.
     *        - ::ERIC_GLOBAL_COMMONDATA_NICHT_VERFUEGBAR
     *        - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     *        - ::ERIC_GLOBAL_UNKNOWN
     *
     * @see
     *    - ::EricHoleFinanzamtLandNummern()
     *    - ::EricHoleFinanzaemter()
     */
    ERICAPI_IMPORT int STDCALL EricHoleFinanzamtsdaten(
        const byteChar bufaNr[5],
        EricRueckgabepufferHandle rueckgabeXmlPuffer);

    /**
     * @brief Die Testfinanzamtliste wird in @c rueckgabeXmlPuffer zurückgegeben.
     *
     * @param[out] rueckgabeXmlPuffer
     *      @parblock
     *              Handle auf einen Rückgabepuffer, in den
     *              die Ergebnis XML-Daten geschrieben werden.
     *              Die XML-Daten folgen der XML Schema Definition
     *              @lsAPI-Rueckgabe-Schemata{Dokumentation\API-Rueckgabe-Schemata\EricHoleTestfinanzaemter.xsd}.
     *
     *              Zur Erzeugung, Verwendung und Freigabe von Rückgabepuffern
     *              siehe Dokumentation zu ::EricRueckgabepufferHandle.
     *      @endparblock
     *
     * \b Beispiel:
     * \code{.xml}
     * <?xml version="1.0" encoding="UTF-8"?>
     * <EricHoleTestfinanzaemter xmlns="http://www.elster.de/EricXML/1.0/EricHoleTestfinanzaemter">
     *   <Finanzamt>
     *       <BuFaNummer>1096</BuFaNummer>
     *       <Name>Testfinanzamt Saarland</Name>
     *     </Finanzamt>
     *     <Finanzamt>
     *       <BuFaNummer>1097</BuFaNummer>
     *       <Name>Finanzschule (Edenkoben)</Name>
     *     </Finanzamt>
     *     (...)
     * </EricHoleTestfinanzaemter>
     * \endcode
     *
     * @return
     *        - ::ERIC_OK
     *        - ::ERIC_GLOBAL_NULL_PARAMETER
     *        - ::ERIC_GLOBAL_COMMONDATA_NICHT_VERFUEGBAR
     *        - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     *        - ::ERIC_GLOBAL_UNKNOWN
     */
    ERICAPI_IMPORT int STDCALL EricHoleTestfinanzaemter(
        EricRueckgabepufferHandle rueckgabeXmlPuffer);

    /**
     * @brief Die Eigenschaften des übergebenen Zertifikats werden im @c rueckgabeXmlPuffer zurückgegeben.
     *
     * @param[in] hToken Handle des Zertifikats, dessen Eigenschaften geholt werden sollen.
     *            Wird von der Funktion EricGetHandleToCertificate() zurückgeliefert.
     * @param[in] pin PIN zum Öffnen des Zertifikats. Wird bei Software-Portalzertifikaten
     *            benötigt.
     * @param[out] rueckgabeXmlPuffer 
     *      @parblock
     *              Handle auf einen Rückgabepuffer, in den die Zertifikateigenschaften
     *              im XML-Format geschrieben werden. Das Format ist im XML Schema
     *              @lsAPI-Rueckgabe-Schemata{Dokumentation\API-Rueckgabe-Schemata\EricHoleZertifikatEigenschaften.xsd}
     *              definiert.
     *
     *              Zur Erzeugung, Verwendung und Freigabe von Rückgabepuffern
     *              siehe Dokumentation zu ::EricRueckgabepufferHandle.
     *      @endparblock
     * @note       Bei einem ELSTER-Softwarezertifikat (.pfx) steht im Common Name (CN) die ID des ELSTER-Kontos,
     *             für das das Zertifikat ausgestellt wurde.
     *             Die Konto-ID kann beispielsweise dafür genutzt werden, bei einer Zertifikatsverlängerung
     *             das verlängerte Zertifikat dem alten Zertifikat zuzuordnen.
     *
     * \b Beispiel:
     * \code{.xml}
     * <EricHoleZertifikatEigenschaften xmlns="http://www.elster.de/EricXML/2.0/EricHoleZertifikatEigenschaften">
     *   <Signaturzertifikateigenschaften>
     *       <AusgestelltAm>220817152116Z</AusgestelltAm>
     *       <GueltigBis>230817152116Z</GueltigBis>
     *       <Signaturalgorithmus>sha1WithRSAEncryption(1.2.840.113549.1.1.5)</Signaturalgorithmus>
     *       <PublicKeyMD5>6b8b191936677957fe74103198e77f4e</PublicKeyMD5>
     *       <PublicKeySHA1>884b0dfe2e10221a2aedd28c986cf34db0f1d932</PublicKeySHA1>
     *       <PublicKeyBitLength>2048</PublicKeyBitLength>
     *       <Issuer>
     *           <Info><Name>CN</Name><Wert>ElsterSoftCA</Wert></Info>
     *           <Info><Name>OU</Name><Wert>CA</Wert></Info>
     *           (...)
     *       </Issuer>
     *       <Subjekt>
     *           <Info><Name>CN</Name><Wert>1000872896</Wert></Info>
     *       </Subjekt>
     *       <Identifikationsmerkmaltyp>Steuernummer</Identifikationsmerkmaltyp>
     *       <Registrierertyp>Person</Registrierertyp>
     *       <Verifikationsart>Postweg</Verifikationsart>
     *       <TokenTyp>Software</TokenTyp>
     *       <Testzertifikat>true</Testzertifikat>
     *   </Signaturzertifikateigenschaften>
     *   <Verschluesselungszertifikateigenschaften>
     *       (...)
     *   </Verschluesselungszertifikateigenschaften>
     * </EricHoleZertifikatEigenschaften>
     * \endcode
     *
     * @return
     *      - ::ERIC_OK
     *      - ::ERIC_GLOBAL_NULL_PARAMETER
     *      - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     *      - ::ERIC_GLOBAL_UNKNOWN
     *      - ERIC_CRYPT_E_*: Ein Zertifikatsfehler aus dem Statuscodebereich
     *                        von ::ERIC_CRYPT_E_INVALID_HANDLE = 610201101 bis 610201212
     *
     * @see
     *      - @lsAPI-Rueckgabe-Schemata{Dokumentation\API-Rueckgabe-Schemata\EricHoleZertifikatEigenschaften.xsd}
     *      - @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kap. "Verwendung von EricHoleZertifikatEigenschaften()"             
     *
     */
    ERICAPI_IMPORT int STDCALL EricHoleZertifikatEigenschaften(
        EricZertifikatHandle hToken,
        const byteChar * pin,
        EricRueckgabepufferHandle rueckgabeXmlPuffer);

    /**
     * @brief  Der Fingerabdruck und dessen Signatur wird für das übergebene
     *         Zertifikat zurückgegeben.
     *
     * Zur Erzeugung, Verwendung und Freigabe von Rückgabepuffern siehe Dokumentation
     * zu ::EricRueckgabepufferHandle.
     *
     * @param[in] cryptoParameter Zertifikatsdaten,
     *            siehe eric_verschluesselungs_parameter_t.
     *            Das in der übergebenen Struktur referenzierte Zertifikat muss
     *            ein clientseitig erzeugtes Zertifikat (CEZ) sein.
     * @param[out] fingerabdruckPuffer Handle auf einen Rückgabepuffer, in
     *            den der Fingerabdruck geschrieben wird, siehe
     *            ::EricRueckgabepufferHandle.
     * @param[out] signaturPuffer Handle auf einen Rückgabepuffer, in den
     *            die Signatur des Fingerabdrucks geschrieben wird, siehe
     *            ::EricRueckgabepufferHandle.
     *
     * @note Die Erzeugung eines Fingerabdrucks mit dieser Funktion ist nur
     *       in Zusammenhang mit clientseitig erzeugten Zertifikaten definiert.
     *
     * @return
     * - ::ERIC_OK
     * - ::ERIC_GLOBAL_NULL_PARAMETER
     * - ::ERIC_GLOBAL_PUFFER_ZUGRIFFSKONFLIKT
     * - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     * - ::ERIC_GLOBAL_UNKNOWN
     * - ::ERIC_CRYPT_E_P12_READ
     * - ::ERIC_CRYPT_E_P12_DECODE
     * - ::ERIC_CRYPT_E_PIN_WRONG
     * - ::ERIC_CRYPT_E_P12_SIG_KEY
     * - ::ERIC_CRYPT_E_P12_ENC_KEY
     * - ::ERIC_CRYPT_ZERTIFIKAT
     * - ::ERIC_CRYPT_EIDKARTE_NICHT_UNTERSTUETZT
     * - ::ERIC_CRYPT_SIGNATUR
     * - ::ERIC_CRYPT_CORRUPTED
     */
    ERICAPI_IMPORT int STDCALL EricHoleZertifikatFingerabdruck(
        const eric_verschluesselungs_parameter_t* cryptoParameter,
        EricRueckgabepufferHandle fingerabdruckPuffer,
        EricRueckgabepufferHandle signaturPuffer);

    /**
     * @brief Initialisiert den Singlethreading-ERiC
     *
     * Vor der Verwendung der Singlethreading-API muss ::EricInitialisiere()
     * aufgerufen werden.
     *
     * Mehrfache Aufrufe dieser Funktion, ohne das zwischendurch
     * ::EricBeende() aufgerufen worden ist, führen dazu, dass der
     * Fehlercode ::ERIC_GLOBAL_MEHRFACHE_INITIALISIERUNG zurückgegeben
     * wird. Der zuvor initialisierte Singlethreading-ERiC bleibt davon
     * aber unberührt und ist weiterhin in einem gültigen Zustand.
     *
     * @param[in] pluginPfad Pfad, in dem die Plugins rekursiv gesucht werden.
     *                       Ist der Zeiger gleich NULL, wird der Pfad zur
     *                       Bibliothek ericapi verwendet.
     * @param[in] logPfad Optionaler Pfad zur Log-Datei eric.log. Ist der
     *                    Wert gleich NULL, wird das betriebssystemspezifische
     *                    Verzeichnis für temporäre Dateien verwendet.
     *
     * @note
     *     @parblock
     *             Kann kein eric.log angelegt werden, wird eine entsprechende
     *             Fehlermeldung auf die Konsole (stderr) geschrieben und an den
     *             Windows-Ereignisdienst bzw. den syslogd-Dienst (Linux, AIX, macOS)
     *             geschickt.
     *
     *             Für Linux, AIX und macOS ist zu beachten, dass der syslogd-Dienst
     *             gegebenenfalls erst noch zu aktivieren und für die Protokollierung
     *             von Meldungen der Facility "User" zu konfigurieren ist.
     *
     *             Suchkriterien für ERiC-Meldungen in der Windows-Ereignisansicht
     *             sind "ERiC (Elster Rich Client)" als Quelle und "Anwendung"
     *             als Protokoll.
     *
     *             Suchkriterien für ERiC-Meldungen in den Systemlogdateien
     *             unter Linux, AIX und macOS sind die Facility "User" und
     *             der Ident "ERiC (Elster Rich Client)".
     *      @endparblock
     *
     * @return
     *             - ::ERIC_OK
     *             - ::ERIC_GLOBAL_MEHRFACHE_INITIALISIERUNG
     *             - ::ERIC_GLOBAL_FEHLER_INITIALISIERUNG
     *             - ::ERIC_GLOBAL_LOG_EXCEPTION
     *
     * @see
     *      - ::EricBeende()
     */
    ERICAPI_IMPORT int STDCALL EricInitialisiere(
        const byteChar *pluginPfad,
        const byteChar *logPfad);


    /**
     * @brief Es wird eine Steuernummer im ELSTER-Steuernummerformat erzeugt.
     *
     * Die Funktion erzeugt aus einer angegebenen Steuernummer
     * im Format des Steuerbescheides eine 13-stellige
     * Steuernummer im ELSTER-Steuernummerformat.<br>
     *
     * Die sich ergebende 13-stellige Steuernummer im
     * ELSTER-Steuernummerformat wird von der Funktion
     * ::EricMakeElsterStnr() auch auf Gültigkeit geprüft.<br>
     *
     * Einer der beiden Parameter @c landesnr oder @c bundesfinanzamtsnr muss
     * korrekt angegeben werden. Der jeweils andere Parameter darf NULL oder leer
     * sein. Bei bayerischen und berliner Steuernummern im Format BBB/UUUUP ist die
     * Angabe der Bundesfinanzamtsnummer zwingend erforderlich.
     *
     * @param[in]  steuernrBescheid
     *             Format der Steuernummer wie auch auf amtlichen
     *             Schreiben angegeben.
     * @param[in]  landesnr
     *             2-stellige Landesnummer (entspricht den ersten
     *             zwei Stellen der Bundesfinanzamtsnummer).
     * @param[in]  bundesfinanzamtsnr
     *             4-stellige Bundesfinanzamtsnummer.
     * @param[out] steuernrPuffer
     *      @parblock
     *              Handle auf einen Rückgabepuffer, in den
     *              die Steuernummer im ELSTER-Steuernummerformat geschrieben wird.
     *
     *              Zur Erzeugung, Verwendung und Freigabe von Rückgabepuffern
     *              siehe Dokumentation zu ::EricRueckgabepufferHandle.
     *      @endparblock
     *
     * @return
     *  - ::ERIC_OK
     *  - ::ERIC_GLOBAL_STEUERNUMMER_UNGUELTIG
     *  - ::ERIC_GLOBAL_LANDESNUMMER_UNBEKANNT
     *  - ::ERIC_GLOBAL_NULL_PARAMETER
     *  - ::ERIC_GLOBAL_UNGUELTIGER_PARAMETER
     *  - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     *  - ::ERIC_GLOBAL_UNKNOWN
     */
    ERICAPI_IMPORT int STDCALL EricMakeElsterStnr(
        const byteChar* steuernrBescheid,
        const byteChar landesnr[2+1],
        const byteChar bundesfinanzamtsnr[4+1],
        EricRueckgabepufferHandle steuernrPuffer);

    /**
     * @brief Konvertiert ein Einheitswert-Aktenzeichen in das ELSTER-Format
     *
     * Konvertiert ein gültiges Einheitswert-Aktenzeichen in einem landesspezifischen Bescheidformat (z.B. 208/035-3-03889.3)
     * unter Angabe des Landeskürzels in ein Einheitswert-Aktenzeichen im ELSTER-Format (z.B. 520840353038893).
     * 
     * @param[in] ewAzBescheid 
     *            Zeiger auf das Einheitswert-Aktenzeichen in einem landesspezifischen Bescheidformat.
     * @param[in] landeskuerzel
     *            Zeiger auf das Landeskürzel (zum Beispiel BY für Bayern)
     * @param[out] ewAzElsterPuffer Handle auf einen Rückgabepuffer, in den 
     *             das erzeugte Einheitswert-Aktenzeichen im ELSTER-Format geschrieben wird.
     *
     * @return
     *  - ::ERIC_OK
     *  - ::ERIC_GLOBAL_EWAZ_UNGUELTIG
     *  - ::ERIC_GLOBAL_EWAZ_LANDESKUERZEL_UNBEKANNT
     *  - ::ERIC_GLOBAL_NULL_PARAMETER
     *  - ::ERIC_GLOBAL_UNGUELTIGER_PARAMETER
     *  - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     *  - ::ERIC_GLOBAL_UNKNOWN
     *
     * @see
     *     - Landeskürzel siehe ISO-3166-2
     */
    ERICAPI_IMPORT int STDCALL EricMakeElsterEWAz(
        const byteChar *ewAzBescheid,
        const byteChar *landeskuerzel,
        EricRueckgabepufferHandle ewAzElsterPuffer);

    /**
     * @brief Die @c bic wird auf Gültigkeit überprüft.
     *
     * Die Prüfung erfolgt in zwei Schritten: @mAbsatz
     * -# Formale Prüfung auf gültige Zeichen und richtige Länge.
     * -# Prüfung, ob das Länderkennzeichen für BIC gültig ist.
     *
     * Falls die BIC ungültig ist liefert die Funktion EricHoleFehlerText()
     * den zugehörigen Fehlertext.
     *
     * @param[in] bic Zeiger auf eine NULL-terminierte Zeichenkette.
     *
     * @return
     *  - ::ERIC_OK
     *  - ::ERIC_GLOBAL_BIC_FORMALER_FEHLER: Ungültige Zeichen, falsche Länge.
     *  - ::ERIC_GLOBAL_BIC_LAENDERCODE_FEHLER
     *  - ::ERIC_GLOBAL_NULL_PARAMETER: Parameter @c bic ist NULL.
     *  - ::ERIC_GLOBAL_COMMONDATA_NICHT_VERFUEGBAR
     *  - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     *  - ::ERIC_GLOBAL_UNKNOWN
     *
     * @see
     *      - @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kap. "BIC: ISO-Ländercodes"
     *      - @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kap. "BIC-Prüfung"
     */
    ERICAPI_IMPORT int STDCALL EricPruefeBIC(
        const byteChar* bic);

    /**
     * @brief Die @c iban wird auf Gültigkeit überprüft.
     *
     * Die Prüfung erfolgt in vier Schritten: @mAbsatz
     * -# Formale Prüfung auf gültige Zeichen und richtige Länge.
     * -# Prüfung, ob das Länderkennzeichen für IBAN gültig ist.
     * -# Prüfung, ob das länderspezifische Format gültig ist.
     * -# Prüfung, ob die Prüfziffer der IBAN gültig ist.
     *
     * Falls die IBAN ungültig ist, liefert die Funktion EricHoleFehlerText()
     * den zugehörigen Fehlertext.
     *
     * @param[in] iban Zeiger auf eine NULL-terminierte Zeichenkette.
     *
     * @return
     *  - ::ERIC_OK
     *  - ::ERIC_GLOBAL_IBAN_FORMALER_FEHLER: Ungültige Zeichen, falsche Länge.
     *  - ::ERIC_GLOBAL_IBAN_LAENDERCODE_FEHLER
     *  - ::ERIC_GLOBAL_IBAN_LANDESFORMAT_FEHLER
     *  - ::ERIC_GLOBAL_IBAN_PRUEFZIFFER_FEHLER
     *  - ::ERIC_GLOBAL_NULL_PARAMETER: Parameter @c iban ist NULL.
     *  - ::ERIC_GLOBAL_COMMONDATA_NICHT_VERFUEGBAR
     *  - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     *  - ::ERIC_GLOBAL_UNKNOWN
     *
     * @see
     *      - @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kap. "IBAN: Länderspezifische Formate"
     *      - @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kap. "IBAN-Prüfung"
     *
     */
    ERICAPI_IMPORT int STDCALL EricPruefeIBAN(
        const byteChar* iban);

    /**
     * @brief Überprüft ein @c Einheitswert-Aktenzeichen im ELSTER-Format auf Gültigkeit.
     *
     * @param[in] einheitswertAz
     *            Zeiger auf ein Einheitswert-Aktenzeichen im ELSTER-Format
     *
     * @return
     *  - ::ERIC_OK
     *  - ::ERIC_GLOBAL_NULL_PARAMETER
     *  - ::ERIC_GLOBAL_EWAZ_UNGUELTIG
     *  - ::ERIC_GLOBAL_COMMONDATA_NICHT_VERFUEGBAR
     *  - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     *  - ::ERIC_GLOBAL_UNKNOWN
     *
     */
    ERICAPI_IMPORT int STDCALL EricPruefeEWAz(
        const byteChar* einheitswertAz);

    /**
     * @brief Die @c steuerId wird auf Gültigkeit überprüft.
     *
     * @param[in] steuerId
     *            Steuer-Identifikationsnummer (IdNr)
     *
     * @return
     *  - ::ERIC_OK
     *  - ::ERIC_GLOBAL_NULL_PARAMETER
     *  - ::ERIC_GLOBAL_IDNUMMER_UNGUELTIG
     *  - ::ERIC_GLOBAL_COMMONDATA_NICHT_VERFUEGBAR
     *  - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     *  - ::ERIC_GLOBAL_UNKNOWN
     *
     * @see
     *         - EricPruefeSteuernummer()
     *         - @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kap. "Prüfung der Steueridentifikationsnummer (IdNr.)"
     *         - @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kap. "Test-Steueridentifikationsnummer"
     */
    ERICAPI_IMPORT int STDCALL EricPruefeIdentifikationsMerkmal(
        const byteChar* steuerId);

    /**
     * @brief Die @c steuernummer wird einschließlich Bundesfinanzamtsnummer
     *        auf formale Richtigkeit geprüft.
     *
     * Zur Prüfung der Bundesfinanzamtsnummer wird
     * ::EricPruefeBuFaNummer() verwendet.
     *
     * Zur Erzeugung, Verwendung und Freigabe von Rückgabepuffern siehe Dokumentation
     * zu ::EricRueckgabepufferHandle.
     *
     * @param[in] steuernummer NULL-terminierte 13-stellige Steuernummer im
     *            ELSTER-Steuernummernformat.
     *
     * @return
     *  - ::ERIC_OK
     *  - ::ERIC_GLOBAL_NULL_PARAMETER
     *  - ::ERIC_GLOBAL_STEUERNUMMER_UNGUELTIG
     *  - ::ERIC_GLOBAL_COMMONDATA_NICHT_VERFUEGBAR
     *  - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     *  - ::ERIC_GLOBAL_UNKNOWN
     *
     * @see
     *         - EricPruefeBuFaNummer()
     *         - Pruefung_der_Steuer_und_Steueridentifikatsnummer.pdf, siehe \linkExt{https://www.elster.de/elsterweb/entwickler/infoseite/schnittstellenbeschreibungen,Entwicklerbereich} bei \linkExt{https://www.elster.de/eportal/start,ELSTER}.
     */
    ERICAPI_IMPORT int STDCALL EricPruefeSteuernummer(
        const byteChar* steuernummer);

    /**
     * @brief Die @c Wirtschafts-Identifikationsnummer (@c W-IdNr.) wird auf formale Gültigkeit überprüft.
     *
     * @param[in] wIdNr
     *             NULL-terminierte Wirtschafts-Identifikationsnummer
     *             mit oder ohne Unterscheidungsmerkmal.
     *
     * @return
     *  - ::ERIC_OK
     *  - ::ERIC_GLOBAL_NULL_PARAMETER
     *  - ::ERIC_GLOBAL_IDNUMMER_UNGUELTIG
     *  - ::ERIC_GLOBAL_COMMONDATA_NICHT_VERFUEGBAR
     *  - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     *  - ::ERIC_GLOBAL_UNKNOWN
     *
     * @see
     *         - @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kap. "Prüfung der Wirtschafts-Identifikationsnummer (W-IdNr.)"
     */
    ERICAPI_IMPORT int STDCALL EricPruefeWIdNr(
        const byteChar* wIdNr);
    
    /**
     * @brief Prüft, ob die @c pin zum Zertifikat @c pathToKeystore passt.
     *        Nicht anwendbar auf Ad Hoc-Zertifikate (AHZ), die für einen
     *        neuen Personalausweis (nPA) ausgestellt sind.
     *
     * @param[in] pathToKeystore
     *      @parblock
     *              Folgende Zertifikatstypen werden unterstützt: @mAbsatz
     *              1. Clientseitig erzeugtes Zertifikat: @mLB<a>Pfad
     *                zum Verzeichnis, in dem sich die Zertifikats-Datei (.cer)
     *                und die Datei mit dem privaten Schlüssel (.p12) befinden.
     *                Diese Kryptomittel wurden mit EricCreateKey() erzeugt.
     *                Der Pfad zum Verzeichnis ist bei clientseitig erzeugten
     *                Zertifikaten relativ zum aktuellen Arbeitsverzeichnis oder absolut
     *                anzugeben.
     *              2. Software-Portalzertifikat: @mLB<a>Pfad
     *                zur Software-Zertifikatsdatei (i.d.R. mit der Endung .pfx).
     *                Der Pfad zur Datei ist bei Software-Zertifikaten relativ zum
     *                aktuellen Arbeitsverzeichnis oder absolut anzugeben.
     *              3. Sicherheitsstick: @mLB<a>Pfad
     *                zur Treiberdatei, siehe (2). Bitte beachten, dass der Treiber
     *                betriebssystemabhängig sein kann. Weitere Informationen in der
     *                Anleitung zum Sicherheitsstick oder unter
     *                \linkExt{https://www.sicherheitsstick.de,https://www.sicherheitsstick.de}.
     *              4. Signaturkarte: @mLB<a>Pfad
     *                zur Treiberdatei, welcher einen Zugriff auf die
     *                Signaturkarte ermöglicht, siehe (2). Weitere Informationen in
     *                der Anleitung zur Signaturkarte.
     *      @endparblock
     * @param[in] pin
     *            PIN für den Zugriff auf den privaten Schlüssel des Zertifikats.
     * @param[in] keyType
     *      @parblock
     *              Mögliche Eingabewerte: @mAbsatz
     *                - 0: eSignatureKey: Schlüssel für die Signatur von Daten, siehe (1).
     *                - 1: eEncryptionKey: Schlüssel für die Verschlüsselung von Daten, siehe (1).
     *      @endparblock
     *                 
     * (1) Bei einem Zertifikat wie dem mit EricCreateKey() clientseitig
     * erzeugten Zertifikat (CEZ), das nur einen einzigen, gemeinsamen Schlüssel
     * für Signatur und Verschlüsselung besitzt, sind beide Eingabewerte
     * erlaubt. Die Werte beziehen sich dann beide auf denselben Schlüssel.
     *
     *  (2) Bei Sicherheitssticks und Signaturkarten ist bei der Angabe
     *  des Treibers der Suchmechanismus nach dynamischen Modulen des
     *  jeweiligen Betriebssystems zu berücksichtigen. Weitere
     *  Informationen sind z.B. unter Windows der Dokumentation der
     *  <tt>LoadLibrary()</tt> oder unter Linux und macOS der Dokumentation der
     *  <tt>dlopen()</tt> zu entnehmen.
     *
     *  Pfade müssen auf Windows in der für Datei-Funktionen benutzten ANSI-Codepage,
     *  auf Linux, AIX und Linux Power in der für das Dateisystem benutzten Locale
     *  und auf macOS in der "decomposed form" von UTF-8 übergeben werden.
     *  Bitte weitere Betriebssystemspezifika bzgl. nicht erlaubter Zeichen in
     *  Pfaden und Pfadtrennzeichen beachten.
     *
     *  Für Details zu Pfaden im ERiC siehe @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kapitel
     *  "Übergabe von Pfaden an ERiC API-Funktionen".
     *
     *  Es wird empfohlen, geöffnete Zertifikatshandle zu schließen, bevor mit
     *  der API-Funktion EricPruefeZertifikatPin() das gewünschte Zertifikat geprüft wird.
     *
     *  @note Eine falsche PIN-Eingabe erhöht bei Sicherheitsstick und Signaturkarte den
     *        Zähler für Fehlversuche. Welche Zertifikatstypen aufgrund von 3 Fehlversuchen
     *        gesperrt werden, ist im @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kap.
     *        "Das Portalzertifikat (POZ)" beschrieben.
     *
     * @return
     *  - ::ERIC_OK
     *  - ::ERIC_CRYPT_E_PIN_WRONG
     *  - ::ERIC_CRYPT_NICHT_UNTERSTUETZTES_PSE_FORMAT
     *  - ::ERIC_CRYPT_EIDKARTE_NICHT_UNTERSTUETZT
     *  - ::ERIC_CRYPT_E_PSE_PATH
     *  - ::ERIC_GLOBAL_NULL_PARAMETER
     *  - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     *  - ::ERIC_GLOBAL_UNKNOWN
     */
    ERICAPI_IMPORT int STDCALL EricPruefeZertifikatPin(
        const byteChar *pathToKeystore,
        const byteChar *pin,
        uint32_t keyType);

    /**
     * @brief Die @c funktion wird als Callback-Funktion für
     *        ::EricBearbeiteVorgang() registriert.
     *
     * Die registrierte Callback-Funktion wird von der Funktion
     * ::EricBearbeiteVorgang() aufgerufen, um bei der Verarbeitung
     * den Fortschritt der einzelnen Arbeitsbereiche anzuzeigen.
     *
     * @param[in] funktion      Zeiger auf die zu registrierende Funktion oder \c NULL
     * @param[in] benutzerdaten Zeiger, der der registrierten Funktion immer
     *                          mitgegeben wird. Die Anwendung kann diesen Parameter
     *                          dazu verwenden, einen Zeiger auf eigene Daten oder
     *                          Funktionen an die zu registrierende Funktion
     *                          übergeben zu lassen.
     *
     * @return
     *  - ::ERIC_OK
     *  - ::ERIC_GLOBAL_UNGUELTIGER_PARAMETER
     *  - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     *  - ::ERIC_GLOBAL_UNKNOWN
     *
     * @remark
     *         - Wenn eine zuvor registrierte Funktion nicht mehr aufgerufen
     *           werden soll, ist ::EricRegistriereFortschrittCallback() mit dem
     *           Wert \c NULL im Parameter \c funktion aufzurufen.
     *         - Es ist nicht erlaubt eine ERiC API-Funktion aus einer Callback-Funktion aufzurufen.
     *         - Die Verarbeitung im Callback findet synchron statt.
     *           Deshalb sollte der Callback sehr schnell ausgeführt werden.
     *
     * @see
     *         - EricBearbeiteVorgang()
     *         - EricFortschrittCallback
     *         - @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kap. "Funktionen für Fortschrittcallbacks"
     *
     */
    ERICAPI_IMPORT int STDCALL EricRegistriereFortschrittCallback(
        EricFortschrittCallback funktion,
        void* benutzerdaten);

    /**
     * @brief Die registrierte @c funktion wird als Callback-Funktion
     *        von ::EricBearbeiteVorgang() aufgerufen und zeigt den
     *        Gesamtfortschritt der Verarbeitung an.
     *
     * @param[in] funktion      Zeiger auf die zu registrierende Funktion oder \c NULL
     * @param[in] benutzerdaten Zeiger, der der registrierten Funktion immer
     *                          mitgegeben wird. Die Anwendung kann diesen Parameter
     *                          dazu verwenden, einen Zeiger auf eigene Daten oder
     *                          Funktionen an die zu registrierende Funktion
     *                          übergeben zu lassen.
     *
     * @return
     *  - ::ERIC_OK
     *  - ::ERIC_GLOBAL_UNGUELTIGER_PARAMETER
     *  - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     *  - ::ERIC_GLOBAL_UNKNOWN
     *
     * @remark
     *         - Wenn eine zuvor registrierte Funktion nicht mehr aufgerufen
     *           werden soll, ist ::EricRegistriereGlobalenFortschrittCallback()
     *           mit dem Wert \c NULL im Parameter \c funktion aufzurufen.
     *         - Es ist nicht erlaubt eine ERiC API-Funktion aus einer
     *           Callback-Funktion aufzurufen.
     *         - Die Verarbeitung im Callback findet synchron statt.
     *           Deshalb sollte der Callback sehr schnell ausgeführt werden.
     *
     * @see
     *         - EricBearbeiteVorgang()
     *         - @typeDokumentation{ERiC-Entwicklerhandbuch.pdf}, Kap. "Funktionen für Fortschrittcallbacks"
     */
    ERICAPI_IMPORT int STDCALL EricRegistriereGlobalenFortschrittCallback(
        EricFortschrittCallback funktion,
        void* benutzerdaten);

    /**
     * @brief Die registrierte @c funktion wird als Callback-Funktion für
     *        jede Lognachricht aufgerufen.
     *        Die Ausgabe entspricht einer Zeile im eric.log.
     *
     * @param[in] funktion Zeiger auf die zu registrierende Funktion oder NULL.
     * @param[in] schreibeEricLogDatei
     *      @parblock
     *              Log-Nachrichten im eric.log: @mAbsatz
     *              - \c 1  Jede Log-Nachricht wird nach eric.log geschrieben.
     *                      Der Parameter \c funktion kann auf eine
     *                      Funktion zeigen oder \c NULL sein.
     *              - \c 0  Falls \c funktion \c != \c NULL werden keine Log-Nachrichten
     *                      nach eric.log geschrieben, andernfalls werden die
     *                      Log-Nachrichten nach eric.log geschrieben.
     *      @endparblock
     * @param[in] benutzerdaten
     *      @parblock
     *              Zeiger, welcher der registrierten Funktion immer
     *              mitgegeben wird.
     *
     *              Die Anwendung kann diesen Parameter
     *              dazu verwenden, einen Zeiger auf eigene Daten oder
     *              Funktionen an die zu registrierende Funktion
     *              übergeben zu lassen.
     *      @endparblock
     *
     * @return
     *  - ::ERIC_OK
     *  - ::ERIC_GLOBAL_UNGUELTIGER_PARAMETER
     *  - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     *  - ::ERIC_GLOBAL_UNKNOWN
     *
     * @remark
     *         - Wenn eine zuvor registrierte Funktion nicht mehr aufgerufen
     *           werden soll, ist ::EricRegistriereLogCallback() mit dem Wert
     *           \c NULL im Parameter \c funktion aufzurufen (=Deregistrierung).
     *         - Vor dem Beenden der Steueranwendung ist eine registrierte
     *           Funktion zu deregistrieren, da es sonst zu einem Absturz
     *           kommen kann.
     *         - Es ist nicht erlaubt eine ERiC API-Funktion aus einer
     *           Callback-Funktion aufzurufen.
     *         - Die Verarbeitung im Callback findet synchron statt.
     *           Deshalb sollte der Callback sehr schnell ausgeführt werden.
     *
     */
    ERICAPI_IMPORT int STDCALL EricRegistriereLogCallback(
        EricLogCallback funktion,
        uint32_t schreibeEricLogDatei,
        void* benutzerdaten);

    /**
     * @brief Diese API-Funktion erzeugt einen Rückgabepuffer und gibt
     *        ein Handle darauf zurück.
     *
     * Die von dieser Funktion erzeugten Rückgabepuffer werden verwendet, um
     * die Ausgaben von ERiC-Funktionen (z.B. EricBearbeiteVorgang())
     * aufzunehmen. Dazu wird das Rückgabepuffer-Handle für den Schreibvorgang
     * an die ausgebende Funktion übergeben.
     *
     * Zum Auslesen des von den API-Funktionen beschriebenen Puffers wird das
     * Rückgabepuffer-Handle an EricRueckgabepufferInhalt() übergeben.
     * Ein einmal erzeugtes Rückgabepuffer-Handle kann für weitere nachfolgende
     * Aufrufe von ERiC API-Funktionen wiederverwendet werden. Bei einer
     * Wiederverwendung eines Handles werden frühere Inhalte überschrieben.
     * Nach Verwendung muss jeder Rückgabepuffer mit
     * EricRueckgabepufferFreigeben() freigegeben werden.
     *
     * Rückgabepuffer sind der Singlethreading-API bzw. einer ERiC-Instanz der
     * Multithreading-API fest zugeordnet. Die Funktionen der ERiC API, die
     * einen Rückgabepuffer entgegennehmen, geben den Fehlercode
     * ::ERIC_GLOBAL_PUFFER_UNGLEICHER_INSTANZ zurück, wenn der übergebene
     * Rückgabepuffer: @mAbsatz
     *      - mit der Singlethreading-API erzeugt worden ist und dann mit der
     *        Multithreading-API verwendet wird.
     *      - mit der Multithreading-API erzeugt worden ist und dann mit der
     *        Singlethreading-API verwendet wird.
     *      - mit einer ERiC-Instanz erzeugt worden ist und dann mit einer
     *        anderen Instanz verwendet wird.
     *
     *
     * @return
     *         - ::EricRueckgabepufferHandle im Erfolgsfall.
     *         - NULL im Fehlerfall.
     *
     * @see
     *         - EricRueckgabepufferLaenge()
     *         - EricRueckgabepufferInhalt()
     *         - EricRueckgabepufferFreigeben()
     */
    ERICAPI_IMPORT EricRueckgabepufferHandle STDCALL EricRueckgabepufferErzeugen(
        void);

    /**
     * @brief Der durch das @c handle bezeichnete Rückgabepuffer wird
     *        freigegeben.
     *
     * Das Handle darf danach nicht weiter verwendet werden. Es wird daher
     * empfohlen, Handle-Variablen nach der Freigabe explizit auf
     * NULL zu setzen.
     *
     * @param[in] handle Handle auf einen mit EricRueckgabepufferErzeugen().
     *            angelegten Rückgabepuffer. Dieser Rückgabepuffer darf nicht
     *            bereits freigegeben worden sein.
     *
     * @return
     *  - ::ERIC_OK
     *  - ::ERIC_GLOBAL_UNGUELTIGER_PARAMETER
     *  - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     *  - ::ERIC_GLOBAL_UNKNOWN
     *
     * @see
     *         - EricRueckgabepufferErzeugen()
     *         - EricRueckgabepufferLaenge()
     *         - EricRueckgabepufferInhalt()
     */
    ERICAPI_IMPORT int STDCALL EricRueckgabepufferFreigeben(
        EricRueckgabepufferHandle handle);

    /**
     * @brief Der durch das @c handle bezeichnete Inhalt des Rückgabepuffers wird zurückgegeben.
     *
     * Der zurückgegebene Zeiger verweist auf ein Byte-Array, das alle in
     * den Rückgabepuffer geschriebenen Bytes sowie eine abschließende
     * NULL-Terminierung enthält. Dieses Array existiert so lange im Speicher,
     * bis der Rückgabepuffer entweder (bei einer Wiederverwendung des Handles)
     * erneut beschrieben oder der Puffer explizit freigegeben wird.
     *
     * @param[in] handle Handle auf einen mit EricRueckgabepufferErzeugen().
     *            angelegten Rückgabepuffer. Dieser Rückgabepuffer darf nicht
     *            bereits freigegeben worden sein.
     *
     * @return
     *         - Zeiger auf den NULL-terminierten Rückgabepufferinhalt, wenn ein gültiges Handle übergeben wird.
     *         - NULL: Bei Übergabe des ungültigen Handles NULL.
     *
     * @see
     *         - EricRueckgabepufferErzeugen()
     *         - EricRueckgabepufferLaenge()
     *         - EricRueckgabepufferFreigeben()
     */
    ERICAPI_IMPORT const char* STDCALL EricRueckgabepufferInhalt(
        EricRueckgabepufferHandle handle);

    /**
     * @brief Die Länge des Rückgabepufferinhalts wird zurückgegeben.
     *
     * Die zurückgegebene Zahl entspricht der Anzahl von Bytes, die von einer
     * zuvor aufgerufenen ERiC API-Funktion in den Rückgabepuffer geschrieben
     * wurden.
     * Die NULL-Terminierung, die bei Aufruf von EricRueckgabepufferInhalt() an
     * das zurückgegebene Byte-Array angefügt wird, wird bei dieser
     * Längenangabe nicht berücksichtigt.
     *
     * @param[in] handle Handle auf einen mit EricRueckgabepufferErzeugen()
     *            angelegten Rückgabepuffer. Dieser Rückgabepuffer darf nicht
     *            bereits freigegeben worden sein.
     *
     * @return
     *         - Anzahl der in den Rückgabepuffer geschriebenen Bytes, wenn ein gültiges Handle übergeben wird.
     *         - 0: Bei Übergabe des ungültigen Handles NULL.
     *
     * @see
     *         - EricRueckgabepufferErzeugen()
     *         - EricRueckgabepufferInhalt()
     *         - EricRueckgabepufferFreigeben()
     */
    ERICAPI_IMPORT uint32_t STDCALL EricRueckgabepufferLaenge(
        EricRueckgabepufferHandle handle);

    /**
     * @brief Es werden Plattform-, Betriebssystem- und
     *        ERiC-Informationen ausgegeben.
     *
     * Diese Funktion liefert Informationen über die
     * verwendeten ERiC-Bibliotheken, ERiC-Druckvorlagen,
     * die eingesetzte Plattform, den Arbeitsspeicher und
     * das verwendete Betriebssystem.
     *
     *
     * @return
     *  - ::ERIC_OK
     *  - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     *  - weitere, siehe eric_fehlercodes.h
     *
     * @see
     *      - EricVersion()
     */
    ERICAPI_IMPORT int STDCALL EricSystemCheck(
        void);

    /**
     * @brief Es wird eine Liste sämtlicher Produkt- und Dateiversionen
     *        der verwendeten ERiC-Bibliotheken als XML-Daten zurückgegeben.
     *
     * Diese Funktion kann bei auftretenden Fehlern die
     * Fehlersuche beschleunigen und Supportfälle unterstützen.
     *
     * @param[out] rueckgabeXmlPuffer
     *      @parblock
     *              Handle auf einen Rückgabepuffer, in den
     *              zu allen ERiC-Bibliotheken die Produkt- und Dateiversionen
     *              als XML-Daten nach XML Schema Definition @lsAPI-Rueckgabe-Schemata{Dokumentation\API-Rueckgabe-Schemata\EricVersion.xsd}
     *              geschrieben werden.
     *
     *              Zur Erzeugung, Verwendung und Freigabe von Rückgabepuffern
     *              siehe Dokumentation zu ::EricRueckgabepufferHandle.
     *      @endparblock
     *
     * \b Beispiel:
     * \code{.xml}
     * <?xml version="1.0" encoding="UTF-8"?>
     * <EricVersion xmlns="http://www.elster.de/EricXML/1.0/EricVersion">
     *     <Bibliothek>
     *       <Name>ericapi.dll</Name>
     *       <Produktversion>99, 1, 2, 32767</Produktversion>
     *       <Dateiversion>2008, 3, 5, 0</Dateiversion>
     *     </Bibliothek>
     *     <Bibliothek>
     *       <Name>ericctrl.dll</Name>
     *       <Produktversion>99, 1, 2, 32767</Produktversion>
     *       <Dateiversion>2008, 3, 5, 0</Dateiversion>
     *     </Bibliothek>
     *     (...)
     * </EricVersion>
     * \endcode
     *
     * @return
     *  - ::ERIC_OK
     *  - ::ERIC_GLOBAL_NULL_PARAMETER
     *  - ::ERIC_GLOBAL_NICHT_GENUEGEND_ARBEITSSPEICHER
     *  - weitere, siehe eric_fehlercodes.h
     *
     * @see
     *      - EricSystemCheck()
     */
    ERICAPI_IMPORT int STDCALL EricVersion(
        EricRueckgabepufferHandle rueckgabeXmlPuffer);

#ifdef __cplusplus
}
#endif

#endif /*ERICAPI_C_H_*/
