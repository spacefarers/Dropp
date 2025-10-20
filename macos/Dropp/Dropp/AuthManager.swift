import Foundation
import AppKit
import Combine

@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    // Customize these to match your backend’s redirect handling
    private let callbackScheme = "dropp"
    private let callbackHost = "auth"
    private let callbackPath: String? = "/callback"
    private let loginBaseURL = URL(string: "https://dropp.yangm.tech/login")!

    @Published private(set) var isLoggedIn: Bool = false
    @Published private(set) var displayName: String?
    @Published private(set) var userID: String?
    @Published private(set) var emailAddress: String?
    @Published private(set) var sessionID: String?
    private(set) var sessionToken: String?

    private let keychain = KeychainStore(service: "tech.yangm.dropp", account: "clerk_session_token")
    private let defaults = UserDefaults.standard
    private let displayNameDefaultsKey = "auth.displayName"
    private let userIDDefaultsKey = "auth.userID"
    private let emailDefaultsKey = "auth.email"
    private let sessionIDDefaultsKey = "auth.sessionID"
    private let legacyUsernameDefaultsKey = "auth.username"

    private init() { }

    func loadFromStorage() {
        if let token = try? keychain.readToken() {
            self.sessionToken = token
            self.isLoggedIn = true
        } else {
            self.sessionToken = nil
            self.isLoggedIn = false
        }
        self.displayName = defaults.string(forKey: displayNameDefaultsKey)
        self.userID = defaults.string(forKey: userIDDefaultsKey)
        self.emailAddress = defaults.string(forKey: emailDefaultsKey)
        self.sessionID = defaults.string(forKey: sessionIDDefaultsKey)

        if displayName == nil, let legacyName = defaults.string(forKey: legacyUsernameDefaultsKey) {
            self.displayName = legacyName
            defaults.removeObject(forKey: legacyUsernameDefaultsKey)
        }
    }

    func openLogin() {
        // Construct a redirect URI your site is prepared to use
        var comps = URLComponents(url: loginBaseURL, resolvingAgainstBaseURL: false)!
        let redirectURI = makeCallbackURLString()
        var items = comps.queryItems ?? []
        items.append(URLQueryItem(name: "redirect_uri", value: redirectURI))
        comps.queryItems = items

        guard let url = comps.url else { return }
        NSWorkspace.shared.open(url)
    }

    // Returns true if the URL was handled as an auth callback
    @discardableResult
    func handleCallback(url: URL) -> Bool {
        guard url.scheme?.lowercased() == callbackScheme,
              url.host?.lowercased() == callbackHost else {
            return false
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }

        let q = components.queryItems ?? []
        let token = q.first(where: { $0.name == "session_token" })?.value
                    ?? q.first(where: { $0.name == "sessionToken" })?.value
                    ?? q.first(where: { $0.name == "token" })?.value
                    ?? q.first(where: { $0.name == "__session" })?.value
        let userId = q.first(where: { $0.name == "user_id" })?.value
                    ?? q.first(where: { $0.name == "userId" })?.value
                    ?? q.first(where: { $0.name == "uid" })?.value
        let email = q.first(where: { $0.name == "email" })?.value
                    ?? q.first(where: { $0.name == "email_address" })?.value
                    ?? q.first(where: { $0.name == "emailAddress" })?.value
        let sessionIdentifier = q.first(where: { $0.name == "session_id" })?.value
                    ?? q.first(where: { $0.name == "sessionId" })?.value
        let displayName = q.first(where: { $0.name == "display_name" })?.value
                        ?? q.first(where: { $0.name == "displayName" })?.value
                        ?? email
                        ?? userId

        guard let token else { return false }

        // Persist securely and update state
        do {
            try keychain.writeToken(token)
            self.sessionToken = token
            self.isLoggedIn = true
        } catch {
            NSLog("Failed to store session token in Keychain: \(error.localizedDescription)")
            return false
        }

        if let displayName {
            defaults.set(displayName, forKey: displayNameDefaultsKey)
            self.displayName = displayName
        } else {
            defaults.removeObject(forKey: displayNameDefaultsKey)
            self.displayName = nil
        }

        if let userId {
            defaults.set(userId, forKey: userIDDefaultsKey)
            self.userID = userId
        } else {
            defaults.removeObject(forKey: userIDDefaultsKey)
            self.userID = nil
        }

        if let email {
            defaults.set(email, forKey: emailDefaultsKey)
            self.emailAddress = email
        } else {
            defaults.removeObject(forKey: emailDefaultsKey)
            self.emailAddress = nil
        }

        if let sessionIdentifier {
            defaults.set(sessionIdentifier, forKey: sessionIDDefaultsKey)
            self.sessionID = sessionIdentifier
        } else {
            defaults.removeObject(forKey: sessionIDDefaultsKey)
            self.sessionID = nil
        }

        defaults.removeObject(forKey: legacyUsernameDefaultsKey)

        return true
    }

    func logout() {
        do {
            try keychain.deleteToken()
        } catch {
            NSLog("Failed to delete token: \(error.localizedDescription)")
        }
        defaults.removeObject(forKey: displayNameDefaultsKey)
        defaults.removeObject(forKey: userIDDefaultsKey)
        defaults.removeObject(forKey: emailDefaultsKey)
        defaults.removeObject(forKey: sessionIDDefaultsKey)
        defaults.removeObject(forKey: legacyUsernameDefaultsKey)
        self.sessionToken = nil
        self.displayName = nil
        self.userID = nil
        self.emailAddress = nil
        self.sessionID = nil
        self.isLoggedIn = false
    }

    // Helper: attach token to requests
    func authorize(_ request: inout URLRequest) {
        if let sessionToken {
            request.addValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        }
    }

    var identitySummary: String {
        displayName ?? emailAddress ?? userID ?? "Account"
    }

    private func makeCallbackURLString() -> String {
        var components = URLComponents()
        components.scheme = callbackScheme
        components.host = callbackHost
        if let callbackPath, !callbackPath.isEmpty {
            if callbackPath.hasPrefix("/") {
                components.path = callbackPath
            } else {
                components.path = "/\(callbackPath)"
            }
        }

        if let string = components.string, !string.isEmpty {
            return string
        }

        let path: String
        if let callbackPath, !callbackPath.isEmpty {
            path = callbackPath.hasPrefix("/") ? callbackPath : "/\(callbackPath)"
        } else {
            path = ""
        }
        return "\(callbackScheme)://\(callbackHost)\(path)"
    }
}
