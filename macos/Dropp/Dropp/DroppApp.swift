//
//  DroppApp.swift
//  Dropp
//
//  Created by Michael Yang on 10/19/25.
//

import SwiftUI
import AppKit

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

    func attach(window: NSWindow) {
        self.window = window
        isVisible = window.isVisible
    }

    func setVisible(_ visible: Bool) {
        DispatchQueue.main.async {
            guard let window = self.window else {
                NSLog("WindowVisibilityController has no window to \(visible ? "show" : "hide")")
                return
            }

            if visible {
                WindowLayout.applySizeAndPosition(window)
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            } else {
                window.orderOut(nil)
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

    func applicationDidFinishLaunching(_ notification: Notification) {
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
    }

    func applicationWillTerminate(_ notification: Notification) {
        fileDragObserver.stop()
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
        notificationTokens.removeAll()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Prevent showing windows when clicking the dock icon
        false
    }

    private func wireDragCallbacks() {
        fileDragObserver.onFileDragStart = { [weak self] _ in
            self?.visibilityController.setVisible(true)
        }
        fileDragObserver.onFileDragEnd = { [weak self] _ in
            self?.visibilityController.setVisible(false)
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
    static let targetSize = NSSize(width: 200, height: 400)

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
