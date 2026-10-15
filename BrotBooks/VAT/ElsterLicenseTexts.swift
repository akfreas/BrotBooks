#if os(macOS)
import Foundation

/// The data-protection texts the ERiC license (`ERiC-44.3.6.0/Dokumentation/lizenz.pdf`) requires the app to show
/// before ERiC is used. Copied verbatim from the license, in German; legal text, not localized and not paraphrased.
/// Only line breaks of the PDF layout are joined (and words hyphenated at a line end rejoined).
enum ElsterLicenseTexts {
    /// One block of a text: a heading, a paragraph or a list item.
    enum Block: Hashable {
        case heading(String)
        case paragraph(String)
        /// A list item; `level` 1 is nested in a level-0 item.
        case item(String, level: Int = 0)
    }

    /// § 5 Abs. 2: "Datenschutzhinweis durch die Finanzverwaltung".
    static let datenschutzhinweisTitle = "Datenschutzhinweis durch die Finanzverwaltung"

    static let datenschutzhinweis = """
        "Mit dieser Software werden personenbezogene Daten im Sinne des Art. 4 Nr. 1 \
        Datenschutzgrundverordnung (DSGVO) und Art. 9 Abs. 1 DSGVO zum Zwecke der Verarbeitung erhoben. Neben den \
        reinen Daten, die zur Steuerveranlagung benötigt werden, erhebt die Software Daten über die Art des \
        Betriebssystems des Nutzers und übermittelt diese an die Finanzverwaltung. Diese Daten werden benötigt, um \
        die ordnungsgemäße Verarbeitung der Daten sicherzustellen und Fehlern im Verarbeitungsprozess vorzubeugen. \
        Die Nutzung der Daten erfolgt im Rahmen des Art. 6 Abs. 1 UAbs. 1 Buchst. e i.V.m. Abs. 3 UAbs. 1 Buchst. b \
        DSGVO i.V.m. bundes- bzw. landesgesetzlicher Steuergesetze durch die Finanzverwaltung und nur für den \
        genannten Zweck."
        """

    /// § 15 "Hinweise an Endnutzer": the part addressed to the end user (the rest of § 15 concerns server
    /// installations and the vendor's own obligations).
    static let protokolldateienTitle = "Hinweis zu Protokolldateien"

    static let protokolldateien = """
        Im Rahmen der ERiC Anwendung werden Protokolldateien erstellt und lokal gespeichert. Die Protokolldateien \
        verbleiben lokal beim Endnutzer. Lediglich im Supportfall können sie nach ausdrücklicher Erlaubnis des \
        Endnutzers an den Softwarehersteller übermittelt werden.
        """

    /// § 5 Abs. 1 / Anhang 2: "Allgemeine Informationen zur Umsetzung der datenschutzrechtlichen Vorgaben der
    /// Artikel 12 bis 14 der Datenschutz-Grundverordnung in der Steuerverwaltung", Stand: 1. Juli 2021.
    static let allgemeineInformationenTitle = """
        Allgemeine Informationen zur Umsetzung der datenschutzrechtlichen Vorgaben der Artikel 12 bis 14 der \
        Datenschutz-Grundverordnung in der Steuerverwaltung
        """

    static let allgemeineInformationen: [Block] = [
        .heading("Vorwort"),
        .paragraph("""
            Nahezu alle Bürgerinnen und Bürger sowie Unternehmen treten mit der Steuerverwaltung – insbesondere den \
            Finanzämtern – früher oder später in Kontakt, weil sie Steuererklärungen abgeben und Steuern zahlen \
            müssen und Erstattungen oder auch Kindergeld beanspruchen können. Hierbei müssen personenbezogene Daten \
            verarbeitet werden.
            """),
        .paragraph("""
            Die nachfolgenden Informationen betreffen die Verarbeitung personenbezogener Daten zu steuerlichen \
            Zwecken, soweit die Abgabenordnung unmittelbar oder mittelbar anzuwenden ist. Ausgenommen ist die \
            Verarbeitung personenbezogener Daten durch Zollbehörden (z. B. Zölle, Einfuhrumsatzsteuer und \
            Kraftfahrzeugsteuer).
            """),
        .paragraph("""
            Im Besteuerungsverfahren sind Daten personenbezogen, wenn sie einer natürlichen Person, einer \
            Körperschaft (z. B. Verein, Kapitalgesellschaft), einer Personenvereinigung oder einer Vermögensmasse \
            zugeordnet werden können. Keine personenbezogenen Daten sind anonymisierte Daten.
            """),
        .paragraph("""
            Wenn Finanzbehörden personenbezogene Daten verarbeiten, bedeutet das, dass sie diese Daten z. B. \
            erheben, speichern, verwenden, übermitteln, zum Abruf bereitstellen oder löschen.
            """),
        .paragraph("""
            Im Folgenden informieren wir Sie darüber, welche personenbezogenen Daten wir erheben, bei wem wir sie \
            erheben und was wir mit diesen Daten machen. Außerdem informieren wir Sie über Ihre Rechte in \
            Datenschutzfragen und an wen Sie sich diesbezüglich wenden können.
            """),

        .heading("Inhaltsverzeichnis"),
        .item("3.1. Wer sind wir?"),
        .item("3.2. Wer sind Ihre Ansprechpartner?"),
        .item("3.3. Zu welchem Zweck verarbeiten wir Ihre personenbezogenen Daten?"),
        .item("3.4. Welche personenbezogenen Daten verarbeiten wir?"),
        .item("3.5. Wie verarbeiten wir diese Daten?"),
        .item("3.6. Unter welchen Voraussetzungen dürfen wir Ihre Daten an Dritte weitergeben?"),
        .item("3.7. Wie lange speichern wir Ihre Daten?"),
        .item("3.8. Welche Rechte (Auskunftsrecht, Widerspruchsrecht usw.) haben Sie?"),
        .item("3.9. Wo bekommen Sie weitergehende Informationen?"),
        .paragraph("Stand: 1. Juli 2021"),

        .heading("3.1 Wer sind wir?"),
        .paragraph("""
            „Wir“ sind die Finanzbehörden des Bundes (Ausnahme: Zollverwaltung) und der Länder und für die \
            Verarbeitung personenbezogener Daten zu steuerlichen Zwecken verantwortlich.
            """),

        .heading("3.2 Wer sind Ihre Ansprechpartner?"),
        .paragraph("""
            Fragen in datenschutzrechtlichen Angelegenheiten können Sie an die verantwortliche Finanzbehörde, \
            vertreten durch die Behördenleitung, richten.
            """),
        .paragraph("""
            Im Regelfall sind die Finanzämter für die Verarbeitung personenbezogener Daten verantwortlich, beim \
            Kindergeld die Familienkassen. Die übrigen Finanzbehörden (z. B. Finanzministerium, Bundeszentralamt für \
            Steuern, Oberfinanzdirektion, Landesamt für Steuern) sind für die Verarbeitung personenbezogener Daten \
            nur verantwortlich, soweit sie diese Daten zur Erfüllung ihrer gesetzlichen Aufgaben verarbeiten.
            """),
        .paragraph("""
            Darüber hinaus können Sie sich an den Datenschutzbeauftragten der jeweils verantwortlichen \
            Finanzbehörde wenden.
            """),
        .paragraph("""
            Die entsprechenden Kontaktdaten für die Landesfinanzbehörden finden Sie unter www.finanzamt.de in den \
            jeweiligen landesspezifischen Übersichten, für das Bundesministerium der Finanzen unter \
            www.bundesfinanzministerium.de und für das Bundeszentralamt für Steuern und die Familienkassen unter \
            www.bzst.de.
            """),

        .heading("3.3 Zu welchem Zweck verarbeiten wir Ihre personenbezogenen Daten?"),
        .paragraph("""
            Um unsere Aufgabe zu erfüllen, die Steuern nach den Vorschriften der Abgabenordnung und der \
            Steuergesetze gleichmäßig festzusetzen und zu erheben, benötigen wir personenbezogene Daten (§ 85 der \
            Abgabenordnung).
            """),
        .paragraph("""
            Ihre personenbezogenen Daten werden in dem steuerlichen Verfahren verarbeitet, für das sie erhoben \
            wurden (§ 29b der Abgabenordnung). Nur in den gesetzlich ausdrücklich zugelassenen Fällen dürfen wir \
            die zur Durchführung eines steuerlichen Verfahrens erhobenen personenbezogenen Daten auch für andere \
            steuerliche oder nichtsteuerliche Zwecke verarbeiten (Weiterverarbeitung nach § 29c Absatz 1 der \
            Abgabenordnung).
            """),
        .paragraph("Beispiel zur Verarbeitung:"),
        .paragraph("""
            Die mit der Einkommensteuererklärung von der Finanzbehörde erhobenen Daten werden bei der \
            Einkommensteuerveranlagung verarbeitet.
            """),
        .paragraph("Beispiel zur Weiterverarbeitung:"),
        .paragraph("""
            In bestimmten Fällen werden einzelne Besteuerungsgrundlagen gesondert festgestellt (z. B. Einkünfte aus \
            der Beteiligung an einer Personengesellschaft). Hierzu werden die Angaben aus der \
            Feststellungserklärung in einem selbständigen Verfahren, dem Feststellungsverfahren, verarbeitet. Die \
            auf diese Weise festgestellten Besteuerungsgrundlagen und weitere erforderliche Daten werden den \
            Finanzbehörden mitgeteilt, die für die Besteuerung der Beteiligten zuständig sind. Diese verarbeiten die \
            mitgeteilten Daten weiter, indem sie diese Daten im Steuerfestsetzungsverfahren, z. B. bei der \
            Einkommensteuer, berücksichtigen.
            """),
        .paragraph("Die Finanzämter verwalten insbesondere die folgenden Steuern:"),
        .item("Einkommensteuer (einschließlich Lohnsteuer und Kapitalertragsteuer),"),
        .item("Körperschaftsteuer,"),
        .item("Solidaritätszuschlag,"),
        .item("Kirchensteuer (Ausnahme: Freistaat Bayern),"),
        .item("Gewerbesteuer (Soweit die Länder die Verwaltung nicht den Gemeinden übertragen haben.),"),
        .item("Erbschaft-/Schenkungsteuer,"),
        .item("Grundsteuer (Soweit die Länder die Verwaltung nicht den Gemeinden übertragen haben.),"),
        .item("Umsatzsteuer (ohne Einfuhrumsatzsteuer),"),
        .item("Grunderwerbsteuer,"),
        .item("Rennwett- und Lotteriesteuer."),
        .paragraph("""
            Das Bundeszentralamt für Steuern hat nach § 5 des Finanzverwaltungsgesetzes insbesondere die folgenden \
            Aufgaben:
            """),
        .item("Vergabe der steuerlichen Identifikationsnummer (IdNr.),"),
        .item("Bildung der elektronischen Lohnsteuerabzugsmerkmale (ELStAM),"),
        .item("Mitwirkung bei Außenprüfungen,"),
        .item("Erstattung und Freistellung von deutschen Abzugssteuern,"),
        .item("zentrale Sammlung und Auswertung von steuerlichen Auslandsbeziehungen,"),
        .item("Vergütung von Vorsteuerbeträgen an Unternehmen,"),
        .item("Vergabe der Umsatzsteuer-Identifikationsnummer (USt-ID),"),
        .item("Kindergeldbearbeitung, wofür sich das Bundeszentralamt für Steuern der Familienkassen bedient."),

        .heading("3.4 Welche personenbezogenen Daten verarbeiten wir?"),
        .paragraph("Wir verarbeiten insbesondere folgende personenbezogene Daten:"),
        .item("""
            Persönliche Identifikations- und Kontaktangaben, z. B. Vor- und Nachname, Adresse, Geburtsdatum und \
            -ort, Steuernummer, Identifikationsnummer, E-Mail-Adresse, Telefonnummer.
            """),
        .item("Für die Festsetzung und Erhebung der Steuern erforderliche Informationen, z. B."),
        .item("""
            Einnahmen (z. B. Arbeitslohn, Betriebseinnahmen, Einnahmen aus Vermietung und Verpachtung, \
            Kapitalerträge, Renten),
            """, level: 1),
        .item("""
            Ausgaben (z. B. Werbungskosten, Betriebsausgaben, Sonderausgaben und außergewöhnliche Belastungen),
            """, level: 1),
        .item("""
            von Dritten einbehaltene Steuern (z. B. Lohnsteuer, Kapitalertragsteuer, Solidaritätszuschlag, \
            Kirchensteuer),
            """, level: 1),
        .item("Familienstand und Kinder,", level: 1),
        .item("Lohnsteuerklasse,", level: 1),
        .item("Beruf,", level: 1),
        .item("Bankverbindung,", level: 1),
        .item("Angaben über geleistete oder erstattete Steuern,", level: 1),
        .item("Angaben über abgegebene Steuererklärungen und gestellte Anträge sowie Rechtsbehelfe.", level: 1),
        .paragraph("""
            Besondere Kategorien personenbezogener Daten, sogenannte „sensible Daten", erheben wir ebenfalls nur \
            dann, wenn dies für das Besteuerungsverfahren erforderlich ist. So benötigen wir z. B. Angaben über die \
            Religionszugehörigkeit, um Kirchensteuerzahlungen als Sonderausgaben berücksichtigen zu können, oder \
            Angaben über Erkrankungen/Behinderungen, um entsprechende Aufwendungen als außergewöhnliche Belastungen \
            abzuziehen. Wir erheben Ihre personenbezogenen Daten in erster Linie bei Ihnen selbst, z. B. durch Ihre \
            Steuererklärungen, Mitteilungen und Anträge.
            """),
        .paragraph("""
            Darüber hinaus erheben wir Ihre personenbezogenen Daten bei Dritten, soweit diese gesetzlich zur \
            Mitteilung an uns verpflichtet sind.
            """),
        .paragraph("Beispiele:"),
        .item("""
            Arbeitgeber übermitteln in der Lohnsteuerbescheinigung z. B. Daten über den Arbeitslohn, die \
            einbehaltenen Steuern und die geleisteten Sozialversicherungsbeiträge,
            """),
        .item("""
            Rentenversicherungsträger übermitteln in der Rentenbezugsmitteilung z. B. Daten über Rentenzahlungen \
            und einbehaltene Kranken- und Pflegeversicherungsbeiträge,
            """),
        .item("""
            Private Krankenversicherungen übermitteln z. B. Daten über geleistete und ggf. erstattete Kranken- und \
            Pflegeversicherungsbeiträge,
            """),
        .item("Sozialbehörden übermitteln Daten über Lohnersatzleistungen,"),
        .item("Kreditinstitute übermitteln Daten über vom Kapitalertragsteuerabzug freigestellte Kapitalerträge,"),
        .item("Gemeinden übermitteln Daten über Gewerbeanmeldungen und Meldedaten,"),
        .item("""
            Notare übermitteln Daten über Grundstücksveräußerungen, Gesellschaftsverträge, Erbverträge und \
            Schenkungsverträge,
            """),
        .item("Behörden übermitteln Daten über Zahlungen und Verwaltungsakte,"),
        .item("öffentlich-rechtliche Rundfunkanstalten übermitteln Daten über Honorare."),
        .paragraph("""
            Außerdem erhalten wir steuerrelevante Informationen von anderen Finanzbehörden oder im Wege des \
            zwischenstaatlichen Informationsaustauschs.
            """),
        .paragraph("""
            Können wir einen steuerrelevanten Sachverhalt nicht mit Ihrer Hilfe aufklären, dürfen wir Sie \
            betreffende personenbezogene Daten auch durch Nachfragen bei Dritten erheben (z. B. Auskunftsersuchen \
            an den Arbeitgeber). Im Vollstreckungsverfahren können wir Daten bei Drittschuldnern (z. B. \
            Kreditinstitut oder Arbeitgeber) erheben.
            """),
        .paragraph("""
            Zudem können wir öffentlich zugängliche Informationen (z. B. aus Zeitungen, öffentlichen Registern oder \
            öffentlichen Bekanntmachungen) verarbeiten.
            """),

        .heading("3.5 Wie verarbeiten wir diese Daten?"),
        .paragraph("""
            Im weitgehend automationsgestützten Besteuerungsverfahren werden Ihre personenbezogenen Daten \
            gespeichert und dann in zumeist maschinellen Verfahren der Festsetzung und Erhebung der Steuer \
            zugrunde gelegt. Wir setzen dabei technische und organisatorische Sicherheitsmaßnahmen ein, um Ihre \
            personenbezogenen Daten gegen unbeabsichtigte oder unrechtmäßige Vernichtung, Verlust oder Veränderung \
            sowie gegen unbefugte Offenlegung oder unbefugten Zugang zu schützen. Unsere Sicherheitsstandards \
            entsprechen stets den aktuellsten technologischen Entwicklungen.
            """),
        .paragraph("""
            Rechtsverbindliche Entscheidungen treffen wir nur dann auf Grundlage einer „vollautomatischen“ \
            Verarbeitung personenbezogener Daten, wenn dies gesetzlich zugelassen ist (z. B. vollautomatischer“ \
            Steuerbescheid nach § 155 Absatz 4 der Abgabenordnung).
            """),

        .heading("3.6 Unter welchen Voraussetzungen dürfen wir Ihre Daten an Dritte weitergeben?"),
        .paragraph("""
            Alle personenbezogenen Daten, die uns in einem steuerlichen Verfahren bekannt geworden sind, dürfen wir \
            nur dann an andere Personen oder Stellen (z. B. an Finanzgerichte, Krankenkassen, \
            Rentenversicherungsträger oder andere Behörden) weitergeben, wenn Sie dem zugestimmt haben oder die \
            Weitergabe gesetzlich zugelassen ist.
            """),
        .paragraph("Beispiele:"),
        .item("""
            Mitteilung der Grundsteuer- und Gewerbesteuermessbeträge an die für die Festsetzung und Erhebung der \
            Grundsteuer bzw. der Gewerbesteuer zuständigen Gemeinden,
            """),
        .item("""
            Mitteilungen an Körperschaften des öffentlichen Rechts (z. B. Kammern und Innungen) zur Festsetzung von \
            solchen Abgaben, die an Besteuerungsgrundlagen, Steuermessbeträge oder Steuerbeträge anknüpfen,
            """),
        .item("""
            Mitteilungen an die gesetzliche Sozialversicherung, an die Bundesagentur für Arbeit und die \
            Künstlersozialkasse, soweit die Kenntnis personenbezogener Daten für die Feststellung der \
            Versicherungspflicht oder die Festsetzung von Beiträgen einschließlich der Künstlersozialabgabe \
            erforderlich ist,
            """),
        .item("""
            Mitteilungen an Sozialbehörden zur Bekämpfung der illegalen Beschäftigung und des \
            Leistungsmissbrauchs,
            """),
        .item("""
            Mitteilungen der Familienkassen an Bezügestellen des öffentlichen Dienstes zur Festsetzung von \
            Gehaltsbestandteilen, die an das Kindergeld anknüpfen.
            """),

        .heading("3.7 Wie lange speichern wir Ihre Daten?"),
        .paragraph("""
            Personenbezogene Daten müssen wir solange speichern, wie sie für das Besteuerungsverfahren erforderlich \
            sind. Maßstab hierfür sind die steuerlichen Verjährungsfristen (§§ 169 bis 171 der Abgabenordnung sowie \
            §§ 228 bis 232 der Abgabenordnung).
            """),
        .paragraph("""
            Wir dürfen Sie betreffende personenbezogene Daten auch speichern, um diese für künftige steuerliche \
            Verfahren zu verarbeiten (§ 88a der Abgabenordnung).
            """),

        .heading("3.8 Welche Rechte (Auskunftsrecht, Widerspruchsrecht usw.) haben Sie?"),
        .paragraph("""
            Sie haben nach der Datenschutz-Grundverordnung verschiedene Rechte. Einzelheiten ergeben sich \
            insbesondere aus Artikel 15 bis 18 und 21 der Datenschutz-Grundverordnung.
            """),
        .item("Recht auf Auskunft"),
        .paragraph("""
            Sie können Auskunft über Ihre von uns verarbeiteten personenbezogenen Daten verlangen. In Ihrem \
            Auskunftsantrag sollten Sie Ihr Anliegen präzisieren, um uns das Zusammenstellen der erforderlichen \
            Daten zu erleichtern. Daher sollten in dem Antrag möglichst Angaben zum konkreten Verwaltungsverfahren \
            (z. B. Steuerart und Jahr) und zum Verfahrensabschnitt (z. B. Festsetzung, Vollstreckung) gemacht \
            werden.
            """),
        .item("Recht auf Berichtigung"),
        .paragraph("""
            Sollten die Sie betreffenden Angaben nicht (mehr) zutreffend sein, können Sie eine Berichtigung \
            verlangen. Sollten Ihre Daten unvollständig sein, können Sie eine Vervollständigung verlangen.
            """),
        .item("Recht auf Löschung"),
        .paragraph("""
            Sie können die Löschung Ihrer personenbezogenen Daten verlangen. Ihr Anspruch auf Löschung hängt u. a. \
            davon ab, ob die Sie betreffenden Daten von uns zur Erfüllung unserer gesetzlichen Aufgaben noch \
            benötigt werden (vgl. oben 3.7.).
            """),
        .item("Recht auf Einschränkung der Verarbeitung"),
        .paragraph("""
            Sie haben das Recht, eine Einschränkung der Verarbeitung der Sie betreffenden Daten zu verlangen. Die \
            Einschränkung steht einer Verarbeitung nicht entgegen, soweit an der Verarbeitung ein wichtiges \
            öffentliches Interesse (z. B. gesetzmäßige und gleichmäßige Besteuerung) besteht.
            """),
        .item("Recht auf Widerspruch"),
        .paragraph("""
            Sie haben das Recht, aus Gründen, die sich aus Ihrer besonderen Situation ergeben, jederzeit der \
            Verarbeitung der Sie betreffenden Daten zu widersprechen. Allerdings können wir dem nicht nachkommen, \
            wenn an der Verarbeitung ein überwiegendes öffentliches Interesse besteht oder eine Rechtsvorschrift uns \
            zur Verarbeitung verpflichtet (z. B. Durchführung des Besteuerungsverfahrens).
            """),
        .item("Recht auf Beschwerde"),
        .paragraph("""
            Wenn Sie der Auffassung sind, dass wir Ihrem Anliegen nicht oder nicht in vollem Umfang nachgekommen \
            sind, können Sie bei der zuständigen Datenschutzaufsichtsbehörde Beschwerde einlegen. Im Regelfall ist \
            dies die oder der Bundesbeauftragte für den Datenschutz und die Informationsfreiheit (Kontaktdaten unter \
            www.bfdi.bund.de). Die Kontaktdaten der Datenschutzbehörden der Länder finden Sie unter \
            www.datenschutz.de/projektpartner/.
            """),
        .paragraph("Allgemeine Hinweise zu diesen Rechten"),
        .paragraph("""
            In einigen Fällen können oder dürfen wir Ihrem Anliegen nicht entsprechen (§§ 32c bis 32f der \
            Abgabenordnung). Sofern dies gesetzlich zulässig ist, teilen wir Ihnen in diesem Fall immer den Grund \
            für die Verweigerung mit.
            """),
        .paragraph("""
            Wir werden Ihnen aber grundsätzlich innerhalb eines Monats nach Eingang Ihres Anliegens antworten. \
            Sollten wir länger als einen Monat für eine abschließende Klärung brauchen, erhalten Sie eine \
            Zwischennachricht.
            """),

        .heading("3.9 Wo bekommen Sie weitergehende Informationen?"),
        .paragraph("Weitergehende Informationen können Sie dem"),
        .item("""
            BMF-Schreiben zum Datenschutz im Steuerverwaltungsverfahren vom 13. Januar 2020, das zuletzt durch das \
            BMF-Schreiben vom 17. Juni 2021 geändert worden ist (siehe BStBl 2020 I S. 143 sowie BStBl 2021 I S. 809 \
            und auf den Internetseiten des Bundesministeriums der Finanzen [http://www.bundesfinanzministerium.de] \
            unter der Rubrik Themen - Steuern - Steuerverwaltung & Steuerrecht - Abgabenordnung - BMF-Schreiben / \
            Allgemeines) sowie
            """),
        .item("""
            der Broschüre „Steuern von A bis Z“ (siehe http://www.bundesfinanzministerium.de unter der Rubrik \
            Themen - Service - Publikationen - Broschüren)
            """),
        .paragraph("entnehmen."),
    ]
}
#endif
