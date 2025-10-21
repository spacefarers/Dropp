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
    @EnvironmentObject private var auth: AuthManager
    @State private var isSettingsMenuPresented = false
    @State private var isRefreshing = false

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

                // Bottom-left controls: Refresh (when logged in) + Hide + Settings
                HStack(spacing: 8) {
                    if auth.isLoggedIn {
                        refreshButton
                    }
                    hideButton
                    settingsButton
                }
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .zIndex(2)

                if isSettingsMenuPresented {
                    // Dismiss area
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture { isSettingsMenuPresented = false }
                        .zIndex(1)

                    // Settings menu shown just above the buttons in the bottom-left
                    settingsMenu
                        .offset(x: 10, y: -48) // small right shift, pop upward from bottom-left
                        .zIndex(2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
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

    private var refreshButton: some View {
        Group {
            if isRefreshing {
                // Spinner while refreshing
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .frame(width: 28, height: 28) // keep button footprint consistent
                    .padding(6)
                    .help("Refreshing…")
            } else {
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    isRefreshing = true
                    Task {
                        defer { isRefreshing = false }
                        await refreshCloudInventory()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .foregroundStyle(iconColor)
                    .frame(width: 28, height: 28)
                    .padding(6)
                }
                .buttonStyle(.plain)
                .disabled(isRefreshing)
                .help("Refresh Cloud State")
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isRefreshing)
    }

    private var hideButton: some View {
        Button {
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(name: .requestForceHideWindow, object: nil)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "eye.slash")
            }
            .foregroundStyle(iconColor)
            .padding(6)
        }
        .buttonStyle(.plain)
        .help("Hide Window")
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
        .help("Settings")
    }

    private var settingsMenu: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Auth section
            if auth.isLoggedIn {
                Button {
                    isSettingsMenuPresented = false
                    auth.logout()
                } label: {
                    Label {
                        Text("Sign out of \(auth.identitySummary)")
                    } icon: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                    }
                }
            } else {
                Button {
                    isSettingsMenuPresented = false
                    auth.openLogin()
                } label: {
                    Label("Login…", systemImage: "person.crop.circle.badge.plus")
                }
            }

            Divider()

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

    private var backgroundColor: Color { Palette.background }
    private var surfaceColor: Color { Palette.surface }
    private var iconColor: Color { Palette.icon }
    private var borderColor: Color { Palette.border }
    private var highlightBorderColor: Color { Palette.accent.opacity(0.35) }
    private var shadowColor: Color { Palette.shadow }
    private var accentColor: Color { Palette.accent }

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

    // MARK: - Cloud refresh

    private func refreshCloudInventory() async {
        guard auth.isLoggedIn else { return }
        do {
            let result = try await DroppAPIClient.shared.list()
            // Update storage caps
            shelf.cloudStorageUsed = result.storageUsed
            shelf.cloudStorageCap = result.storageCap

            // Build a lookup for cloud files by filename
            let cloudByName: [String: ShelfItem.CloudFileInfo] = Dictionary(
                uniqueKeysWithValues: result.files.map { ($0.filename, $0) }
            )

            // Update each local item’s state
            for item in shelf.items {
                let localName = item.resolvedURL().lastPathComponent
                if let info = cloudByName[localName] {
                    item.cloudInfo = info
                    item.cloudState = .both
                } else {
                    // Not present in cloud; keep/seed minimal info
                    item.cloudInfo = ShelfItem.CloudFileInfo(
                        filename: localName,
                        size: (try? item.resolvedURL().resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0,
                        contentType: "application/octet-stream"
                    )
                    item.cloudState = .localOnly
                }
            }
        } catch {
            NSLog("Failed to refresh cloud inventory: \(error.localizedDescription)")
            showAlert(title: "Refresh Failed", message: error.localizedDescription)
        }
    }

    private func showAlert(title: String, message: String) {
        #if os(macOS)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
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

    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var shelf: Shelf
    @State private var isHovering = false

    var body: some View {
        let url = item.resolvedURL()
        return rowContent(for: url)
    }

    @ViewBuilder
    private func rowContent(for url: URL) -> some View {
        HStack(alignment: .center, spacing: 10) {
            DraggableRowContainer(item: item, onExternalMove: { movedItem in
                onRemove(movedItem)
            }) {
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
                // Cloud action (only shown when logged in)
                if auth.isLoggedIn {
                    if item.isCloudBusy {
                        // Spinner styled like the action button to keep layout/feel identical
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(iconBackgroundColor)
                                .shadow(color: Palette.shadow.opacity(0.18), radius: 22 * 0.28, y: 22 * 0.18)
                            ProgressView()
                                .progressViewStyle(.circular)
                                .controlSize(.small)
                                .scaleEffect(0.9) // visually centered for 22x22
                                .tint(Palette.accent)
                        }
                        .frame(width: 22, height: 22)
                        .help("Working…")
                    } else {
                        ShelfActionButton(
                            systemName: cloudIconName(for: item.cloudState),
                            tooltip: cloudTooltip(for: item.cloudState),
                            backgroundColor: iconBackgroundColor,
                            foregroundColor: Palette.accent,
                            size: 22,
                            cornerRadius: 6
                        ) {
                            handleCloudAction(for: item)
                        }
                        .disabled(item.isCloudBusy)
                    }
                }

                // Remove on top, Reveal below (existing)
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
                .disabled(item.isCloudBusy)

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
                .disabled(item.isCloudBusy)
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

    private func handleCloudAction(for item: ShelfItem) {
        switch item.cloudState {
        case .localOnly:
            // Preflight quota check then upload
            item.cloudActivity = .uploading
            Task { @MainActor in
                defer { item.cloudActivity = .idle }
                do {
                    let fileSize = try determineLocalFileSize(item: item)
                    let used = shelf.cloudStorageUsed
                    let cap = shelf.cloudStorageCap

                    if cap > 0 && used + fileSize > cap {
                        showQuotaAlert(needed: fileSize, used: used, cap: cap)
                        return
                    }

                    try await DroppAPIClient.shared.upload(item: item)

                    // Update state to reflect upload
                    item.cloudState = .both
                    if item.cloudInfo == nil {
                        item.cloudInfo = ShelfItem.CloudFileInfo(
                            filename: item.resolvedURL().lastPathComponent,
                            size: fileSize,
                            contentType: "application/octet-stream"
                        )
                    } else {
                        item.cloudInfo?.size = fileSize
                    }
                    shelf.cloudStorageUsed = used + fileSize
                } catch {
                    showErrorAlert(title: "Upload Failed", message: error.localizedDescription)
                }
            }
        case .cloudOnly:
            // TODO: Implement download wiring
            NSLog("Download action tapped for \(item.resolvedURL().lastPathComponent)")
        case .both:
            // TODO: Implement cloud remove wiring
            NSLog("Remove-from-cloud action tapped for \(item.resolvedURL().lastPathComponent)")
        }
    }

    private func determineLocalFileSize(item: ShelfItem) throws -> Int64 {
        if let s = item.cloudInfo?.size, s > 0 { return s }
        let url = item.resolvedURL()
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        if let size = values.fileSize { return Int64(size) }
        return 0
    }

    private func showQuotaAlert(needed: Int64, used: Int64, cap: Int64) {
        #if os(macOS)
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file

        let neededStr = formatter.string(fromByteCount: needed)
        let usedStr = formatter.string(fromByteCount: used)
        let capStr = formatter.string(fromByteCount: cap)

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Not Enough Cloud Storage"
        alert.informativeText = "This file (\(neededStr)) would exceed your cloud storage cap (\(usedStr) used of \(capStr))."
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        #endif
    }

    private func showErrorAlert(title: String, message: String) {
        #if os(macOS)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        #endif
    }

    private func cloudIconName(for state: ShelfItem.CloudPresence) -> String {
        switch state {
        case .localOnly:
            return "icloud.and.arrow.up"
        case .cloudOnly:
            return "icloud.and.arrow.down"
        case .both:
            return "icloud"
        }
    }

    private func cloudTooltip(for state: ShelfItem.CloudPresence) -> String {
        switch state {
        case .localOnly:
            return "Upload to Cloud"
        case .cloudOnly:
            return "Download from Cloud"
        case .both:
            return "Remove from Cloud"
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
    let onExternalMove: ((ShelfItem) -> Void)?

    init(item: ShelfItem,
         onExternalMove: ((ShelfItem) -> Void)? = nil,
         @ViewBuilder content: () -> Content) {
        self.item = item
               self.onExternalMove = onExternalMove
        self.content = content()
    }

    func makeNSView(context: Context) -> DraggableContainerView<Content> {
        DraggableContainerView(item: item, rootView: content, onExternalMove: onExternalMove)
    }

    func updateNSView(_ nsView: DraggableContainerView<Content>, context: Context) {
        nsView.update(item: item, rootView: content, onExternalMove: onExternalMove)
    }
}

private final class DraggableContainerView<Content: View>: NSView, NSDraggingSource {
    var item: ShelfItem
    private let hostingView: NSHostingView<Content>
    private var isDraggingSessionActive = false
    private var mouseDownEvent: NSEvent?
    private var onExternalMove: ((ShelfItem) -> Void)?
    private var didStartDragThisMouseDown = false

    init(item: ShelfItem, rootView: Content, onExternalMove: ((ShelfItem) -> Void)?) {
        self.item = item
        self.onExternalMove = onExternalMove
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

    func update(item: ShelfItem, rootView: Content, onExternalMove: ((ShelfItem) -> Void)?) {
        self.item = item
        self.onExternalMove = onExternalMove
        hostingView.rootView = rootView
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        didStartDragThisMouseDown = false        // allow one drag for this press
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        // Only allow one start per mouse-down; do nothing after Esc-cancel until mouseUp
        if !isDraggingSessionActive && !didStartDragThisMouseDown {
            let dragEvent = mouseDownEvent ?? event
            didStartDragThisMouseDown = true
            startDraggingSession(with: dragEvent)
            mouseDownEvent = nil
        }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        // Reset so the next press can start a new drag
        didStartDragThisMouseDown = false
        mouseDownEvent = nil
        super.mouseUp(with: event)
    }

    private func startDraggingSession(with event: NSEvent) {
        guard let fileURL = item.beginDragAccess() else { return }
        let draggingItem = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
        draggingItem.setDraggingFrame(bounds, contents: snapshotImage() ?? hostingView)

        isDraggingSessionActive = true
        let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true // explicit, matches your expectation
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

    private func isInsideAnyAppWindow(_ screenPoint: NSPoint) -> Bool {
        for window in NSApp.windows where window.isVisible {
            if window.frame.contains(screenPoint) { return true }
        }
        return false
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        switch context {
        case .withinApplication:
            return [.move, .copy]
        case .outsideApplication:
            return [.move, .copy]
        @unknown default:
            return [.move, .copy]
        }
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        isDraggingSessionActive = false
        item.endDragAccess()

        let droppedInsideApp = isInsideAnyAppWindow(screenPoint)

        // Remove only if the drop completed outside the app.
        // (operation.isEmpty means cancel/fail; keep item in shelf.)
        if !droppedInsideApp && !operation.isEmpty {
            onExternalMove?(item)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(Shelf())
        .environmentObject(AuthManager.shared)
}

