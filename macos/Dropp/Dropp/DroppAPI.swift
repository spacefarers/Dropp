//
//  DroppAPI.swift
//  Dropp
//
//  Created by Michael Yang on 10/20/25.
//

import Foundation

enum DroppAPIError: Error, LocalizedError {
    case invalidURL
    case noFilename
    case fileReadFailed
    case badResponse(status: Int, body: String?)
    case missingData
    case unauthorized // missing or invalid session token

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL."
        case .noFilename:
            return "Missing filename."
        case .fileReadFailed:
            return "Failed to read file data."
        case .badResponse(let status, let body):
            return "Server returned status \(status). \(body ?? "")"
        case .missingData:
            return "Missing response data."
        case .unauthorized:
            return "You must be signed in to perform this action."
        }
    }
}

struct DroppAPI {
    static let baseURL = URL(string: "https://droppapi.yangm.tech")!
}

@MainActor
final class DroppAPIClient {
    static let shared = DroppAPIClient(auth: AuthManager.shared)

    private let auth: AuthManager
    private let session: URLSession

    init(auth: AuthManager, session: URLSession = .shared) {
        self.auth = auth
        self.session = session
    }

    // MARK: - Public API

    // Upload a file from disk using the ShelfItem’s URL and optional metadata.
    func upload(item: ShelfItem) async throws {
        try requireAuth()

        let fileURL = item.resolvedURL()
        let didStartAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        let filename = item.cloudInfo?.filename ?? fileURL.lastPathComponent
        guard !filename.isEmpty else { throw DroppAPIError.noFilename }

        // Read data robustly (handles iCloud/File Provider and coordination)
        let fileData: Data
        do {
            fileData = try await readFileData(at: fileURL)
        } catch {
            NSLog("❌ Upload read failed for \(fileURL.path): \(error.localizedDescription)")
            throw DroppAPIError.fileReadFailed
        }

        let contentType = item.cloudInfo?.contentType ?? "application/octet-stream"
        let size = item.cloudInfo?.size ?? Int64(fileData.count)

        let url = DroppAPI.baseURL.appendingPathComponent("upload", isDirectory: true)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        auth.authorize(&request)
        debugAssertAuthorizationHeader(request)

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = try makeMultipartBody(
            boundary: boundary,
            fields: [
                "filename": filename,
                "content_type": contentType,
                "size": String(size)
            ],
            fileField: "file",
            fileFilename: filename,
            fileMimeType: contentType,
            fileData: fileData
        )

        let t0 = Date()
        let (data, response) = try await session.data(for: request)
        logNetwork(request: request, response: response, data: data, startedAt: t0, purpose: "upload")
        try validateResponse(response, data: data)
    }

    // Download by filename (from the item’s cloud info). Returns raw Data.
    func download(info: ShelfItem.CloudFileInfo) async throws -> Data {
        try requireAuth()

        guard var components = URLComponents(
            url: DroppAPI.baseURL.appendingPathComponent("download", isDirectory: true),
            resolvingAgainstBaseURL: false
        ) else {
            throw DroppAPIError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "filename", value: info.filename)
        ]
        guard let url = components.url else { throw DroppAPIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        auth.authorize(&request)
        debugAssertAuthorizationHeader(request)

        let t0 = Date()
        let (data, response) = try await session.data(for: request)
        logNetwork(request: request, response: response, data: data, startedAt: t0, purpose: "download")
        try validateResponse(response, data: data)
        return data
    }

    // Remove a cloud file by filename.
    func remove(info: ShelfItem.CloudFileInfo) async throws {
        try requireAuth()

        let url = DroppAPI.baseURL.appendingPathComponent("remove", isDirectory: true)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        auth.authorize(&request)
        debugAssertAuthorizationHeader(request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: String] = ["filename": info.filename]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let t0 = Date()
        let (data, response) = try await session.data(for: request)
        logNetwork(request: request, response: response, data: data, startedAt: t0, purpose: "remove")
        try validateResponse(response, data: data)
    }

    // List cloud files and storage caps.
    func list() async throws -> (files: [ShelfItem.CloudFileInfo], storageUsed: Int64, storageCap: Int64) {
        try requireAuth()

        let url = DroppAPI.baseURL.appendingPathComponent("list", isDirectory: true)
        NSLog(url.absoluteString)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        auth.authorize(&request)
        debugAssertAuthorizationHeader(request)

        let t0 = Date()
        let (data, response) = try await session.data(for: request)
        logNetwork(request: request, response: response, data: data, startedAt: t0, purpose: "list")
        try validateResponse(response, data: data)

        let decoded = try JSONDecoder().decode(ListResponse.self, from: data)
        let files = decoded.files.map { dto in
            ShelfItem.CloudFileInfo(filename: dto.filename, size: dto.size, contentType: dto.contentType)
        }
        return (files, decoded.storage.used, decoded.storage.cap)
    }

    // MARK: - Helpers

    private func requireAuth() throws {
        guard auth.sessionToken != nil else {
            throw DroppAPIError.unauthorized
        }
    }

    private func validateResponse(_ response: URLResponse, data: Data?) throws {
        guard let http = response as? HTTPURLResponse else {
            throw DroppAPIError.badResponse(status: -1, body: nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = data.flatMap { String(data: $0, encoding: .utf8) }
            // Map 401 to a clearer error
            if http.statusCode == 401 {
                throw DroppAPIError.unauthorized
            }
            throw DroppAPIError.badResponse(status: http.statusCode, body: body)
        }
    }

    private func makeMultipartBody(
        boundary: String,
        fields: [String: String],
        fileField: String,
        fileFilename: String,
        fileMimeType: String,
        fileData: Data
    ) throws -> Data {
        var body = Data()
        let lineBreak = "\r\n"

        func append(_ string: String) {
            if let data = string.data(using: .utf8) {
                body.append(data)
            }
        }

        for (key, value) in fields {
            append("--\(boundary)\(lineBreak)")
            append("Content-Disposition: form-data; name=\"\(key)\"\(lineBreak)\(lineBreak)")
            append("\(value)\(lineBreak)")
        }

        append("--\(boundary)\(lineBreak)")
        append("Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(fileFilename)\"\(lineBreak)")
        append("Content-Type: \(fileMimeType)\(lineBreak)\(lineBreak)")
        body.append(fileData)
        append(lineBreak)

        append("--\(boundary)--\(lineBreak)")
        return body
    }

    // Robust file read that handles iCloud/File Provider and coordinates access
    private func readFileData(at url: URL) async throws -> Data {
        // Reject plain directories (packages may still be directories; allow them)
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        if values.isDirectory == true && values.isPackage == false {
            throw DroppAPIError.fileReadFailed
        }

        // Ensure iCloud files are downloaded locally
        if values.isUbiquitousItem == true {
            try await ensureUbiquitousItemIsDownloaded(at: url)
        }

        // Coordinate the read to cooperate with File Providers
        return try coordinatedRead(at: url)
    }

    private func coordinatedRead(at url: URL) throws -> Data {
        var coordError: NSError?
        var resultData: Data?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordError) { coordinatedURL in
            do {
                resultData = try Data(contentsOf: coordinatedURL, options: .mappedIfSafe)
            } catch {
                resultData = nil
            }
        }
        if let coordError { throw coordError }
        guard let data = resultData else {
            throw DroppAPIError.fileReadFailed
        }
        return data
    }

    private func ubiquitousStatus(for url: URL) throws -> URLUbiquitousItemDownloadingStatus? {
        let vals = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        return vals.ubiquitousItemDownloadingStatus
    }

    private func ensureUbiquitousItemIsDownloaded(at url: URL) async throws {
        // Kick off download if needed
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
        } catch {
            // It may already be local; continue to poll status
        }

        // Poll until status == .current or timeout
        let timeout: TimeInterval = 30
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if let status = try? ubiquitousStatus(for: url), status == .current {
                return
            }
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
        }
        // If still not current, attempt read anyway; let it fail if unavailable
    }

    // MARK: - Logging

    // Centralized logging for all backend responses
    private func logNetwork(request: URLRequest, response: URLResponse, data: Data?, startedAt: Date, purpose: String) {
        guard let http = response as? HTTPURLResponse else {
            NSLog("↩️ [\(purpose)] Non-HTTP response from \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "<nil>")")
            return
        }

        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        let method = request.httpMethod ?? "GET"
        let urlString = request.url?.absoluteString ?? "<nil>"
        let status = http.statusCode

        // Headers (response)
        let headerLines: [String] = http.allHeaderFields.compactMap { key, value in
            "\(String(describing: key)): \(String(describing: value))"
        }.sorted()

        // Decide how to log body
        let contentType = (http.allHeaderFields["Content-Type"] as? String) ?? (http.allHeaderFields["content-type"] as? String) ?? ""
        let isLikelyText = contentType.contains("json")
            || contentType.contains("text/")
            || contentType.contains("xml")
            || contentType.contains("yaml")

        let maxPreviewBytes = 8 * 1024

        var bodyPreview: String = ""
        if let data, !data.isEmpty {
            if isLikelyText, let text = String(data: data.prefix(maxPreviewBytes), encoding: .utf8) {
                let truncated = data.count > maxPreviewBytes ? " …(truncated)" : ""
                bodyPreview = "Body (\(data.count) bytes, text):\n\(text)\(truncated)"
            } else {
                // Hex preview for binary
                let prefix = data.prefix(min(64, data.count))
                let hex = prefix.map { String(format: "%02x", $0) }.joined(separator: " ")
                let truncated = data.count > prefix.count ? " …(truncated)" : ""
                bodyPreview = "Body (\(data.count) bytes, binary):\n\(hex)\(truncated)"
            }
        } else {
            bodyPreview = "Body: <empty>"
        }

        NSLog("""
        ↩️ [\(purpose)] \(method) \(urlString)
           Status: \(status) • \(durationMs) ms
           Response Headers:
           \(headerLines.joined(separator: "\n   "))
           \(bodyPreview)
        """)
    }

    #if DEBUG
    private func debugAssertAuthorizationHeader(_ request: URLRequest) {
        if request.value(forHTTPHeaderField: "Authorization") == nil {
            NSLog("⚠️ Authorization header is missing on request to \(request.url?.absoluteString ?? "<nil>")")
        }
    }
    #else
    private func debugAssertAuthorizationHeader(_ request: URLRequest) { }
    #endif
}

// MARK: - DTOs

private struct ListResponse: Decodable {
    let files: [CloudFileInfoDTO]
    let storage: StorageDTO

    struct StorageDTO: Decodable {
        let used: Int64
        let cap: Int64
    }
}

private struct CloudFileInfoDTO: Decodable {
    let filename: String
    let size: Int64
    let contentType: String

    private enum CodingKeys: String, CodingKey {
        case filename
        case size
        case contentType = "content_type"
    }
}
