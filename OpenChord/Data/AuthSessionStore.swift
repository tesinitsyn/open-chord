import Foundation
import Security

enum ServerMode: String, Codable, CaseIterable {
    case personal = "PERSONAL"
    case family = "FAMILY"
}

struct ServerCapabilities: Decodable {
    let initialized: Bool
    let mode: ServerMode?
    let registrationEnabled: Bool
}

struct Account: Codable, Equatable {
    let id: UUID
    let username: String
    let displayName: String
    let role: String
}

protocol AccessTokenProviding: Sendable {
    func accessToken() -> String?
}

final class KeychainTokenStore: AccessTokenProviding, @unchecked Sendable {
    static let shared = KeychainTokenStore()
    private let service = "app.openchord.session"

    func accessToken() -> String? { read("access") }
    func refreshToken() -> String? { read("refresh") }

    func save(access: String, refresh: String) throws {
        try write(access, account: "access")
        try write(refresh, account: "refresh")
    }

    func clear() {
        delete("access")
        delete("refresh")
    }

    private func read(_ account: String) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func write(_ value: String, account: String) throws {
        delete(account)
        var query = baseQuery(account)
        query[kSecValueData as String] = Data(value.utf8)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw AuthError.keychain(status) }
    }

    private func delete(_ account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }

    private func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
    }
}

struct AuthAPIClient {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func capabilities(at serverURL: URL) async throws -> ServerCapabilities {
        try await request(path: "api/auth/server", method: "GET", body: Optional<String>.none, at: serverURL)
    }

    func login(username: String, password: String, at serverURL: URL) async throws -> AuthPayload {
        try await request(
            path: "api/auth/login",
            body: LoginBody(username: username, password: password, deviceName: Self.deviceName), at: serverURL)
    }

    func register(username: String, displayName: String, password: String, at serverURL: URL) async throws
        -> AuthPayload
    {
        try await request(
            path: "api/auth/register",
            body: CredentialsBody(
                username: username, displayName: displayName, password: password, deviceName: Self.deviceName),
            at: serverURL)
    }

    func setup(username: String, displayName: String, password: String, mode: ServerMode, at serverURL: URL)
        async throws -> AuthPayload
    {
        try await request(
            path: "api/auth/setup",
            body: SetupBody(
                username: username, displayName: displayName, password: password, deviceName: Self.deviceName,
                mode: mode), at: serverURL)
    }

    private func request<Body: Encodable, Response: Decodable>(
        path: String, method: String = "POST", body: Body?, at serverURL: URL
    ) async throws -> Response {
        var request = URLRequest(url: serverURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = try JSONEncoder().encode(body) }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            let message = (try? JSONDecoder().decode(ServerError.self, from: data).message)
            throw AuthError.server(message ?? "The server returned HTTP \(response.statusCode).")
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private static var deviceName: String { "iPhone" }
}

struct AuthPayload: Decodable {
    let accessToken: String
    let refreshToken: String
    let account: Account
    private enum CodingKeys: String, CodingKey { case accessToken, refreshToken, account = "user" }
}

private struct LoginBody: Encodable { let username: String; let password: String; let deviceName: String }
private struct CredentialsBody: Encodable {
    let username: String; let displayName: String; let password: String; let deviceName: String
}
private struct SetupBody: Encodable {
    let username: String; let displayName: String; let password: String; let deviceName: String; let mode: ServerMode
}
private struct ServerError: Decodable { let message: String }

enum AuthError: LocalizedError {
    case invalidResponse
    case server(String)
    case keychain(OSStatus)
    var errorDescription: String? {
        switch self {
        case .invalidResponse: "The server returned an invalid response."
        case .server(let message): message
        case .keychain: "OpenChord could not securely save this session."
        }
    }
}

@MainActor
final class AuthSessionStore: ObservableObject {
    @Published private(set) var account: Account?
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?
    var isAuthenticated: Bool { account != nil && tokens.accessToken() != nil }

    private let client: AuthAPIClient
    private let tokens: KeychainTokenStore

    init(client: AuthAPIClient = AuthAPIClient(), tokens: KeychainTokenStore = .shared) {
        self.client = client
        self.tokens = tokens
        if let data = UserDefaults.standard.data(forKey: "openchord.account") {
            account = try? JSONDecoder().decode(Account.self, from: data)
        }
    }

    func capabilities(at url: URL) async throws -> ServerCapabilities { try await client.capabilities(at: url) }

    func login(username: String, password: String, serverURL: URL) async {
        await perform { try await client.login(username: username, password: password, at: serverURL) }
    }
    func register(username: String, displayName: String, password: String, serverURL: URL) async {
        await perform {
            try await client.register(username: username, displayName: displayName, password: password, at: serverURL)
        }
    }
    func setup(username: String, displayName: String, password: String, mode: ServerMode, serverURL: URL) async {
        await perform {
            try await client.setup(
                username: username, displayName: displayName, password: password, mode: mode, at: serverURL)
        }
    }

    func logout() {
        tokens.clear()
        account = nil
        UserDefaults.standard.removeObject(forKey: "openchord.account")
    }

    private func perform(_ operation: () async throws -> AuthPayload) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let payload = try await operation()
            try tokens.save(access: payload.accessToken, refresh: payload.refreshToken)
            account = payload.account
            UserDefaults.standard.set(try JSONEncoder().encode(payload.account), forKey: "openchord.account")
        } catch { errorMessage = error.localizedDescription }
    }
}
