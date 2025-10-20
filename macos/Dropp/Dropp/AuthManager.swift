import Foundation
import AppKit
import Combine

@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    // Customize these to match your backend’s redirect handling
    private let callbackScheme = "dropp"
    private let callbackHost = "auth"
    private let loginBaseURL = URL(string: "https://dropp.yangm.tech/login")!

    @Published private(set) var isLoggedIn: Bool = false
    @Published private(set) var username: String?
    private(set) var sessionToken: String?

    private let keychain = KeychainStore(service: "tech.yangm.dropp", account: "clerk_session_token")
    private let defaults = UserDefaults.standard
    private let usernameDefaultsKey = "auth.username"

    private init() { }

    func loadFromStorage() {
        if let token = try? keychain.readToken() {
            self.sessionToken = token
            self.isLoggedIn = true
        } else {
            self.sessionToken = nil
            self.isLoggedIn = false
        }
        self.username = defaults.string(forKey: usernameDefaultsKey)
    }

    func openLogin() {
        // Construct a redirect URI your site is prepared to use
        var comps = URLComponents(url: loginBaseURL, resolvingAgainstBaseURL: false)!
        let redirectURI = "\(callbackScheme)://\(callbackHost)"
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
                    ?? q.first(where: { $0.name == "token" })?.value
                    ?? q.first(where: { $0.name == "__session" })?.value
        let user = q.first(where: { $0.name == "username" })?.value
                    ?? q.first(where: { $0.name == "user" })?.value

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

        if let user {
            defaults.set(user, forKey: usernameDefaultsKey)
            self.username = user
        }

        return true
    }

    func logout() {
        do {
            try keychain.deleteToken()
        } catch {
            NSLog("Failed to delete token: \(error.localizedDescription)")
        }
        defaults.removeObject(forKey: usernameDefaultsKey)
        self.sessionToken = nil
        self.username = nil
        self.isLoggedIn = false
    }

    // Helper: attach token to requests
    func authorize(_ request: inout URLRequest) {
        if let sessionToken {
            request.addValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        }
    }
}

