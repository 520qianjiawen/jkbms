import Foundation
import Security

public enum JKPasswordKind: String, CaseIterable {
    case connection, settings
}

public protocol JKCredentialStore {
    func password(deviceID: UUID, kind: JKPasswordKind) throws -> String?
    func save(_ password: String, deviceID: UUID, kind: JKPasswordKind) throws
    func remove(deviceID: UUID, kind: JKPasswordKind) throws
}

/// Device-specific credentials stay in this device's Keychain and are never synchronized.
public final class JKKeychainCredentialStore: JKCredentialStore {
    private let service = "com.cavon.jkbms.native.device-passwords"
    public init() {}
    private func query(_ deviceID: UUID, _ kind: JKPasswordKind) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: deviceID.uuidString + ":" + kind.rawValue,
         kSecAttrSynchronizable as String: false]
    }
    public func password(deviceID: UUID, kind: JKPasswordKind) throws -> String? {
        var query = query(deviceID, kind)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { throw StoreError.unavailable }
        return value
    }
    public func save(_ password: String, deviceID: UUID, kind: JKPasswordKind) throws {
        let query = query(deviceID, kind)
        let attributes: [String: Any] = [
            kSecValueData as String: Data(password.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updated == errSecItemNotFound {
            var addition = query
            attributes.forEach { addition[$0.key] = $0.value }
            guard SecItemAdd(addition as CFDictionary, nil) == errSecSuccess else { throw StoreError.unavailable }
        } else if updated != errSecSuccess { throw StoreError.unavailable }
    }
    public func remove(deviceID: UUID, kind: JKPasswordKind) throws {
        let status = SecItemDelete(query(deviceID, kind) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StoreError.unavailable }
    }
    private enum StoreError: Error { case unavailable }
}

/// Resets only session verification. A saved password is reused only after a fresh
/// validated device-information response matches it; a mismatch invalidates that entry.
final class JKDeviceCredentials {
    private let store: JKCredentialStore
    private(set) var deviceID: UUID?
    private var expected: [JKPasswordKind: String] = [:]
    private var verified: Set<JKPasswordKind> = []
    private(set) var remembered: Set<JKPasswordKind> = []
    private(set) var changed: Set<JKPasswordKind> = []
    private(set) var storageMessage = ""
    init(store: JKCredentialStore) { self.store = store }

    func beginSession(deviceID: UUID) {
        endSession()
        self.deviceID = deviceID
        for kind in JKPasswordKind.allCases {
            if read(kind) != nil { remembered.insert(kind) }
        }
    }
    func endSession() {
        deviceID = nil; expected = [:]; verified = []; remembered = []; changed = []
        storageMessage = ""
    }
    func isVerified(_ kind: JKPasswordKind) -> Bool { verified.contains(kind) }

    func update(connection: String, settings: String) {
        guard deviceID != nil else { return }
        for (kind, value) in [(JKPasswordKind.connection, connection), (.settings, settings)] {
            if let previous = expected[kind], previous != value { verified.remove(kind) }
            expected[kind] = value
            if value.isEmpty { verified.insert(kind) }
            guard let saved = read(kind) else { continue }
            if saved == value {
                remembered.insert(kind); verified.insert(kind); changed.remove(kind)
            } else {
                verified.remove(kind); changed.insert(kind)
                remove(kind)
            }
        }
    }

    @discardableResult func verify(_ password: String, kind: JKPasswordKind, remember: Bool) -> Bool {
        guard deviceID != nil, let actual = expected[kind], actual == password else { return false }
        verified.insert(kind); changed.remove(kind)
        storageMessage = ""
        if remember { save(password, kind: kind) } else { remove(kind) }
        return true
    }
    /// Caller must have compared a fresh device response to the requested new password.
    func confirmedChange(_ password: String, kind: JKPasswordKind) {
        guard deviceID != nil else { return }
        let shouldRemember = remembered.contains(kind)
        expected[kind] = password; verified.insert(kind); changed.remove(kind)
        if shouldRemember { save(password, kind: kind) }
    }
    func forgetSavedPasswords() {
        storageMessage = ""
        for kind in JKPasswordKind.allCases { remove(kind) }
    }
    private func read(_ kind: JKPasswordKind) -> String? {
        guard let deviceID else { return nil }
        do { return try store.password(deviceID: deviceID, kind: kind) }
        catch { storageMessage = "暂时无法读取已保存的密码，请输入密码继续。"; return nil }
    }
    private func save(_ password: String, kind: JKPasswordKind) {
        guard let deviceID else { return }
        do { try store.save(password, deviceID: deviceID, kind: kind); remembered.insert(kind) }
        catch { storageMessage = "本次验证已通过，但密码保存失败，下次连接可能需要重新输入。" }
    }
    private func remove(_ kind: JKPasswordKind) {
        guard let deviceID else { return }
        do { try store.remove(deviceID: deviceID, kind: kind); remembered.remove(kind) }
        catch { storageMessage = "未能清除已保存的密码，请稍后重试。" }
    }
}
