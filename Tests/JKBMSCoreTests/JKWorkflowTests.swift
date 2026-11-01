import XCTest
@testable import JKBMSCore

final class JKWorkflowTests: XCTestCase {
    func testLaunchStartsDisconnectedInRealMode() {
        let manager = JKBluetoothManager(enableBluetooth: false)
        XCTAssertFalse(manager.isSimulatorMode)
        XCTAssertFalse(manager.isConnected)
        XCTAssertFalse(manager.hasTelemetry)
        XCTAssertFalse(manager.hasSettings)
        XCTAssertFalse(manager.canWrite)
        XCTAssertTrue(manager.discoveredDevices.isEmpty)
        XCTAssertTrue(manager.status.cellVoltages.isEmpty)
        XCTAssertTrue(manager.exportSettingsJSON.isEmpty)
    }

    func testDemoIsExplicitAndLeavingItClearsSyntheticSession() {
        let manager = JKBluetoothManager(enableBluetooth: false)
        manager.setDemoMode(true)
        XCTAssertTrue(manager.isSimulatorMode)
        XCTAssertTrue(manager.canWrite)
        XCTAssertTrue(manager.hasTelemetry)
        manager.send(command: .setCharge(enabled: false))
        XCTAssertFalse(manager.status.isChargeEnabled)
        manager.send(command: .setHeating(enabled: true))
        XCTAssertTrue(manager.status.isHeatingEnabled)
        manager.send(command: .setEmergency(enabled: true))
        XCTAssertTrue(manager.status.isEmergencyEnabled)
        manager.setDemoMode(false)
        XCTAssertFalse(manager.isSimulatorMode)
        XCTAssertFalse(manager.isConnected)
        XCTAssertFalse(manager.hasTelemetry)
        XCTAssertFalse(manager.hasSettings)
        XCTAssertNil(manager.lastUpdate)
        XCTAssertTrue(manager.discoveredDevices.isEmpty)
        XCTAssertTrue(manager.status.cellVoltages.isEmpty)
        XCTAssertFalse(manager.canWrite)
    }

    func testPasswordsNeverUnlockWithoutReadDeviceInformation() {
        let manager = JKBluetoothManager(enableBluetooth: false)
        XCTAssertFalse(manager.authenticate(password: "1234"))
        XCTAssertFalse(manager.authenticate(password: "123456"))
        XCTAssertFalse(manager.authenticate(password: ""))
        XCTAssertFalse(manager.isAuthenticated)
    }

    func testExportContainsKnownParametersAndNoCredentials() throws {
        let manager = JKBluetoothManager(enableBluetooth: false)
        manager.setDemoMode(true)
        defer { manager.setDemoMode(false) }
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(manager.exportSettingsJSON.utf8)) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        let values = try XCTUnwrap(object["settings"] as? [String: Double])
        XCTAssertEqual(values["cellCount"], 16)
        XCTAssertNil(values["password"])
        XCTAssertFalse(manager.exportSettingsJSON.contains("1234"))
    }

    func testImportRejectsUnknownKeysAtomically() throws {
        let manager = JKBluetoothManager(enableBluetooth: false)
        manager.setDemoMode(true)
        defer { manager.setDemoMode(false) }
        let capacity = manager.settings.batteryCapacity
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(manager.exportSettingsJSON.utf8)) as? [String: Any])
        object["settings"] = ["batteryCapacity": 200.0, "arbitraryRegister": 1.0]
        let text = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        manager.importSettingsJSON(text)
        XCTAssertNotNil(manager.lastErrorMessage)
        XCTAssertEqual(manager.settings.batteryCapacity, capacity)
    }

    func testLogbookBoundsAndCRC() throws {
        var frame = [UInt8](repeating: 0, count: 300)
        frame.replaceSubrange(0..<4, with: [0x55, 0xAA, 0xEB, 0x90]); frame[4] = 5
        frame[6] = 255 // host must cap count at 50 entries
        frame[11] = 60; frame[15] = 0x11
        frame[299] = frame.prefix(299).reduce(0, &+)
        let records = try XCTUnwrap(JKLogbookCodec.decode(Data(frame)))
        XCTAssertEqual(records.count, 50)
        XCTAssertEqual(records[0].uptime, 60)
        XCTAssertEqual(records[0].event, "单体过压保护")
        frame[12] ^= 1
        XCTAssertNil(JKLogbookCodec.decode(Data(frame)))
        XCTAssertNil(JKLogbookCodec.decode(Data(frame.prefix(12))))
    }
}
