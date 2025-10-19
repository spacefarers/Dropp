//
//  Shelf.swift
//  Dropp
//
//  Created by Michael Yang on 10/19/25.
//

import Foundation
import Combine

@MainActor
final class Shelf: ObservableObject {
    @Published private(set) var items: [URL] = []

    func add(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        for url in urls {
            if !items.contains(url) {
                items.append(url)
            }
        }
        let paths = items.map { $0.path }
        NSLog("Shelf now has \(items.count) item(s): \(paths)")
    }

    func clear() {
        items.removeAll()
        NSLog("Shelf cleared.")
    }
}
