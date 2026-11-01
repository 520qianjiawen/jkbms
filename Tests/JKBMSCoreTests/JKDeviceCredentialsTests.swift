import XCTest
@testable import JKBMSCore

private final class MemoryCredentials: JKCredentialStore {
    struct Key: Hashable { let device: UUID; let role: String }
    var values: [Key: String] = [:]
    var failReads = false
    var failWrites = false
    enum Failure: Error { case unavailable }
    func password(deviceID: UUID, kind: JKPasswordKind) throws -> String? {
        if failReads { throw Failure.unavailable }
        return values[Key(device: deviceID, role: kind.rawValue)]
    }
    func save(_ password: String, deviceID: UUID, kind: JKPasswordKind) throws {
        if failWrites { throw Failure.unavailable }
        values[Key(device: deviceID, role: kind.rawValue)] = password
    }
    func remove(deviceID: UUID, kind: JKPasswordKind) throws {
        values.removeValue(forKey: Key(device: deviceID, role: kind.rawValue))
    }
}

final class JKDeviceCredentialsTests: XCTestCase {
    private let board = UUID(uuidString: "C28E0000-0000-0000-0000-000000000001")!

    func testReconnectAndAppRestartReuseOnlyAfterFreshDeviceInformation() throws {
        let store = MemoryCredentials()
        let first = JKDeviceCredentials(store: store)
        first.beginSession(deviceID: board)
        first.update(connection: "ble-secret", settings: "setup-secret")
        XCTAssertTrue(first.verify("ble-secret", kind: .connection, remember: true))
        XCTAssertTrue(first.verify("setup-secret", kind: .settings, remember: true))
        first.endSession()
        XCTAssertFalse(first.isVerified(.connection))
        let restarted = JKDeviceCredentials(store: store)
        restarted.beginSession(deviceID: board)
        XCTAssertFalse(restarted.isVerified(.connection))
        XCTAssertFalse(restarted.isVerified(.settings))
        restarted.update(connection: "ble-secret", settings: "setup-secret")
        XCTAssertTrue(restarted.isVerified(.connection))
        XCTAssertTrue(restarted.isVerified(.settings))
    }

    func testPasswordsCannotCrossDevicesOrRoles() throws {
        let store = MemoryCredentials()
        try store.save("ble-secret", deviceID: board, kind: .connection)
        let session = JKDeviceCredentials(store: store)
        session.beginSession(deviceID: board)
        session.update(connection: "ble-secret", settings: "setup-secret")
        XCTAssertTrue(session.isVerified(.connection))
        XCTAssertFalse(session.isVerified(.settings))
        session.beginSession(deviceID: UUID())
        session.update(connection: "ble-secret", settings: "setup-secret")
        XCTAssertFalse(session.isVerified(.connection))
        XCTAssertFalse(session.isVerified(.settings))
    }

    func testFailedInputAndUnrequestedDevicePasswordAreNeverSaved() throws {
        let store = MemoryCredentials()
        let session = JKDeviceCredentials(store: store)
        session.beginSession(deviceID: board)
        XCTAssertFalse(session.verify("ble-secret", kind: .connection, remember: true))
        session.update(connection: "ble-secret", settings: "setup-secret")
        XCTAssertTrue(store.values.isEmpty) // Never learn a password merely because the board returned it.
        XCTAssertFalse(session.verify("wrong", kind: .connection, remember: true))
        XCTAssertTrue(store.values.isEmpty)
    }

    func testChangedPasswordRelocksAndDeletesOnlyStaleRole() throws {
        let store = MemoryCredentials()
        try store.save("old", deviceID: board, kind: .connection)
        try store.save("setup", deviceID: board, kind: .settings)
        let session = JKDeviceCredentials(store: store)
        session.beginSession(deviceID: board)
        session.update(connection: "new", settings: "setup")
        XCTAssertFalse(session.isVerified(.connection))
        XCTAssertTrue(session.isVerified(.settings))
        XCTAssertNil(try store.password(deviceID: board, kind: .connection))
        XCTAssertEqual(try store.password(deviceID: board, kind: .settings), "setup")
        XCTAssertTrue(session.changed.contains(.connection))
    }

    func testOptOutDoesNotSurviveReconnect() throws {
        let store = MemoryCredentials()
        let session = JKDeviceCredentials(store: store)
        session.beginSession(deviceID: board)
        session.update(connection: "ble", settings: "setup")
        XCTAssertTrue(session.verify("ble", kind: .connection, remember: false))
        XCTAssertTrue(session.isVerified(.connection))
        session.beginSession(deviceID: board)
        session.update(connection: "ble", settings: "setup")
        XCTAssertFalse(session.isVerified(.connection))
        XCTAssertTrue(store.values.isEmpty)
    }

    func testConfirmedPasswordChangeRefreshesSavedValueAndStaysUnlocked() throws {
        let store = MemoryCredentials()
        let session = JKDeviceCredentials(store: store)
        session.beginSession(deviceID: board)
        session.update(connection: "ble", settings: "old")
        XCTAssertTrue(session.verify("old", kind: .settings, remember: true))
        session.confirmedChange("new", kind: .settings)
        session.update(connection: "ble", settings: "new")
        XCTAssertTrue(session.isVerified(.settings))
        XCTAssertEqual(try store.password(deviceID: board, kind: .settings), "new")
        session.beginSession(deviceID: board)
        session.update(connection: "ble", settings: "new")
        XCTAssertTrue(session.isVerified(.settings))
    }

    func testForgetDoesNotDisconnectCurrentSessionButNextOneRequiresInput() {
        let store = MemoryCredentials()
        let session = JKDeviceCredentials(store: store)
        session.beginSession(deviceID: board)
        session.update(connection: "ble", settings: "setup")
        XCTAssertTrue(session.verify("ble", kind: .connection, remember: true))
        session.forgetSavedPasswords()
        XCTAssertTrue(session.isVerified(.connection))
        XCTAssertTrue(session.remembered.isEmpty)
        session.beginSession(deviceID: board)
        session.update(connection: "ble", settings: "setup")
        XCTAssertFalse(session.isVerified(.connection))
    }

    func testKeychainFailureDoesNotBlockValidSessionOrLeakPassword() {
        let store = MemoryCredentials()
        let session = JKDeviceCredentials(store: store)
        session.beginSession(deviceID: board)
        session.update(connection: "ble-secret", settings: "setup-secret")
        store.failWrites = true
        XCTAssertTrue(session.verify("ble-secret", kind: .connection, remember: true))
        XCTAssertTrue(session.isVerified(.connection))
        XCTAssertFalse(session.storageMessage.isEmpty)
        XCTAssertFalse(session.storageMessage.contains("ble-secret"))
        XCTAssertTrue(store.values.isEmpty)
    }
}
