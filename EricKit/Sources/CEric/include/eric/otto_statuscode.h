#ifndef OTTO_STATUSCODE_H_
#define OTTO_STATUSCODE_H_

/**
 * @file
 * @brief Auflistung der Otto-Statuscodes
 */
typedef enum {
    /** Die Verarbeitung ist ordnungsgemäß abgeschlossen worden. */
    OTTO_OK = 0,


    // ========   Otto-Fehler 61 040 x xxx   ========


    // --------   Interne Fehler 61 040 1 xxx   --------

    /** Es trat ein interner Fehler auf, Details stehen im otto.log. */
    OTTO_INTERNER_FEHLER = 610401001,

    /** Es trat ein unerwarteter Fehler auf, Details stehen im otto.log. */
    OTTO_UNBEKANNTER_FEHLER = 610401002,

    /** Es trat ein Fehler bei der Erzeugung eines Ad-hoc-Zertifikats für den nPA auf, Details stehen ggf. im otto.log. */
    OTTO_NPA_ZERTIFIKATFEHLER = 610401003,

    // --------   Transferfehler 61 040 3 xxx   --------

    /** Es trat ein Fehler beim Transfer auf, Details stehen ggf. im otto.log. */
    OTTO_TRANSFER_FEHLER = 610403001,

    /** Es trat ein Fehler bei der Initialisierung des Transfers auf. */
    OTTO_TRANSFER_INIT = 610403002,

    /** Es konnte keine Verbindung zum OTTER-Server aufgebaut werden. */
    OTTO_TRANSFER_CONNECTSERVER = 610403003,

    /** Es konnte keine Verbindung zum Proxy aufgebaut werden. */
    OTTO_TRANSFER_CONNECTPROXY = 610403004,

    /** Bei der Kommunikation mit dem Server kam es zu einer Zeitüberschreitung. */
    OTTO_TRANSFER_TIMEOUT = 610403005,

    /** Der Proxy erwartet Anmeldedaten oder der Proxy hat die Verbindung abgelehnt. */
    OTTO_TRANSFER_PROXYAUTH = 610403006,

    /** Der Client darf die Schnittstelle nicht verwenden. */
    OTTO_TRANSFER_UNAUTHORIZED = 610403007,

    /** Der OTTER-Server hat das Objekt nicht gefunden. */
    OTTO_TRANSFER_NOT_FOUND = 610403008,

    /** Der OTTER-Server hat einen unerwarteten Fehler gemeldet. Möglicherweise ist ein Retry sinnvoll. Details stehen im otto.log. */
    OTTO_TRANSFER_SERVER_FEHLER = 610403009,

    /** Die empfangenen Daten konnten nicht dekodiert werden. */
    OTTO_TRANSFER_DECODING = 610403010,

    /** Es konnte kein Ad-hoc-Zertifikat für den Personalausweis oder den Aufenthaltstitel erzeugt bzw. gefunden werden, Details stehen ggf. im otto.log. */
    OTTO_TRANSFER_EID_ZERTIFIKATFEHLER = 610403011,

    /** Der eID-Client ist nicht erreichbar. Wahrscheinlich wurde er nicht gestartet oder die übergebene lokale URL ist nicht korrekt. */
    OTTO_TRANSFER_EID_KEINCLIENT = 610403012,

    /** Für die Identifikationsnummer des Benutzers existiert kein Konto bei ELSTER. */
    OTTO_TRANSFER_EID_KEINKONTO = 610403013,

    /** Der eID-Client hat einen Fehler gemeldet. Details zu dem Fehler finden Sie im Log des eID-Clients oder ggf. im otto.log. */
    OTTO_TRANSFER_EID_CLIENTFEHLER = 610403014,

    /** Der Personalausweis wird von einem anderen Vorgang blockiert. Beenden Sie den anderen Vorgang und versuchen Sie es dann erneut. */
    OTTO_TRANSFER_EID_NPABLOCKIERT = 610403015,

    // --------   Anwendungsfehler 61 040 5 xxx   --------

    /** Einer der übergebenen Parameter ist ungültig. */
    OTTO_UNGUELTIGER_PARAMETER = 610405001,

    /** Das übergebene Handle ist ungültig. */
    OTTO_UNGUELTIGES_HANDLE = 610405002,

    /** Die übergebene Otto-Instanz wird gerade (zum Beispiel in einem anderen Thread) verwendet. */
    OTTO_MEHRFACHAUFRUFE_NICHT_UNTERSTUETZT = 610405003,

    /** Eines der übergebenen Otto-Objekte wurde mit einer anderen Otto-Instanz erstellt. */
    OTTO_INSTANZEN_INKONSISTENT = 610405004,

    /** Mit dieser Instanz wurden Unterobjekte erzeugt, die noch nicht freigegeben worden sind. */
    OTTO_INSTANZ_UNTEROBJEKTE_NICHT_FREIGEGEBEN = 610405005,

    /** Die Protokolldatei konnte nicht erzeugt oder geöffnet werden. */
    OTTO_LOG_FEHLER = 610405006,

    /** Die verwendetet Funktion oder Funktionalität wird nicht, noch nicht oder nicht mehr unterstützt. */
    OTTO_FUNKTION_NICHT_UNTERSTUETZT = 610405007,

    /** Für das Zertifikat wurde ein falsches Passwort bzw. eine falsche PIN angegeben. */
    OTTO_ZERTIFIKAT_PIN_FALSCH = 610405008,

    /** Unter dem angegebenen Pfad wurde kein Zertifikat gefunden. */
    OTTO_ZERTIFIKAT_PFAD_FALSCH = 610405009,

    /** Das Zertifikat wurde nicht erkannt, Details stehen ggf. im otto.log. */
    OTTO_ZERTIFIKAT_NICHT_ERKANNT = 610405010,

    /** Die Prüfsumme wurde bereits finalisiert */
    OTTO_PRUEFSUMME_FINALISIERT = 610405011,

    /** Es wurde keine oder eine ungültige Hersteller-ID angegeben. */
    OTTO_UNGUELTIGE_HERSTELLERID = 610405012,

    /** Der Empfang wurde durch einen API-Aufruf vorzeitig beendet. */
    OTTO_EMPFANG_VORZEITIG_BEENDET = 610405013,

    /** Die Versanddaten dürfen die Mindestgröße nicht unterschreiten. */
    OTTO_VERSAND_GERINGE_DATENMENGE = 610405014,

    /** Die eSigner-Bibliothek konnte nicht geladen werden, Details stehen ggf. im otto.log */
    OTTO_ESIGNER_NICHT_GELADEN = 610405015,

    /** Die eSigner-Bibliothek ist veraltet, Details stehen ggf. im otto.log. */
    OTTO_ESIGNER_VERALTET = 610405016,

    /** Die eSigner-Bibliothek ist mit der Otto-Bibliothek inkompatibel. */
    OTTO_ESIGNER_INKOMPATIBEL = 610405017,

    /** Es wurde keine URL oder IP für den Proxy angegeben. */
    OTTO_PROXY_URL = 610405018,

    /** Es wurde kein oder ein ungültiger Port für den Proxy angegeben. */
    OTTO_PROXY_PORT = 610405019,

    /** Es wurde kein gültiges Proxy-Authentifizierungschema angegeben. */
    OTTO_PROXY_AUTHSCHEMA = 610405020,

    /** Der Verand wurde bereits abgeschlossen. */
    OTTO_VERSAND_ABGESCHLOSSEN = 610405021,

    /** Die Versanddaten dürfen die Maximalgröße nicht überschreiten. */
    OTTO_VERSAND_ZU_GROSSE_DATENMENGE = 610405022,

    /** Die Einstellung ist unbekannt */
    OTTO_EINSTELLUNG_UNBEKANNT = 610405023,

    /** Der Wert ist für diese Einstellung nicht zulässig */
    OTTO_EINSTELLUNG_WERT_UNGUELTIG = 610405024,

    // --------   Anwendungsfehler, die vom eSigner durchgereicht werden 61 040 5 8xx   --------

    /** eSigner: Überlastung */
    OTTO_ESIGNER_BUSY = 610405801,

    /** eSigner: Fehler beim Entschlüsseln */
    OTTO_ESIGNER_DECRYPT = 610405802,

    /** eSigner: Fehler beim Verschlüsseln */
    OTTO_ESIGNER_ENCRYPT = 610405803,

    /** eSigner: Fehler beim Encoding */
    OTTO_ESIGNER_ENCODE_ERROR = 610405804,

    /** eSigner: Parameter Fehler: unbekanntes Encoding */
    OTTO_ESIGNER_ENCODE_UNKNOWN = 610405805,

    /** eSigner: Eine Laufzeitausnahme ist aufgetreten und abgefangen worden. */
    OTTO_ESIGNER_ESICL_EXCEPTION = 610405806,

    /** eSigner: Ungültiges Token-Handle */
    OTTO_ESIGNER_INVALID_HANDLE = 610405807,

    /** eSigner: PKCS11- bzw. PC/SC-Bibliothek fehlt oder ist nicht ausführbar. */
    OTTO_ESIGNER_LOAD_DLL = 610405808,

    /** eSigner: Zu viele Sessions geöffnet. */
    OTTO_ESIGNER_MAX_SESSION = 610405809,

    /** eSigner: Der PC/SC-Dienst ist nicht gestartet. */
    OTTO_ESIGNER_NO_SERVICE = 610405810,

    /** eSigner: Kein Signatur/Verschlüsselungszertifikat bzw. -schlüssel vorhanden. */
    OTTO_ESIGNER_NO_SIG_ENC_KEY = 610405811,

    /** eSigner: Speicherallokation fehlgeschlagen. */
    OTTO_ESIGNER_OUT_OF_MEM = 610405812,

    /** eSigner: Fehler beim Zugriff auf Hard-Token-Entschlüsselungsschlüssel */
    OTTO_ESIGNER_P11_ENC_KEY = 610405813,

    /** eSigner: Die PKCS#11-Engine wird von einer anderen Bibliothek belegt. */
    OTTO_ESIGNER_P11_ENGINE_LOADED = 610405814,

    /** eSigner: P11 Initialer Token-Zugriff fehlgeschlagen. */
    OTTO_ESIGNER_P11_INIT_FAILED = 610405815,

    /** eSigner: P11 Verschlüsselungszertifikat fehlt. */
    OTTO_ESIGNER_P11_NO_ENC_CERT = 610405816,

    /** eSigner: P11 Signaturzertifikat fehlt. */
    OTTO_ESIGNER_P11_NO_SIG_CERT = 610405817,

    /** eSigner: Fehler beim Zugriff auf den Hard-Token-Signaturschlüssel */
    OTTO_ESIGNER_P11_SIG_KEY = 610405818,

    /** eSigner: Leere Slot-Liste, d.h. keine Karte eingesteckt. */
    OTTO_ESIGNER_P11_SLOT_EMPTY = 610405819,

    /** eSigner: Temporäres PKCS#12-Token konnte nicht erzeugt werden. */
    OTTO_ESIGNER_P12_CREATE = 610405820,

    /** eSigner: Fehler beim Dekodieren des PKCS#12-Objekts */
    OTTO_ESIGNER_P12_DECODE = 610405821,

    /** eSigner: Fehler beim Zugriff auf den Soft-PSE-Entschlüsselungsschlüssel */
    OTTO_ESIGNER_P12_ENC_KEY = 610405822,

    /** eSigner: Fehler beim Zugriff auf den Soft-PSE-Signaturschlüssel */
    OTTO_ESIGNER_P12_SIG_KEY = 610405823,

    /** eSigner: P12 Verschlüsselungszertifikat fehlt. */
    OTTO_ESIGNER_P12_NO_ENC_CERT = 610405824,

    /** eSigner: P12 Signaturzertifikat fehlt. */
    OTTO_ESIGNER_P12_NO_SIG_CERT = 610405825,

    /** eSigner: Fehler beim Lesen des PKCS#12-Objekts */
    OTTO_ESIGNER_P12_READ = 610405826,

    /** eSigner: Fehler beim Dekodieren des PKCS#7-Objekts */
    OTTO_ESIGNER_P7_DECODE = 610405827,

    /** eSigner: Fehler beim Lesen des PKCS#7-Objekts */
    OTTO_ESIGNER_P7_READ = 610405828,

    /** eSigner: Das Entschlüsselungszertifikat ist nicht in der Empfängerliste enthalten. */
    OTTO_ESIGNER_P7_RECIPIENT = 610405829,

    /** eSigner: Die PIN bzw. das Passwort ist gesperrt. */
    OTTO_ESIGNER_PIN_LOCKED = 610405830,

    /** eSigner: Die PIN bzw. das Passwort ist falsch. */
    OTTO_ESIGNER_PIN_WRONG = 610405831,

    /** eSigner: Der Pfad zum Soft-PSE ist falsch oder ungültig. */
    OTTO_ESIGNER_PSE_PATH = 610405832,

    /** eSigner: Fehler beim Zugriff auf den Stick-Entschlüsselungsschlüssel. */
    OTTO_ESIGNER_SC_ENC_KEY = 610405833,

    /** eSigner: Initialer Token-Zugriff auf die PC/SC-Schnittstelle fehlgeschlagen. */
    OTTO_ESIGNER_SC_INIT_FAILED = 610405834,

    /** eSigner: Kein unterstütztes Applet gefunden. */
    OTTO_ESIGNER_SC_NO_APPLET = 610405835,

    /** eSigner: PC/SC Verschlüsselungszertifikat fehlt. */
    OTTO_ESIGNER_SC_NO_ENC_CERT = 610405836,

    /** eSigner: PC/SC Signaturzertifikat fehlt. */
    OTTO_ESIGNER_SC_NO_SIG_CERT = 610405837,

    /** eSigner: Fehler in der Karten-Session. */
    OTTO_ESIGNER_SC_SESSION = 610405838,

    /** eSigner: Fehler beim Zugriff auf den Stick-Signaturschlüssel */
    OTTO_ESIGNER_SC_SIG_KEY = 610405839,

    /** eSigner: Es ist keine Karte bzw. kein Stick eingesteckt. */
    OTTO_ESIGNER_SC_SLOT_EMPTY = 610405840,

    /** eSigner: Der Token-Typ der CA (Certification Authority, Zertifizierungsstelle) stimmt nicht mit dem internen Token-Typ überein. */
    OTTO_ESIGNER_TOKEN_TYPE_MISMATCH = 610405841,

    /** eSigner: Die Aktion wurde vom Benutzer abgebrochen. */
    OTTO_ESIGNER_USER_CANCEL = 610405842,

    /** eSigner: Die Zertifikatskette konnte nicht verifiziert werden. */
    OTTO_ESIGNER_VERIFY_CERT_CHAIN = 610405843,

    /** eSigner: Die Datenstruktur ist nicht initialisiert. */
    OTTO_ESIGNER_DATA_NOT_INITIALIZED = 610405844,

    /** eSigner: Der Lesepuffer zum Dekodieren der ASN.1-Struktur ist zu klein. */
    OTTO_ESIGNER_ASN1_READ_BUFFER_TOO_SMALL = 610405845,

    /** eSigner: Die Daten der ASN.1-Struktur sind unvollständig. */
    OTTO_ESIGNER_ASN1_READ_DATA_INCOMPLETE = 610405846,

    /** eSigner: Die ASN.1-Struktur enthält kein Enveloped Data. */
    OTTO_ESIGNER_ASN1_NO_ENVELOPED_DATA = 610405847,

    /** eSigner: Die ASN.1-Struktur enthält keine Daten. */
    OTTO_ESIGNER_ASN1_NO_CONTENT_DATA = 610405848,

    /** eSigner: Fehler beim Signieren der XML-Eingabedatei. */
    OTTO_ESIGNER_XML_VERIFY = 610405849,

    // --------   Systemfehler 61 040 7 xxx   --------

    /** Fehler beim Einlesen der otto.ini. */
    OTTO_INIDATEI_LESEFEHLER = 610407001,

    /** Das Zertifikat konnte nicht geladen werden. */
    OTTO_ZERTIFIKAT_LESEFEHLER = 610407002,

    /** Die Zertifikatsdatei oder das Soft-PSE ist defekt. */
    OTTO_ZERTIFIKAT_DEFEKT = 610407003,

    /** Für das Zertifikat konnte kein Fingerabdruck erstellt werden. */
    OTTO_ZERTIFIKAT_FINGERABDRUCK_FEHLER = 610407004,

    /** Die Daten konnten mit dem übergebenen Zertifikat nicht signiert werden. */
    OTTO_SIGNIEREN_FEHLGESCHLAGEN = 610407005,

    /** Die Daten konnten mit dem übergebenen Zertifikat nicht entschlüsselt werden. */
    OTTO_ENTSCHLUESSELN_FEHLGESCHLAGEN = 610407006,

    /** Die Daten konnten nicht dekomprimiert werden. */
    OTTO_DEKOMPRESSION_FEHLGESCHLAGEN = 610407007,

    /** Es ist nicht genügend Arbeitsspeicher vorhanden. */
    OTTO_NICHT_GENUEGEND_ARBEITSSPEICHER = 610407008
} OttoStatusCode;

#endif /* OTTO_STATUSCODE_H_ */