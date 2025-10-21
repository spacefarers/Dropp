//
//  Shelf.swift
//  Dropp
//
//  Created by Michael Yang on 10/19/25.
//

import Foundation
import Combine
import AppKit

extension Notification.Name {
    static let shelfBecameEmpty = Notification.Name("ShelfBecameEmpty")
}

@MainActor
final class Shelf: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []

    // Latest cloud storage info (updated via refresh)
    @Published var cloudStorageUsed: Int64 = 0
    @Published var cloudStorageCap: Int64 = 0

    func add(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        for url in urls {
            let standardized = url.standardizedFileURL
            // Check if we already have this file by comparing resolved URLs
            let alreadyExists = items.contains { item in
                // Compare by filename for robustness; local duplicates avoided by exact URL
                let existingName = item.displayName
                return existingName == standardized.lastPathComponent
                    || item.resolvedURL().standardizedFileURL == standardized
            }
            if !alreadyExists {
                items.append(ShelfItem(url: standardized))
            }
        }
        logContents()
    }

    func addPhantomCloudItem(filename: String, size: Int64, contentType: String, id: String?, downloadURL: URL?) {
        // Avoid duplicates by filename
        if items.contains(where: { $0.displayName == filename }) { return }
        let info = ShelfItem.CloudFileInfo(filename: filename, size: size, contentType: contentType, id: id, downloadURL: downloadURL)
        let phantom = ShelfItem(cloudOnly: info)
        items.append(phantom)
        logContents()
    }

    func remove(_ item: ShelfItem) {
        guard let index = items.firstIndex(of: item) else { return }
        items.remove(at: index)
        NSLog("Removed item from shelf. Remaining count: \(items.count)")
        logContents()
        if items.isEmpty {
            NotificationCenter.default.post(name: .shelfBecameEmpty, object: self)
        }
    }

    func clear() {
        items.removeAll()
        NSLog("Shelf cleared.")
        logContents()
        NotificationCenter.default.post(name: .shelfBecameEmpty, object: self)
    }

    func syncCloudPresence(with cloudFilenames: Set<String>) {
        var removedCloudOnly: [String] = []
        var demotedToLocal: [String] = []

        items.removeAll { item in
            let filename = item.displayName
            let existsInCloud = cloudFilenames.contains(filename)

            if item.cloudState == .cloudOnly && !existsInCloud {
                // Remove cloud-only items that no longer exist in the cloud
                removedCloudOnly.append(filename)
                return true
            } else if item.cloudState == .both && !existsInCloud {
                // For items that are both local and cloud, demote to local-only
                item.cloudState = .localOnly
                item.cloudInfo = nil
                demotedToLocal.append(filename)
            }

            return false
        }

        if !removedCloudOnly.isEmpty {
            NSLog("Removed \(removedCloudOnly.count) stale cloud-only item(s): \(removedCloudOnly)")
        }
        if !demotedToLocal.isEmpty {
            NSLog("Demoted \(demotedToLocal.count) item(s) to local-only: \(demotedToLocal)")
        }

        if !removedCloudOnly.isEmpty || !demotedToLocal.isEmpty {
            logContents()
        }
    }

    private func logContents() {
        let entries = items.map { item -> String in
            let state: String
            switch item.cloudState {
            case .localOnly: state = "localOnly"
            case .cloudOnly: state = "cloudOnly"
            case .both:      state = "both"
            }
            return "\(item.displayName) [\(state)]"
        }
        NSLog("Shelf now has \(items.count) item(s): \(entries)")
    }
}

@MainActor
final class ShelfItem: ObservableObject, Identifiable, Hashable {
    let id = UUID()
    private var bookmarkData: Data
    private var bookmarkUsesSecurityScope = false
    private var isAccessingResource = false

    // Whether this item was created from cloud inventory only (no local file yet)
    @Published private(set) var isPhantom: Bool = false

    // MARK: - Cloud/UI State

    enum CloudPresence: Equatable {
        case localOnly
        case cloudOnly
        case both
    }

    struct CloudFileInfo: Equatable {
        var filename: String
        var size: Int64
        var contentType: String
        var id: String?
        var downloadURL: URL?
    }

    // Cloud presence/state for this item; UI reads this to decide the icon
    @Published var cloudState: CloudPresence = .localOnly

    // Optional metadata about the file for cloud interactions
    @Published var cloudInfo: CloudFileInfo?

    // Activity state to drive spinners/disable actions
    enum CloudActivity: Equatable {
        case idle
        case uploading
        case downloading
        case removing
    }
    @Published var cloudActivity: CloudActivity = .idle

    var isCloudBusy: Bool { cloudActivity != .idle }

    // A user-facing name regardless of whether the item has a local file
    var displayName: String {
        cloudInfo?.filename ?? resolvedURL().lastPathComponent
    }

    // A stable key for persisting link mappings
    var bookmarkKey: String {
        bookmarkData.base64EncodedString()
    }

    // MARK: - Initializers

    // Local file initializer
    init(url: URL) {
        do {
            bookmarkData = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            bookmarkUsesSecurityScope = true
        } catch {
            NSLog("⚠️ Failed to create security-scoped bookmark for \(url.lastPathComponent): \(error.localizedDescription)")
            do {
                bookmarkData = try url.bookmarkData(
                    options: [],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                bookmarkUsesSecurityScope = false
            } catch {
                NSLog("❌ Failed to create bookmark: \(url.lastPathComponent) — \(error.localizedDescription)")
                bookmarkData = Data()
                bookmarkUsesSecurityScope = false
            }
        }

        self.isAccessingResource = false
        self.isPhantom = false

        if !bookmarkData.isEmpty {
            NSLog("✅ Added: \(url.lastPathComponent)")
        } else {
            NSLog("❌ Failed to add: \(url.lastPathComponent)")
        }

        // Seed minimal info for UI; can be refined on refresh
        self.cloudInfo = ShelfItem.CloudFileInfo(
            filename: url.lastPathComponent,
            size: (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0,
            contentType: "application/octet-stream",
            id: nil,
            downloadURL: nil
        )
        self.cloudState = .localOnly
    }

    // Cloud-only phantom initializer
    init(cloudOnly info: CloudFileInfo) {
        self.bookmarkData = Data()
        self.bookmarkUsesSecurityScope = false
        self.isAccessingResource = false
        self.isPhantom = true
        self.cloudInfo = info
        self.cloudState = .cloudOnly
    }

    // After downloading, adopt a local file and transition out of phantom mode
    func adoptLocalFile(at url: URL) {
        do {
            bookmarkData = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            bookmarkUsesSecurityScope = true
            isPhantom = false

            // Update size/contentType if we can
            let vals = try? url.resourceValues(forKeys: [.fileSizeKey, .typeIdentifierKey])
            if var info = cloudInfo {
                if let s = vals?.fileSize { info.size = Int64(s) }
                cloudInfo = info
                // If we have a cloud id, persist the link now that we have a bookmark
                if let cid = info.id {
                    CloudLinkStore.shared.link(cloudId: cid, toBookmarkKey: bookmarkKey)
                }
            } else {
                cloudInfo = ShelfItem.CloudFileInfo(
                    filename: url.lastPathComponent,
                    size: (vals?.fileSize).map { Int64($0) } ?? 0,
                    contentType: "application/octet-stream",
                    id: nil,
                    downloadURL: nil
                )
            }

            cloudState = .both
        } catch {
            NSLog("❌ Failed to adopt local file for \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private func recreateBookmark(from url: URL) {
        do {
            if bookmarkUsesSecurityScope {
                let didStartAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if didStartAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                if didStartAccess {
                    bookmarkData = try url.bookmarkData(
                        options: [.withSecurityScope],
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                } else {
                    // Fall back if we lose the scope for some reason.
                    bookmarkData = try url.bookmarkData(
                        options: [],
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    bookmarkUsesSecurityScope = false
                }
            } else {
                bookmarkData = try url.bookmarkData(
                    options: [],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            }
        } catch {
            NSLog("⚠️ Failed to refresh bookmark for \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    func resolvedURL() -> URL {
        guard !bookmarkData.isEmpty else {
            return URL(fileURLWithPath: "/")
        }

        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: bookmarkUsesSecurityScope ? [.withSecurityScope] : [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                // Recreate bookmark if file moved
                recreateBookmark(from: url)
            }

            return url
        } catch {
            return URL(fileURLWithPath: "/")
        }
    }

    func beginDragAccess() -> URL? {
        let url = resolvedURL()
        guard url.path != "/" else { return nil }

        if bookmarkUsesSecurityScope {
            let didStart = url.startAccessingSecurityScopedResource()
            guard didStart else {
                return nil
            }
            isAccessingResource = true
        } else {
            isAccessingResource = false
        }

        return url
    }

    func endDragAccess() {
        guard isAccessingResource else { return }
        let url = resolvedURL()
        url.stopAccessingSecurityScopedResource()
        isAccessingResource = false
    }

    static func == (lhs: ShelfItem, rhs: ShelfItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

@MainActor
final class DiskAccessController {
    static let shared = DiskAccessController()

    private init() { }

    func isAccessGranted() -> Bool {
        let testPaths = [
            "/Library/Application Support/com.apple.TCC/TCC.db",
            "/Library/Preferences/com.apple.TimeMachine.plist",
            NSHomeDirectory().appending("/Library/Safari/Bookmarks.plist"),
            NSHomeDirectory().appending("/Library/Safari/CloudTabs.db")
        ]

        for path in testPaths {
            let url = URL(fileURLWithPath: path)
            do {
                _ = try Data(contentsOf: url, options: .mappedIfSafe)
                return true
            } catch {
                let nsError = error as NSError
                if nsError.domain == NSCocoaErrorDomain {
                    switch nsError.code {
                    case NSFileReadNoSuchFileError, NSFileNoSuchFileError:
                        continue
                    case NSFileReadNoPermissionError, NSFileLockingError:
                        return false
                    default:
                        continue
                    }
                }
            }
        }

        return true
    }

    func requestAccess() {
        #if os(macOS)
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else {
            return
        }
        NSWorkspace.shared.open(url)
        #endif
    }
}
