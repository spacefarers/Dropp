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

        let fileData: Data
        do {
            fileData = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        } catch {
            throw DroppAPIError.fileReadFailed
        }

        let contentType = item.cloudInfo?.contentType ?? "application/octet-stream"
        let size = item.cloudInfo?.size ?? Int64(fileData.count)

        let url = DroppAPI.baseURL.appendingPathComponent("upload")
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

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
    }

    // Download by filename (from the item’s cloud info). Returns raw Data.
    func download(info: ShelfItem.CloudFileInfo) async throws -> Data {
        try requireAuth()

        guard var components = URLComponents(url: DroppAPI.baseURL.appendingPathComponent("download"), resolvingAgainstBaseURL: false) else {
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

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return data
    }

    // Remove a cloud file by filename.
    func remove(info: ShelfItem.CloudFileInfo) async throws {
        try requireAuth()

        let url = DroppAPI.baseURL.appendingPathComponent("remove")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        auth.authorize(&request)
        debugAssertAuthorizationHeader(request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: String] = ["filename": info.filename]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
    }

    // List cloud files and storage caps.
    func list() async throws -> (files: [ShelfItem.CloudFileInfo], storageUsed: Int64, storageCap: Int64) {
        try requireAuth()

        let url = DroppAPI.baseURL.appendingPathComponent("list")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        auth.authorize(&request)
        debugAssertAuthorizationHeader(request)

        let (data, response) = try await session.data(for: request)
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
