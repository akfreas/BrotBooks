#if os(iOS)
import PDFKit
import SwiftUI
import VisionKit

/// "Scan Documents…": the VisionKit document camera. One scan session becomes one multi-page PDF (one expense).
struct DocumentScanner: UIViewControllerRepresentable {
    /// The scanned PDF, or nil when the user cancelled or the scan failed.
    let onFinish: (Data?) -> Void

    /// False in the Simulator and on devices without a camera.
    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: (Data?) -> Void

        init(onFinish: @escaping (Data?) -> Void) {
            self.onFinish = onFinish
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            onFinish(Self.pdf(scan))
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onFinish(nil)
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: any Error) {
            onFinish(nil)
        }

        /// Every page of the scan as one PDF.
        static func pdf(_ scan: VNDocumentCameraScan) -> Data? {
            let document = PDFDocument()
            for index in 0..<scan.pageCount {
                guard let page = PDFPage(image: scan.imageOfPage(at: index)) else { continue }
                document.insert(page, at: document.pageCount)
            }
            return document.pageCount > 0 ? document.dataRepresentation() : nil
        }
    }
}
#endif
