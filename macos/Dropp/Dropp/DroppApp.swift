//
//  DroppApp.swift
//  Dropp
//
//  Created by Michael Yang on 10/19/25.
//

import SwiftUI
import AppKit
import QuartzCore
import Carbon.HIToolbox

extension Notification.Name {
    static let requestForceHideWindow = Notification.Name("RequestForceHideWindow")
}

final class FileDragStartObserver {
    private var monitors: [Any] = []
    private var lastFiredChangeCount: Int = -1
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

    func setVisible(_ visible: Bool, force: Bool = false) {
        if !visible, !force, let shelf = shelf, !shelf.items.isEmpty {
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
            NSLog(visible ? "Showing window" : "Hiding window\(force ? " (forced)" : "")")
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

    // Hotkey storage
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyEventHandler: EventHandlerRef?

    private let auth = AuthManager.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        auth.loadFromStorage()

        promptForDiskAccessIfNeeded()

        let rootView = ContentView()
            .environmentObject(shelf)
            .environmentObject(auth)

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
        registerGlobalHotKeyF10()

        showWindowSuppressingActivationUpdate()

        Task { @MainActor in
            await refreshCloudInventoryOnLaunch()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        fileDragObserver.stop()
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
        notificationTokens.removeAll()
        if let monitor = globalMouseDownMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseDownMonitor = nil
        }
        unregisterGlobalHotKey()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        promptForDiskAccessIfNeeded()
        showWindowSuppressingActivationUpdate()
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if AuthManager.shared.handleCallback(url: url) {
                NSApp.activate(ignoringOtherApps: true)
                showWindowSuppressingActivationUpdate()

                Task { @MainActor in
                    await refreshCloudInventoryOnLaunch()
                }
            }
        }
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
                try? await Task.sleep(nanoseconds: 300_000_000)
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

        notificationTokens.append(
            NotificationCenter.default.addObserver(
                forName: .shelfBecameEmpty,
                object: shelf,
                queue: .main
            ) { [weak self] _ in
                self?.visibilityController.setVisible(false)
            }
        )

        notificationTokens.append(
            NotificationCenter.default.addObserver(
                forName: .requestForceHideWindow,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.visibilityController.setVisible(false, force: true)
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

    // MARK: - Global Hotkey (F10)

    private func registerGlobalHotKeyF10() {
        // Install a handler for hotkey pressed events
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let statusInstall = InstallEventHandler(GetApplicationEventTarget(), { (_, event, userData) -> OSStatus in
            guard let userData = userData else { return noErr }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            delegate.handleGlobalHotKey()
            return noErr
        }, 1, &eventSpec, userData, &hotKeyEventHandler)

        if statusInstall != noErr {
            NSLog("Failed to install hotkey event handler: \(statusInstall)")
            hotKeyEventHandler = nil
            return
        }

        // Register the F10 hotkey (no modifiers)
        var hotKeyID = EventHotKeyID(signature: OSType(0x44525050), id: 1) // 'DRPP'
        let statusReg = RegisterEventHotKey(UInt32(kVK_F10), 0, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)

        if statusReg != noErr {
            NSLog("Failed to register F10 hotkey: \(statusReg)")
            // Clean up handler if registration failed
            if let handler = hotKeyEventHandler {
                RemoveEventHandler(handler)
                hotKeyEventHandler = nil
            }
            hotKeyRef = nil
        } else {
            NSLog("Registered global hotkey: F10")
        }
    }

    private func unregisterGlobalHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handler = hotKeyEventHandler {
            RemoveEventHandler(handler)
            hotKeyEventHandler = nil
        }
    }

    private func handleGlobalHotKey() {
        let currentlyVisible = mainWindow?.isVisible ?? false
        let newVisible = !currentlyVisible
        visibilityController.setVisible(newVisible, force: true)
        if newVisible {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // Prompt user to grant Full Disk Access if we detect restricted access.
    private func promptForDiskAccessIfNeeded() {
        guard !hasShownDiskAccessAlert else { return }

        let granted = DiskAccessController.shared.isAccessGranted()
        guard !granted else { return }

        hasShownDiskAccessAlert = true

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Additional Disk Access Recommended"
        alert.informativeText = """
        To work reliably with files across your Mac (including some protected locations), Dropp may require Full Disk Access.

        You can grant this in System Settings → Privacy & Security → Full Disk Access. This is optional, but without it certain files may be unreadable.
        """
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Not Now")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            DiskAccessController.shared.requestAccess()
        }
    }

    // MARK: - Initial cloud sync

    private func refreshCloudInventoryOnLaunch() async {
        guard auth.isLoggedIn else { return }
        do {
            let result = try await DroppAPIClient.shared.list()
            shelf.cloudStorageUsed = result.storageUsed
            shelf.cloudStorageCap = result.storageCap

            let cloudByName: [String: ShelfItem.CloudFileInfo] = Dictionary(uniqueKeysWithValues: result.files.map { ($0.filename, $0) })
            let cloudById: [String: ShelfItem.CloudFileInfo] = Dictionary(uniqueKeysWithValues: result.files.compactMap { info in
                if let id = info.id { return (id, info) } else { return nil }
            })

            let existingNames = Set(shelf.items.map { $0.displayName })

            for item in shelf.items {
                if let linkedId = CloudLinkStore.shared.lookupCloudId(forBookmarkKey: item.bookmarkKey),
                   let info = cloudById[linkedId] {
                    item.cloudInfo = info
                    item.cloudState = item.isPhantom ? .cloudOnly : .both
                    continue
                }

                let name = item.displayName
                if let info = cloudByName[name] {
                    item.cloudInfo = info
                    item.cloudState = item.isPhantom ? .cloudOnly : .both
                } else {
                    item.cloudState = item.isPhantom ? .cloudOnly : .localOnly
                }
            }

            for info in result.files where !existingNames.contains(info.filename) {
                shelf.addPhantomCloudItem(
                    filename: info.filename,
                    size: info.size,
                    contentType: info.contentType,
                    id: info.id,
                    downloadURL: info.downloadURL
                )
            }

            if !result.files.isEmpty {
                visibilityController.setVisible(true)
            }

            NSLog("Initial cloud inventory synced: \(result.files.count) file(s) in cloud.")
        } catch {
            NSLog("Initial cloud inventory sync failed: \(error.localizedDescription)")
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
    static let targetSize = NSSize(width: 160, height: 400)

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
