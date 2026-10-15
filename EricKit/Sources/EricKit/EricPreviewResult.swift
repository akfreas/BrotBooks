import Foundation

/// The outcome of `EricService.preview`: the validation messages and the preview PDF(s) ERiC printed.
public struct EricPreviewResult: Sendable, Equatable {
    /// One PDF from ERiC's `pdfCallback`.
    public struct Document: Sendable, Equatable {
        /// ERiC's name for the PDF (`pdfBezeichner`).
        public var name: String
        public var data: Data

        public init(name: String, data: Data) {
            self.name = name
            self.data = data
        }
    }

    /// Code, rule errors and hints, as from `validate` (without hint checking, `ERIC_PRUEFE_HINWEISE`).
    public var validation: EricValidationResult
    /// Usually one; empty when validation failed.
    public var documents: [Document]

    public init(validation: EricValidationResult, documents: [Document]) {
        self.validation = validation
        self.documents = documents
    }

    /// The first PDF, or nil when ERiC printed none.
    public var pdf: Data? { documents.first?.data }
}
