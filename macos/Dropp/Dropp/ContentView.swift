//
//  ContentView.swift
//  Dropp
//
//  Created by Michael Yang on 10/19/25.
//

import SwiftUI
import AppKit

private enum Palette {
    static let background = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let accent = Color(nsColor: .controlAccentColor)
    static let border = Color.black.opacity(0.08)
    static let shadow = Color.black.opacity(0.18)
    static let icon = Color(nsColor: .secondaryLabelColor)
}

struct ContentView: View {
    @EnvironmentObject private var shelf: Shelf
    @State private var isSettingsMenuPresented = false

    var body: some View {
        DropContainer(onDrop: handleDrop) {
            ZStack(alignment: .bottomLeading) {
                backgroundColor
                    .ignoresSafeArea()
                    .zIndex(0)

                contentLayer
                    .padding(.horizontal, 8)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .zIndex(1)

                settingsButton
                    .padding(10)
                    .zIndex(2)

                if isSettingsMenuPresented {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture { isSettingsMenuPresented = false }
                        .zIndex(1)

                    settingsMenu
                        .offset(x: 10, y: -48)
                        .zIndex(2)
                }
            }
        }
    }

    private var contentLayer: some View {
        Group {
            if shelf.items.isEmpty {
                emptyStateView
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                itemsListView
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.1))
                    .frame(width: 84, height: 84)
                Image(systemName: "tray.and.arrow.down")
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(iconColor)
                    .font(.system(size: 40, weight: .semibold))
            }

            VStack(spacing: 6) {
                Text("Drop files here")
                    .font(.system(size: 16, weight: .semibold))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .center)
    }

    private var itemsListView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack() {
                ForEach(shelf.items) { item in
                    ShelfItemRow(
                        item: item,
                        onRemove: removeItem,
                        onReveal: revealInFinder,
                        borderColor: borderColor,
                        highlightBorderColor: highlightBorderColor,
                        surfaceColor: surfaceColor,
                        shadowColor: shadowColor
                    )
                }
            }
            .padding(.top, 0)
            .padding(.bottom, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var settingsButton: some View {
        Button {
            NSApp.activate(ignoringOtherApps: true)
            isSettingsMenuPresented.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "gearshape.fill")
            }
            .foregroundStyle(iconColor)
            .padding(6)
        }
        .buttonStyle(.plain)
    }

    private var settingsMenu: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                isSettingsMenuPresented = false
                openAbout()
            } label: {
                Label("About Dropp", systemImage: "info.circle")
            }

            Divider()

            Button(role: .destructive) {
                isSettingsMenuPresented = false
                quitApp()
            } label: {
                Label("Quit Dropp", systemImage: "xmark.circle")
            }
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.plain)
        .padding(14)
        .frame(width: 180, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(surfaceColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(borderColor, lineWidth: 1)
                )
                .shadow(color: shadowColor.opacity(0.25), radius: 18, y: 8)
        )
    }

    // MARK: - Colors

    private var backgroundColor: Color {
        Palette.background
    }

    private var surfaceColor: Color {
        Palette.surface
    }

    private var iconColor: Color {
        Palette.icon
    }

    private var borderColor: Color {
        Palette.border
    }

    private var highlightBorderColor: Color {
        Palette.accent.opacity(0.35)
    }

    private var shadowColor: Color {
        Palette.shadow
    }

    private var accentColor: Color {
        Palette.accent
    }

    // MARK: - Actions

    private func openAbout() {
        #if os(macOS)
        NSApp.orderFrontStandardAboutPanel(nil)
        NSApp.activate(ignoringOtherApps: true)
        #endif
    }

    private func quitApp() {
        #if os(macOS)
        NSApp.terminate(nil)
        #endif
    }

    private func handleDrop(_ urls: [URL]) {
        shelf.add(urls)
    }

    private func removeItem(_ item: ShelfItem) {
        shelf.remove(item)
    }

    private func revealInFinder(_ item: ShelfItem) {
        #if os(macOS)
        let url = item.resolvedURL()
        NSWorkspace.shared.activateFileViewerSelecting([url])
        #endif
    }
}

private struct ShelfItemRow: View {
    @ObservedObject var item: ShelfItem
    let onRemove: (ShelfItem) -> Void
    let onReveal: (ShelfItem) -> Void
    let borderColor: Color
    let highlightBorderColor: Color
    let surfaceColor: Color
    let shadowColor: Color

    @State private var isHovering = false

    var body: some View {
        let url = item.resolvedURL()
        return rowContent(for: url)
    }

    @ViewBuilder
    private func rowContent(for url: URL) -> some View {
        HStack(alignment: .center, spacing: 10) {
            DraggableRowContainer(item: item) {
                VStack(spacing: 8) {
                    thumbnail(for: url)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: shadowColor.opacity(0.12), radius: 6, y: 3)

                    Text(truncatedDisplayName(for: url))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.primary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(width: 90, alignment: .leading)

            VStack(spacing: 6) {
                ShelfActionButton(
                    systemName: "magnifyingglass",
                    tooltip: "Reveal in Finder",
                    backgroundColor: iconBackgroundColor,
                    foregroundColor: iconColor,
                    size: 22,
                    cornerRadius: 6
                ) {
                    onReveal(item)
                }

                ShelfActionButton(
                    systemName: "xmark",
                    tooltip: "Remove",
                    backgroundColor: iconBackgroundColor,
                    foregroundColor: Color(nsColor: .systemRed),
                    size: 22,
                    cornerRadius: 6
                ) {
                    onRemove(item)
                }
            }
            .frame(width: 24)
            .opacity(isHovering ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: isHovering)
        }
        .frame(width: 140, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(surfaceColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isHovering ? highlightBorderColor : borderColor, lineWidth: 1)
                )
                .shadow(color: shadowColor.opacity(isHovering ? 0.25 : 0.12), radius: 18, y: isHovering ? 10 : 6)
        )
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture(count: 2) {
            open(item)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }

    private func thumbnail(for url: URL) -> Image {
        #if os(macOS)
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 64, height: 64)
        return Image(nsImage: icon)
        #else
        return Image(systemName: "doc")
        #endif
    }

    private var iconBackgroundColor: Color { Palette.surface.opacity(0.85) }
    private var iconColor: Color { Palette.icon }

    private func truncatedDisplayName(for url: URL, maxLength: Int = 10) -> String {
        let name = url.lastPathComponent
        guard name.count > maxLength else { return name }

        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count > 1 else {
            let prefix = name.prefix(maxLength)
            return "\(prefix)"
        }

        let extensionPart = parts.last ?? ""
        let base = name.dropLast(extensionPart.count + 1)
        if base.count <= maxLength {
            return "\(base).\(extensionPart)"
        }

        let prefix = base.prefix(maxLength)
        return "\(prefix)…\(extensionPart)"
    }

    private func open(_ item: ShelfItem) {
        #if os(macOS)
        let url = item.resolvedURL()
        NSWorkspace.shared.open(url)
        #endif
    }
}


private struct ShelfActionButton: View {
    let systemName: String
    let tooltip: String?
    let backgroundColor: Color
    let foregroundColor: Color
    let size: CGFloat
    let cornerRadius: CGFloat
    let action: () -> Void

    init(
        systemName: String,
        tooltip: String? = nil,
        backgroundColor: Color = Palette.accent,
        foregroundColor: Color = .white,
        size: CGFloat = 32,
        cornerRadius: CGFloat = 16,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.tooltip = tooltip
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
        self.size = size
        self.cornerRadius = cornerRadius
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: max(11, size * 0.45), weight: .semibold))
                .foregroundStyle(foregroundColor)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(backgroundColor)
                        .shadow(color: Palette.shadow.opacity(0.18), radius: size * 0.28, y: size * 0.18)
                )
        }
        .buttonStyle(.plain)
        .help(tooltip ?? "")
    }
}

// MARK: - Drag Support

private struct DraggableRowContainer<Content: View>: NSViewRepresentable {
    let item: ShelfItem
    let content: Content

    init(item: ShelfItem, @ViewBuilder content: () -> Content) {
        self.item = item
        self.content = content()
    }

    func makeNSView(context: Context) -> DraggableContainerView<Content> {
        DraggableContainerView(item: item, rootView: content)
    }

    func updateNSView(_ nsView: DraggableContainerView<Content>, context: Context) {
        nsView.update(item: item, rootView: content)
    }
}

private final class DraggableContainerView<Content: View>: NSView, NSDraggingSource {
    var item: ShelfItem
    private let hostingView: NSHostingView<Content>
    private var isDraggingSessionActive = false
    private var mouseDownEvent: NSEvent?

    init(item: ShelfItem, rootView: Content) {
        self.item = item
        self.hostingView = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        setupHostingView()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func setupHostingView() {
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    func update(item: ShelfItem, rootView: Content) {
        self.item = item
        hostingView.rootView = rootView
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if !isDraggingSessionActive {
            // Use the stored mouseDown event if available, otherwise use current event
            let dragEvent = mouseDownEvent ?? event
            startDraggingSession(with: dragEvent)
            mouseDownEvent = nil
        }
        super.mouseDragged(with: event)
    }

    private func startDraggingSession(with event: NSEvent) {
        guard let fileURL = item.beginDragAccess() else { return }
        let draggingItem = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
        draggingItem.setDraggingFrame(bounds, contents: snapshotImage() ?? hostingView)

        isDraggingSessionActive = true
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    private func snapshotImage() -> NSImage? {
        guard !bounds.isEmpty else { return nil }
        guard let representation = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: representation)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(representation)
        return image
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        switch context {
        case .withinApplication:
            return .move
        case .outsideApplication:
            return [.move, .copy]
        @unknown default:
            return [.move, .copy]
        }
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        isDraggingSessionActive = false
        item.endDragAccess()
    }
}

#Preview {
    ContentView()
        .environmentObject(Shelf())
}
