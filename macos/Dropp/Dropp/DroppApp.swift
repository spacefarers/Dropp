//
//  DroppApp.swift
//  Dropp
//
//  Created by Michael Yang on 10/19/25.
//

import SwiftUI
import AppKit
import QuartzCore

final class FileDragStartObserver {
    private var monitors: [Any] = []
    private var lastFiredChangeCount: Int = -1   // which drag we've already reported
    private var isDragging = false

    func start() {
        let pb = NSPasteboard(name: .drag)
        let currentCC = pb.changeCount
        lastFiredChangeCount = currentCC
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            self?.handleDragged()
        } as Any)

        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            self?.handleMouseUp()
        } as Any)
    }

    func stop() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
    }

    private func handleDragged() {
        let pb = NSPasteboard(name: .drag)
        let currentCC = pb.changeCount

        guard currentCC != lastFiredChangeCount else { return }
        lastFiredChangeCount = currentCC

        let knownFileTypes: Set<NSPasteboard.PasteboardType> = [.fileURL, .URL]
        let types = Set(pb.types ?? [])
        let isLikelyFileDrag = !knownFileTypes.isDisjoint(with: types)

        if isLikelyFileDrag {
            isDragging = true
            onFileDragStart?([])
        }
    }

    private func handleMouseUp() {
        guard isDragging else { return }
        isDragging = false
        onFileDragEnd?([])
    }

    var onFileDragStart: (([URL]) -> Void)?
    var onFileDragEnd: (([URL]) -> Void)?
}

final class WindowVisibilityController {
    private weak var window: NSWindow?
    private weak var shelf: Shelf?
    private(set) var isVisible: Bool = false
    private var shouldOrderOutAfterFade = false
    private let animationDuration: TimeInterval = 0.2

    func attach(window: NSWindow, shelf: Shelf) {
        self.window = window
        self.shelf = shelf
        isVisible = window.isVisible
    }

    func setVisible(_ visible: Bool) {
        // Never hide the window if there are items in the shelf
        if !visible, let shelf = shelf, !shelf.items.isEmpty {
            return
        }

        if visible == isVisible { return }
        DispatchQueue.main.async {
            guard let window = self.window else {
                NSLog("WindowVisibilityController has no window to \(visible ? "show" : "hide")")
                return
            }

            if visible {
                self.shouldOrderOutAfterFade = false
                WindowLayout.applySizeAndPosition(window)

                if !window.isVisible {
                    window.alphaValue = 0
                }
                window.orderFrontRegardless()

                NSAnimationContext.runAnimationGroup { context in
                    context.duration = self.animationDuration
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    window.animator().alphaValue = 1
                }
            } else {
                if !window.isVisible {
                    window.orderOut(nil)
                    window.alphaValue = 1
                } else {
                    self.shouldOrderOutAfterFade = true

                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = self.animationDuration
                        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                        window.animator().alphaValue = 0
                    } completionHandler: { [weak self, weak window] in
                        guard let self = self, let window = window else { return }
                        if self.shouldOrderOutAfterFade {
                            window.orderOut(nil)
                            window.alphaValue = 1
                            self.shouldOrderOutAfterFade = false
                        }
                    }
                }
            }

            self.isVisible = visible
            NSLog(visible ? "Showing window" : "Hiding window")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let shelf = Shelf()
    private let fileDragObserver = FileDragStartObserver()
    private let visibilityController = WindowVisibilityController()
    private var mainWindow: NSPanel?
    private var notificationTokens: [NSObjectProtocol] = []
    private var skipNextActivationUpdate = false
    private var hasShownDiskAccessAlert = false
    private var globalMouseDownMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        promptForDiskAccessIfNeeded()

        let rootView = ContentView()
            .environmentObject(shelf)

        let hostingController = NSHostingController(rootView: rootView)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: WindowLayout.targetSize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        WindowLayout.configure(panel)
        panel.orderOut(nil)

        visibilityController.attach(window: panel, shelf: shelf)
        mainWindow = panel

        wireDragCallbacks()
        installObservers()
        installGlobalMouseMonitor()

        // Surface the window immediately on launch.
        showWindowSuppressingActivationUpdate()
    }

    func applicationWillTerminate(_ notification: Notification) {
        fileDragObserver.stop()
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
        notificationTokens.removeAll()
        if let monitor = globalMouseDownMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseDownMonitor = nil
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        promptForDiskAccessIfNeeded()
        showWindowSuppressingActivationUpdate()
        return true
    }

    private func wireDragCallbacks() {
        fileDragObserver.onFileDragStart = { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.showWindowSuppressingActivationUpdate()
            }
        }
        fileDragObserver.onFileDragEnd = { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                // Allow the drop callback to finish mutating the shelf before evaluating.
                try? await Task.sleep(nanoseconds: 120_000_000)
                self.visibilityController.setVisible(false)
            }
        }
        fileDragObserver.start()
    }

    private func installObservers() {
        if let window = mainWindow {
            notificationTokens.append(
                NotificationCenter.default.addObserver(
                    forName: NSWindow.didBecomeMainNotification,
                    object: window,
                    queue: .main
                ) { note in
                    guard let window = note.object as? NSWindow else { return }
                    WindowLayout.configure(window)
                }
            )
        }

        notificationTokens.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let window = self?.mainWindow else { return }
                    WindowLayout.applySizeAndPosition(window)
                }
            }
        )

        notificationTokens.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleApplicationBecameActive()
                }
            }
        )

        notificationTokens.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.visibilityController.setVisible(false)
                }
            }
        )
    }

    private func installGlobalMouseMonitor() {
        globalMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                guard let window = self.mainWindow, window.isVisible else { return }
                let mouseLocation = NSEvent.mouseLocation
                if !window.frame.contains(mouseLocation) {
                    self.visibilityController.setVisible(false)
                }
            }
        }
    }

    private func handleApplicationBecameActive() {
        if skipNextActivationUpdate {
            skipNextActivationUpdate = false
            return
        }
        visibilityController.setVisible(false)
    }

    private func showWindowSuppressingActivationUpdate() {
        skipNextActivationUpdate = NSApp.isActive
        visibilityController.setVisible(true)
    }

    private func promptForDiskAccessIfNeeded() {
        guard !hasShownDiskAccessAlert else { return }
        guard !DiskAccessController.shared.isAccessGranted() else { return }
        hasShownDiskAccessAlert = true
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Dropp Needs Full Disk Access"
        alert.informativeText = "Dropp can only pin and move your files if Full Disk Access is enabled. Without it, the shelf cannot stay in sync."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            DiskAccessController.shared.requestAccess()
        }
    }
}

@main
struct DroppApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

private enum WindowLayout {
    static let targetSize = NSSize(width: 170, height: 400)

    static func configure(_ window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true

        window.isOpaque = false
        window.backgroundColor = .clear

        window.isMovable = false
        window.isMovableByWindowBackground = false
        window.styleMask.remove(.resizable)

        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        window.collectionBehavior.remove(.fullScreenPrimary)
        window.collectionBehavior.remove(.fullScreenAuxiliary)

        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = 10
            contentView.layer?.masksToBounds = true
        }

        if let hostingView = window.contentView?.subviews.first {
            hostingView.wantsLayer = true
            hostingView.layer?.cornerRadius = 10
            hostingView.layer?.masksToBounds = true
        }

        applySizeAndPosition(window)
    }

    static func applySizeAndPosition(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame

        var frame = window.frame
        frame.size = targetSize

        let x = visible.maxX - targetSize.width
        let y = visible.midY - (targetSize.height / 2.0)
        frame.origin = NSPoint(x: x, y: y)

        window.setFrame(frame, display: true, animate: false)

        // Use a floating level so popups/menus can appear above.
        window.level = .floating
        window.hasShadow = true

        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = 10
            contentView.layer?.masksToBounds = true
        }

        if let hostingView = window.contentView?.subviews.first {
            hostingView.wantsLayer = true
            hostingView.layer?.cornerRadius = 10
            hostingView.layer?.masksToBounds = true
        }
    }
}
