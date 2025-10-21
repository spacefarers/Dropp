// CloudLinkStore.swift
import Foundation

@MainActor
final class CloudLinkStore {
    static let shared = CloudLinkStore()

    private let defaults = UserDefaults.standard
    private let key = "cloud.link.map" // [cloudId: bookmarkKey]

    private init() { }

    private var map: [String: String] {
        get { (defaults.dictionary(forKey: key) as? [String: String]) ?? [:] }
        set { defaults.set(newValue, forKey: key) }
    }

    func link(cloudId: String, toBookmarkKey bookmarkKey: String) {
        var m = map
        m[cloudId] = bookmarkKey
        map = m
    }

    func unlink(cloudId: String) {
        var m = map
        m.removeValue(forKey: cloudId)
        map = m
    }

    func lookupCloudId(forBookmarkKey bookmarkKey: String) -> String? {
        // Reverse lookup (small maps are fine to scan)
        return map.first(where: { $0.value == bookmarkKey })?.key
    }
}
