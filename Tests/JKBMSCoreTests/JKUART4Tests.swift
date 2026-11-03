import XCTest
@testable import JKBMSCore

final class JKUART4Tests: XCTestCase {
    private func frame(current: UInt8 = 1, mask: UInt32 = 0b1010, visible: Bool = true, writable: Bool = true, type: UInt8 = 3) -> Data {
        var bytes = [UInt8](repeating: 0, count: 300)
        bytes.replaceSubrange(0..<4, with: [0x55, 0xAA, 0xEB, 0x90]); bytes[4] = type
        bytes[21] = 32; bytes[298] = 1
        bytes[279] = current
        for index in 0..<4 { bytes[280 + index] = UInt8(truncatingIfNeeded: mask >> (index * 8)) }
        if visible { bytes[287 + 38 / 8] |= 1 << (38 % 8) }
        if writable { bytes[150 + 0xB8 / 8] |= 1 << (0xB8 % 8) }
        bytes[299] = bytes.prefix(299).reduce(0, &+)
        return Data(bytes)
    }
    private func settings(_ frame: Data) -> JKBMSSettings {
        var result = JKBMSSettings()
        result.extendedValues = JKParameterCatalog.decode(frame: frame, variant: .jk02_32s)
        return result
    }

    func testUART4UsesItsOwnAllowMaskAndPreservesUnknownCurrentValue() {
        let state = settings(frame())
        XCTAssertEqual(state.extendedValues["uart4Protocol"], 1)
        XCTAssertEqual(Set(JKParameterCatalog.availableOptions(id: "uart4Protocol", settings: state).keys), [1, 3])
        XCTAssertTrue(JKParameterCatalog.isValueAvailable(id: "uart4Protocol", value: 3, settings: state))
        XCTAssertFalse(JKParameterCatalog.isValueAvailable(id: "uart4Protocol", value: 2, settings: state))
        XCTAssertFalse(JKParameterCatalog.isValueAvailable(id: "uart4Protocol", value: 1.5, settings: state))
        XCTAssertTrue(JKParameterCatalog.availableOptions(id: "uart4Protocol", settings: settings(frame(mask: 0))).isEmpty)
        XCTAssertTrue(JKParameterCatalog.availableOptions(id: "uart4Protocol", settings: JKBMSSettings()).isEmpty)
        let unknown = settings(frame(current: 99, mask: (1 << 1) | (1 << 31)))
        XCTAssertEqual(unknown.extendedValues["uart4Protocol"], 99)
        XCTAssertEqual(Set(JKParameterCatalog.availableOptions(id: "uart4Protocol", settings: unknown).keys), [1])
        XCTAssertFalse(JKParameterCatalog.isValueAvailable(id: "uart4Protocol", value: 99, settings: unknown))
    }

    func testUART4WirePacketAndVariantRestrictions() throws {
        let packet = try JKModernCodec.encode(command: .setParameter(id: "uart4Protocol", value: 3), variant: .jk02_32s, settings: settings(frame()))
        XCTAssertEqual(Array(packet.prefix(10)), [0xAA, 0x55, 0x90, 0xEB, 0xB8, 2, 3, 0, 0, 0])
        XCTAssertEqual(packet.count, 20)
        XCTAssertEqual(packet[19], packet.prefix(19).reduce(0, &+))
        XCTAssertThrowsError(try JKModernCodec.encode(command: .setParameter(id: "uart4Protocol", value: 2), variant: .jk02_32s, settings: settings(frame())))
        for variant in [JKProtocolVariant.jk02_24s, .jk04, .legacy, .automatic] {
            XCTAssertFalse(JKParameterCatalog.supports(id: "uart4Protocol", variant: variant))
            XCTAssertThrowsError(try JKParameterCatalog.encode(id: "uart4Protocol", value: 1, variant: variant))
            XCTAssertNil(JKParameterCatalog.decode(frame: frame(), variant: variant)["uart4Protocol"])
        }
        XCTAssertTrue(JKParameterCatalog.readbackNeedsDeviceInfo(id: "uart4Protocol"))
    }

    func testUART4ReadbackOnlyComesFromValidatedDeviceInfo() {
        XCTAssertNil(settings(frame(type: 1)).extendedValues["uart4Protocol"])
        var bad = frame(); bad[279] ^= 1
        XCTAssertNil(settings(bad).extendedValues["uart4Protocol"])
        XCTAssertFalse(JKParameterCatalog.matches(id: "uart4Protocol", value: 3, settings: settings(frame(current: 1))))
        XCTAssertTrue(JKParameterCatalog.matches(id: "uart4Protocol", value: 3, settings: settings(frame(current: 3))))
    }

    func testBoardVisibilityAndCommandSupportGateUIAndWrites() {
        let manager = JKBluetoothManager(enableBluetooth: false)
        manager.receive(frame())
        XCTAssertTrue(manager.uart4ProtocolVisible)
        XCTAssertTrue(manager.supports(command: .setParameter(id: "uart4Protocol", value: 1)))
        manager.receive(frame(writable: false))
        XCTAssertTrue(manager.uart4ProtocolVisible)
        XCTAssertFalse(manager.supports(command: .setParameter(id: "uart4Protocol", value: 1)))
        manager.receive(frame(visible: false))
        XCTAssertFalse(manager.uart4ProtocolVisible)
        XCTAssertFalse(manager.supports(command: .setParameter(id: "uart4Protocol", value: 1)))
    }

    func testUART4BackupImportRespectsAllowedProtocolsAndDoesNotPartiallyApplyInvalidFile() throws {
        let manager = JKBluetoothManager(enableBluetooth: false)
        manager.setDemoMode(true)
        defer { manager.setDemoMode(false) }
        for (id, value) in settings(frame()).extendedValues {
            manager.simulator.execute(command: .setParameter(id: id, value: value))
        }
        manager.send(command: .requestSettings)
        var document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(manager.exportSettingsJSON.utf8)) as? [String: Any])
        let exported = try XCTUnwrap(document["settings"] as? [String: Double])
        XCTAssertEqual(exported["uart4Protocol"], 1)
        XCTAssertNil(exported["uart4Protocol.enabledMask"])
        let capacity = manager.settings.batteryCapacity
        document["settings"] = ["batteryCapacity": 200.0, "uart4Protocol": 2.0]
        manager.importSettingsJSON(String(decoding: try JSONSerialization.data(withJSONObject: document), as: UTF8.self))
        XCTAssertEqual(manager.settings.batteryCapacity, capacity)
        XCTAssertEqual(manager.settings.extendedValues["uart4Protocol"], 1)
        document["settings"] = ["uart4Protocol": 3.0]
        manager.importSettingsJSON(String(decoding: try JSONSerialization.data(withJSONObject: document), as: UTF8.self))
        XCTAssertEqual(manager.settings.extendedValues["uart4Protocol"], 3)
        manager.send(command: .setParameter(id: "uart4Protocol", value: 2))
        XCTAssertEqual(manager.settings.extendedValues["uart4Protocol"], 3)
    }
}
