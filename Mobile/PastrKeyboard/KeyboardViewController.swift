import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class KeyboardViewController: UIInputViewController {
    private var hostingController: UIHostingController<PastrKeyboardView>?
    private var heightConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()
        configureKeyboardHeight()

        let hostingController = UIHostingController(rootView: makeKeyboardView())
        hostingController.view.backgroundColor = .clear
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)
        self.hostingController = hostingController
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hostingController?.rootView = makeKeyboardView()
    }

    private func makeKeyboardView() -> PastrKeyboardView {
        PastrKeyboardView(
            clips: PastrSharedClipCache.load(limit: 18),
            onClipTap: { [weak self] clip in
                self?.handleClipTap(clip) ?? .unavailable
            },
            onDelete: { [weak self] in
                self?.textDocumentProxy.deleteBackward()
            },
            onReturn: { [weak self] in
                self?.textDocumentProxy.insertText("\n")
            },
            onNextKeyboard: { [weak self] in
                self?.advanceToNextInputMode()
            }
        )
    }

    private func configureKeyboardHeight() {
        heightConstraint?.isActive = false
        let constraint = view.heightAnchor.constraint(equalToConstant: 292)
        constraint.priority = .defaultHigh
        constraint.isActive = true
        heightConstraint = constraint
    }

    private func handleClipTap(_ clip: PastrClip) -> PastrKeyboardActionResult {
        switch clip.type {
        case .image:
            return copyImageClipToPasteboard(clip) ? .copied : .unavailable
        case .link:
            guard clip.hasWebURL else {
                return .unavailable
            }
            textDocumentProxy.insertText(clip.insertText)
            return .inserted
        case .text, .richText, .file, .other:
            let text = clip.insertText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                return .unavailable
            }
            textDocumentProxy.insertText(text)
            return .inserted
        }
    }

    private func copyImageClipToPasteboard(_ clip: PastrClip) -> Bool {
        guard let imageData = clip.imageData,
              UIImage(data: imageData) != nil else {
            return false
        }

        UIPasteboard.general.setItems(
            [[UTType.png.identifier: imageData]],
            options: [:]
        )
        return true
    }
}
