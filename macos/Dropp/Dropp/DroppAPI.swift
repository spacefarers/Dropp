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
    static let baseURL = URL(string: "https://dropp.yangm.tech/api")!
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

        // Read file data
        let fileData: Data
        do {
            fileData = try await readFileData(at: fileURL)
        } catch {
            NSLog("❌ Upload read failed for \(fileURL.path): \(error.localizedDescription)")
            throw DroppAPIError.fileReadFailed
        }

        let contentType = item.cloudInfo?.contentType ?? "application/octet-stream"

        // STEP 1: Get upload token from backend
        let uploadToken = try await getUploadToken(
            filename: filename,
            contentType: contentType,
            fileSize: fileData.count
        )

        // STEP 2: Upload directly to Vercel
        try await uploadToVercel(
            token: uploadToken,
            filename: filename,
            contentType: contentType,
            fileData: fileData
        )

        NSLog("✅ File uploaded successfully: \(filename)")
    }

    // Remove a cloud file by id.
    func remove(info: ShelfItem.CloudFileInfo) async throws {
        try requireAuth()

        guard let id = info.id, !id.isEmpty else {
            throw DroppAPIError.invalidURL
        }

        let url = DroppAPI.baseURL.appendingPathComponent("files/\(id)", isDirectory: false)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        auth.authorize(&request)
        debugAssertAuthorizationHeader(request)

        // Pre-flight log indicating we are sending the delete to backend
        NSLog("➡️ [delete] DELETE \(url.absoluteString) • id=\(id) • filename=\(info.filename)")

        let t0 = Date()
        let (data, response) = try await session.data(for: request)
        logNetwork(request: request, response: response, data: data, startedAt: t0, purpose: "delete")
        try validateResponse(response, data: data)
    }

    // List cloud files and storage caps.
    func list() async throws -> (files: [ShelfItem.CloudFileInfo], storageUsed: Int64, storageCap: Int64) {
        try requireAuth()

        let url = DroppAPI.baseURL.appendingPathComponent("list")
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
            ShelfItem.CloudFileInfo(
                filename: dto.filename,
                size: dto.size,
                contentType: dto.contentType,
                id: dto.id,
                downloadURL: dto.blobURL
            )
        }
        return (files, decoded.storage.used, decoded.storage.cap)
    }

    // MARK: - Upload Helpers

    private func getUploadToken(
        filename: String,
        contentType: String,
        fileSize: Int
    ) async throws -> String {
        try requireAuth()

        let url = DroppAPI.baseURL.appendingPathComponent("upload/token")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        auth.authorize(&request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = [
            "filename": filename,
            "contentType": contentType,
            "maximumSizeInBytes": fileSize * 2  // Allow 2x for safety
        ] as [String : Any]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let t0 = Date()
        let (data, response) = try await session.data(for: request)
        logNetwork(request: request, response: response, data: data, startedAt: t0, purpose: "get-upload-token")
        try validateResponse(response, data: data)

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        return tokenResponse.token
    }

    private func uploadToVercel(
        token: String,
        filename: String,
        contentType: String,
        fileData: Data
    ) async throws {
        let url = URL(string: "https://blob.vercelusercontent.com/upload")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = fileData

        NSLog("➡️ [upload] POST \(url.absoluteString) • filename=\(filename) • size=\(fileData.count)")

        let t0 = Date()
        let (data, response) = try await session.data(for: request)
        logNetwork(request: request, response: response, data: data, startedAt: t0, purpose: "upload-to-vercel")
        try validateResponse(response, data: data)

        NSLog("✅ Vercel accepted upload: \(filename)")
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
            if http.statusCode == 401 {
                throw DroppAPIError.unauthorized
            }
            throw DroppAPIError.badResponse(status: http.statusCode, body: body)
        }
    }

    // Robust file read that handles iCloud/File Provider and coordinates access
    private func readFileData(at url: URL) async throws -> Data {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        if values.isDirectory == true && values.isPackage == false {
            throw DroppAPIError.fileReadFailed
        }

        if values.isUbiquitousItem == true {
            try await ensureUbiquitousItemIsDownloaded(at: url)
        }

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
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
        } catch {
            // It may already be local; continue to poll status
        }

        let timeout: TimeInterval = 30
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if let status = try? ubiquitousStatus(for: url), status == .current {
                return
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    // MARK: - Logging

    private func logNetwork(request: URLRequest, response: URLResponse, data: Data?, startedAt: Date, purpose: String) {
        guard let http = response as? HTTPURLResponse else {
            NSLog("↩️ [\(purpose)] Non-HTTP response from \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "<nil>")")
            return
        }

        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        let method = request.httpMethod ?? "GET"
        let urlString = request.url?.absoluteString ?? "<nil>"
        let status = http.statusCode

        // Log request summary
        NSLog("↩️ [\(purpose)] \(method) \(urlString)")
        NSLog("   Status: \(status) • \(durationMs) ms")

        // Log headers
        let headerLines: [String] = http.allHeaderFields.compactMap { key, value in
            "\(String(describing: key)): \(String(describing: value))"
        }.sorted()

        if !headerLines.isEmpty {
            NSLog("   Response Headers:")
            for header in headerLines {
                NSLog("      \(header)")
            }
        }

        // Log body separately to avoid NSLog character limits
        let contentType = (http.allHeaderFields["Content-Type"] as? String) ?? (http.allHeaderFields["content-type"] as? String) ?? ""
        let isLikelyText = contentType.contains("json")
            || contentType.contains("text/")
            || contentType.contains("xml")
            || contentType.contains("yaml")

        let maxPreviewBytes = 100000000
        let logChunkSize = 500000  // Split large responses into 500KB chunks

        if let data, !data.isEmpty {
            if isLikelyText, let text = String(data: data.prefix(maxPreviewBytes), encoding: .utf8) {
                let truncated = data.count > maxPreviewBytes ? " (truncated beyond \(maxPreviewBytes / 1000000)MB)" : ""
                NSLog("   Body (\(data.count) bytes, text)\(truncated):")

                // Split into chunks to avoid NSLog truncation
                let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                var currentChunk = ""
                for line in lines {
                    if currentChunk.count + line.count > logChunkSize {
                        NSLog("      \(currentChunk)")
                        currentChunk = line
                    } else {
                        if !currentChunk.isEmpty {
                            currentChunk += "\n"
                        }
                        currentChunk += line
                    }
                }
                if !currentChunk.isEmpty {
                    NSLog("      \(currentChunk)")
                }
            } else {
                let prefix = data.prefix(min(64, data.count))
                let hex = prefix.map { String(format: "%02x", $0) }.joined(separator: " ")
                let truncated = data.count > prefix.count ? " (truncated)" : ""
                NSLog("   Body (\(data.count) bytes, binary)\(truncated):")
                NSLog("      \(hex)")
            }
        } else {
            NSLog("   Body: <empty>")
        }
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

private struct TokenResponse: Decodable {
    let token: String
    let uploadUrl: String?
}

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
    let id: String?
    let blobURL: URL?

    private enum CodingKeys: String, CodingKey {
        case filename
        case size
        case contentType = "content_type"
        case id
        case blobURL = "blob_url"
    }
}
