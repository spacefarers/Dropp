import SwiftUI
import AppKit

final class DropView: NSView {
    var onDrop: (([URL]) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            registerForDraggedTypes([.fileURL])
        } else {
            unregisterDraggedTypes()
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = sender.draggingPasteboard
            .readObjects(forClasses: [NSURL.self], options: opts) as? [URL],
              !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }
}

struct DropContainer<Content: View>: NSViewRepresentable {
    let onDrop: ([URL]) -> Void
    let content: Content

    init(onDrop: @escaping ([URL]) -> Void, @ViewBuilder content: () -> Content) {
        self.onDrop = onDrop
        self.content = content()
    }

    func makeNSView(context: Context) -> DropView {
        let dropView = DropView()
        dropView.onDrop = onDrop

        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        dropView.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: dropView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: dropView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: dropView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: dropView.bottomAnchor)
        ])

        return dropView
    }

    func updateNSView(_ nsView: DropView, context: Context) {
        nsView.onDrop = onDrop

        guard let hostingView = nsView.subviews.first as? NSHostingView<Content> else {
            return
        }
        hostingView.rootView = content
    }
}
