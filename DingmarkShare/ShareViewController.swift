import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// Share extension entry point. The system presents this controller full
/// size; it stays transparent and presents the SwiftUI form as a page sheet
/// with medium and large detents, so the nominal path is two taps:
/// Share, then Save.
final class ShareViewController: UIViewController, UIAdaptivePresentationControllerDelegate {
    private var didPresent = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didPresent else { return }
        didPresent = true
        Task { @MainActor in
            let shared = await SharedItemReader.read(from: extensionContext)
            presentSheet(url: shared.url, title: shared.title)
        }
    }

    private func presentSheet(url: String?, title: String?) {
        let root = ShareSheetView(session: Session(), sharedURL: url, sharedTitle: title) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        } onCancel: { [weak self] in
            self?.cancel()
        }
        let host = UIHostingController(rootView: root.tint(.dingmarkTint))
        host.modalPresentationStyle = .pageSheet
        host.presentationController?.delegate = self
        if let sheet = host.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 34
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
            sheet.largestUndimmedDetentIdentifier = nil
        }
        present(host, animated: true)
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        cancel()
    }

    private func cancel() {
        extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }
}

/// Pulls the shared URL (and page title when Safari provides one) out of the
/// extension items. Falls back to the first URL found in shared text.
enum SharedItemReader {
    struct Result {
        var url: String?
        var title: String?
    }

    static func read(from context: NSExtensionContext?) async -> Result {
        var result = Result()
        guard let items = context?.inputItems as? [NSExtensionItem] else { return result }
        for item in items {
            if result.title == nil, let text = item.attributedContentText?.string, !text.isEmpty, URL(string: text)?.scheme == nil {
                result.title = text
            }
            for provider in item.attachments ?? [] {
                if result.url == nil, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let loaded = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) {
                        if let url = loaded as? URL { result.url = url.absoluteString }
                        else if let data = loaded as? Data, let s = String(data: data, encoding: .utf8) { result.url = s }
                    }
                }
                if result.url == nil, provider.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier) {
                    // Safari "web page" payload: results of a JS preprocessor.
                    if let loaded = try? await provider.loadItem(forTypeIdentifier: UTType.propertyList.identifier),
                       let dict = loaded as? [String: Any],
                       let results = dict[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any] {
                        result.url = results["URL"] as? String ?? results["url"] as? String
                        result.title = result.title ?? results["title"] as? String
                    }
                }
                if result.url == nil, provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let loaded = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier),
                       let text = loaded as? String {
                        result.url = firstURL(in: text)
                        if result.url == nil, result.title == nil { result.title = text }
                    }
                }
            }
        }
        return result
    }

    static func firstURL(in text: String) -> String? { URLDomain.firstURL(in: text) }
}
