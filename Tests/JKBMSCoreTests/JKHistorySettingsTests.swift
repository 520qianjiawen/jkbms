import XCTest
@testable import JKBMSCore

final class JKHistorySettingsTests: XCTestCase {
    private func frame(period: UInt32 = 60, visible: Bool = true, writable: Bool = true, type: UInt8 = 3) -> Data {
        var bytes = [UInt8](repeating: 0, count: 300)
        bytes.replaceSubrange(0..<4, with: [0x55, 0xAA, 0xEB, 0x90]); bytes[4] = type
        bytes[21] = 32; bytes[298] = 1
        for index in 0..<4 { bytes[262 + index] = UInt8(truncatingIfNeeded: period >> (8 * index)) }
        if visible { bytes[287 + 31 / 8] |= 1 << (31 % 8) }
        if writable { bytes[150 + 0xB2 / 8] |= 1 << (0xB2 % 8) }
        bytes[299] = bytes.prefix(299).reduce(0, &+)
        return Data(bytes)
    }

    func testHistoryPeriodUsesOriginalRangeAndFourByteSecondsPayload() throws {
        let definition = try XCTUnwrap(JKParameterCatalog.definitions.first { $0.id == "dataStoredPeriod" })
        XCTAssertEqual(definition.unit, "s"); XCTAssertEqual(definition.step, 1)
        XCTAssertEqual(definition.range, 5...864000)
        for value in [5.0, 60, 864000] {
            let packet = try JKModernCodec.encode(command: .setParameter(id: "dataStoredPeriod", value: value), variant: .jk02_32s)
            XCTAssertEqual(packet[4], 0xB2); XCTAssertEqual(packet[5], 4)
            let raw = (0..<4).reduce(UInt32(0)) { $0 | UInt32(packet[6 + $1]) << (8 * $1) }
            XCTAssertEqual(raw, UInt32(value))
            XCTAssertEqual(packet[19], packet.prefix(19).reduce(0, &+))
        }
        for value in [-1.0, 0, 4, 5.5, 864001, Double.nan, Double.infinity] {
            XCTAssertThrowsError(try JKParameterCatalog.encode(id: "dataStoredPeriod", value: value, variant: .jk02_32s))
        }
        for variant in [JKProtocolVariant.jk02_24s, .jk04, .legacy, .automatic] {
            XCTAssertFalse(JKParameterCatalog.supports(id: "dataStoredPeriod", variant: variant))
            XCTAssertThrowsError(try JKParameterCatalog.encode(id: "dataStoredPeriod", value: 60, variant: variant))
        }
    }

    func testHistoryPeriodOnlyDecodesFromValidDeviceInfoAndPreservesValuesForRepair() {
        var settings = JKBMSSettings()
        settings.extendedValues = JKParameterCatalog.decode(frame: frame(period: 864000), variant: .jk02_32s)
        XCTAssertEqual(settings.extendedValues["dataStoredPeriod"], 864000)
        XCTAssertTrue(JKParameterCatalog.matches(id: "dataStoredPeriod", value: 864000, settings: settings))
        XCTAssertFalse(JKParameterCatalog.matches(id: "dataStoredPeriod", value: 60, settings: settings))
        XCTAssertEqual(JKParameterCatalog.decode(frame: frame(period: 0), variant: .jk02_32s)["dataStoredPeriod"], 0)
        XCTAssertNil(JKParameterCatalog.decode(frame: frame(type: 1), variant: .jk02_32s)["dataStoredPeriod"])
        var bad = frame(); bad[262] ^= 1
        XCTAssertNil(JKParameterCatalog.decode(frame: bad, variant: .jk02_32s)["dataStoredPeriod"])
        XCTAssertTrue(JKParameterCatalog.readbackNeedsDeviceInfo(id: "dataStoredPeriod"))
    }

    func testHistoryPeriodVisibilityAndCommandSupportAreSeparate() {
        let manager = JKBluetoothManager(enableBluetooth: false)
        manager.receive(frame())
        XCTAssertTrue(manager.dataStoredPeriodVisible)
        XCTAssertTrue(manager.supports(command: .setParameter(id: "dataStoredPeriod", value: 60)))
        manager.receive(frame(writable: false))
        XCTAssertTrue(manager.dataStoredPeriodVisible)
        XCTAssertFalse(manager.supports(command: .setParameter(id: "dataStoredPeriod", value: 60)))
        manager.receive(frame(visible: false))
        XCTAssertFalse(manager.dataStoredPeriodVisible)
        XCTAssertFalse(manager.supports(command: .setParameter(id: "dataStoredPeriod", value: 60)))
    }

    func testHistoryPeriodBackupAndImportValidateBeforeChangingOtherParameters() throws {
        let manager = JKBluetoothManager(enableBluetooth: false)
        manager.setDemoMode(true)
        defer { manager.setDemoMode(false) }
        manager.simulator.execute(command: .setParameter(id: "dataStoredPeriod", value: 60))
        manager.send(command: .requestSettings)
        var document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(manager.exportSettingsJSON.utf8)) as? [String: Any])
        let exported = try XCTUnwrap(document["settings"] as? [String: Double])
        XCTAssertEqual(exported["dataStoredPeriod"], 60)
        let capacity = manager.settings.batteryCapacity
        document["settings"] = ["batteryCapacity": 200.0, "dataStoredPeriod": 864001.0]
        manager.importSettingsJSON(String(decoding: try JSONSerialization.data(withJSONObject: document), as: UTF8.self))
        XCTAssertEqual(manager.settings.batteryCapacity, capacity)
        XCTAssertEqual(manager.settings.extendedValues["dataStoredPeriod"], 60)
        document["settings"] = ["dataStoredPeriod": 120.0]
        manager.importSettingsJSON(String(decoding: try JSONSerialization.data(withJSONObject: document), as: UTF8.self))
        XCTAssertEqual(manager.settings.extendedValues["dataStoredPeriod"], 120)
        manager.send(command: .setParameter(id: "dataStoredPeriod", value: 5.5))
        XCTAssertEqual(manager.settings.extendedValues["dataStoredPeriod"], 120)
    }
}
