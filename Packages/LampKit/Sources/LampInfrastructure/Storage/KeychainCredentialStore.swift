import Foundation
import LampApplication
import LampDomain
import Security

/// API keys, headers and session cookies, one Keychain item per server, readable only on this Mac. The item holds the
/// origin the credential was given for next to it, so a server address changed in `servers.json` cannot redirect it.
public struct KeychainCredentialStore: CredentialStore {
    private let service: String

    public init(service: String = "pl.dabusoft.olivelamp.credentials") {
        self.service = service
    }

    public func credential(for server: UUID) throws -> StoredCredential? {
        var query = baseQuery(server)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw KeychainError(status: status) }
        if let item = try? JSONDecoder().decode(Item.self, from: data) {
            return StoredCredential(item.credential, origin: item.origin)
        }
        // Saved before 1.0.3: the credential alone.
        return StoredCredential(try JSONDecoder().decode(Credential.self, from: data), origin: nil)
    }

    public func store(_ credential: Credential, origin: String, for server: UUID) throws {
        let data = try JSONEncoder().encode(Item(credential: credential, origin: origin))
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery(server) as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw KeychainError(status: status) }
        var add = baseQuery(server)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        add[kSecAttrLabel as String] = "Olive Lamp: OliveTin sign-in"
        let added = SecItemAdd(add as CFDictionary, nil)
        guard added == errSecSuccess else { throw KeychainError(status: added) }
    }

    public func remove(for server: UUID) throws {
        let status = SecItemDelete(baseQuery(server) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }

    struct Item: Codable {
        var credential: Credential
        var origin: String
    }

    private func baseQuery(_ server: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: server.uuidString,
        ]
    }
}

public struct KeychainError: Error, LocalizedError {
    public let status: OSStatus

    public var errorDescription: String? {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
    }
}
