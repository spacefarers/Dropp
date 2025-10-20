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
    private var currentDragURLs: [URL] = []

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
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
           !urls.isEmpty {
            lastFiredChangeCount = currentCC
            isDragging = true
            currentDragURLs = urls
            onFileDragStart?(urls)
        }
    }

    private func handleMouseUp() {
        guard isDragging else { return }
        isDragging = false
        let pb = NSPasteboard(name: .drag)
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = (pb.readObjects(forClasses: [NSURL.self], options: options) as? [URL]) ?? currentDragURLs

        if !urls.isEmpty {
            onFileDragEnd?(urls)
        }
    }

    var onFileDragStart: (([URL]) -> Void)?
    var onFileDragEnd: (([URL]) -> Void)?
}

final class WindowVisibilityController {
    private weak var window: NSWindow?
    private(set) var isVisible: Bool = false
    private var shouldOrderOutAfterFade = false
    private let animationDuration: TimeInterval = 0.2

    func attach(window: NSWindow) {
        self.window = window
        isVisible = window.isVisible
    }

    func setVisible(_ visible: Bool) {
        if visible == isVisible { return }
        DispatchQueue.main.async {
            guard let window = self.window else {
                NSLog("WindowVisibilityController has no window to \(visible ? "show" : "hide")")
                return
            }

            if visible {
                self.shouldOrderOutAfterFade = false
                WindowLayout.applySizeAndPosition(window)
                NSApp.activate(ignoringOtherApps: true)

                if !window.isVisible {
                    window.alphaValue = 0
                }
                window.makeKeyAndOrderFront(nil)

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
    private var mainWindow: NSWindow?
    private var notificationTokens: [NSObjectProtocol] = []
    private var skipNextActivationUpdate = false
    private var isDraggingFiles = false
    private var hasShownDiskAccessAlert = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        promptForDiskAccessIfNeeded()

        let rootView = ContentView()
            .environmentObject(shelf)

        let hostingController = NSHostingController(rootView: rootView)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: WindowLayout.targetSize),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false

        WindowLayout.configure(window)
        window.orderOut(nil)

        visibilityController.attach(window: window)
        mainWindow = window

        wireDragCallbacks()
        installObservers()

        // Surface the window immediately on launch.
        showWindowSuppressingActivationUpdate()
    }

    func applicationWillTerminate(_ notification: Notification) {
        fileDragObserver.stop()
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
        notificationTokens.removeAll()
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
                self.isDraggingFiles = true
                self.showWindowSuppressingActivationUpdate()
            }
        }
        fileDragObserver.onFileDragEnd = { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.isDraggingFiles = false
                // Allow the drop callback to finish mutating the shelf before evaluating.
                try? await Task.sleep(nanoseconds: 120_000_000)
                self.updateVisibilityBasedOnShelf()
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
                guard let window = self?.mainWindow else { return }
                WindowLayout.applySizeAndPosition(window)
            }
        )

        notificationTokens.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.handleApplicationBecameActive()
            }
        )

        notificationTokens.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.updateVisibilityBasedOnShelf()
            }
        )
    }

    private func updateVisibilityBasedOnShelf() {
        if isDraggingFiles {
            return
        }
        if shelf.items.isEmpty {
            visibilityController.setVisible(false)
        } else {
            visibilityController.setVisible(true)
        }
    }

    private func handleApplicationBecameActive() {
        if skipNextActivationUpdate {
            skipNextActivationUpdate = false
            return
        }
        updateVisibilityBasedOnShelf()
    }

    private func showWindowSuppressingActivationUpdate() {
        skipNextActivationUpdate = true
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

        window.isMovable = false
        window.isMovableByWindowBackground = false
        window.styleMask.remove(.resizable)

        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        window.collectionBehavior.remove(.fullScreenPrimary)
        window.collectionBehavior.remove(.fullScreenAuxiliary)

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
    }
}
