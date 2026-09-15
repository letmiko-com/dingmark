import SwiftUI
import SafariServices

/// SFSafariViewController has no SwiftUI equivalent: the one mandatory
/// UIKit wrapper of the app. `entersReader` asks for Safari Reader when the
/// page offers it; `onFinish` fires when the user taps Done, so the caller
/// can drop its presentation state.
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    var entersReader = false
    var onFinish: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = entersReader
        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.dismissButtonStyle = .done
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
        context.coordinator.onFinish = onFinish
    }

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        var onFinish: () -> Void

        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) { onFinish() }
    }
}
