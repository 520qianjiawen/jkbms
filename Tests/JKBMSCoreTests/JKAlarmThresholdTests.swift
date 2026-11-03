import XCTest
@testable import JKBMSCore

final class JKAlarmThresholdTests: XCTestCase {
    private func settings(_ channel: JKAlarmThresholds.Channel = JKAlarmThresholds.channels[0], source: Double = 4,
                          trigger: Double = 3620, release: Double = 3580) -> JKBMSSettings {
        var settings = JKBMSSettings()
        settings.extendedValues = [channel.id: source, channel.triggerID: trigger, channel.releaseID: release]
        return settings
    }

    func testUnitsRangesAndStrictHysteresisForDocumentedSources() throws {
        let cases: [(Int, String, Double, Double, Bool)] = [
            (1, "%", 0, 99, true), (2, "mV", 0, 105000, false), (3, "mV", 0, 105000, true),
            (4, "mV", 0, 5000, false), (5, "mV", 0, 5000, true),
            (6, "mA", 0, 1000000, false), (7, "mA", 0, 1000000, false),
            (8, "℃", -50, 150, false), (9, "℃", -50, 150, false), (11, "℃", -50, 150, true), (13, "%", 0, 99, false)
        ]
        for (source, unit, minimum, maximum, below) in cases {
            let rule = try XCTUnwrap(JKAlarmThresholds.rule(source: source))
            XCTAssertEqual(rule.unit, unit); XCTAssertEqual(rule.range, minimum...maximum)
            XCTAssertEqual(rule.triggersBelow, below)
            XCTAssertTrue(rule.accepts(trigger: below ? minimum : maximum, release: below ? maximum : minimum))
            XCTAssertFalse(rule.accepts(trigger: minimum, release: minimum))
            XCTAssertFalse(rule.contains(minimum - 1)); XCTAssertFalse(rule.contains(maximum + 1))
            XCTAssertFalse(rule.contains(minimum + 0.5)); XCTAssertFalse(rule.contains(.nan))
        }
    }

    func testSourceSwitchChangesUnitsAndHidesUnspecifiedThresholds() throws {
        var snapshot = settings()
        for (source, unit, upper) in [(4.0, "mV", 5000.0), (6.0, "mA", 1000000.0), (11.0, "℃", 150.0), (1.0, "%", 99.0)] {
            snapshot.extendedValues["lcdBuzzerTrigger"] = source
            let definition = try XCTUnwrap(JKAlarmThresholds.definition(id: "lcdBuzzerTriggerVal", settings: snapshot))
            XCTAssertEqual(definition.unit, unit); XCTAssertEqual(definition.range.upperBound, upper)
            XCTAssertEqual(definition.step, 1)
        }
        for source in [0, 10, 12, 14, 99] {
            snapshot.extendedValues["lcdBuzzerTrigger"] = Double(source)
            XCTAssertFalse(JKParameterCatalog.definitions(settings: snapshot).contains { $0.id == "lcdBuzzerTriggerVal" })
            XCTAssertThrowsError(try JKModernCodec.encode(command: .setParameter(id: "lcdBuzzerTriggerVal", value: 10), variant: .jk02_32s, settings: snapshot))
        }
    }

    func testAllSixRegistersAndNegativeTemperatureUseRawSignedIntegers() throws {
        for channel in JKAlarmThresholds.channels {
            let snapshot = settings(channel, source: 11, trigger: -10, release: 0)
            for (id, value, register) in [(channel.triggerID, -10.0, channel.triggerRegister), (channel.releaseID, 0.0, channel.triggerRegister + 1)] {
                let packet = try JKModernCodec.encode(command: .setParameter(id: id, value: value), variant: .jk02_32s, settings: snapshot)
                XCTAssertEqual(packet.count, 20); XCTAssertEqual(packet[4], register); XCTAssertEqual(packet[5], 4)
                XCTAssertEqual(Array(packet[6...9]), value < 0 ? [246, 255, 255, 255] : [0, 0, 0, 0])
                XCTAssertEqual(packet[19], packet.prefix(19).reduce(0, &+))
                XCTAssertThrowsError(try JKParameterCatalog.encode(id: id, value: value, variant: .jk02_32s))
                XCTAssertThrowsError(try JKParameterCatalog.encode(id: id, value: value, variant: .jk02_24s, settings: snapshot))
            }
        }
        let voltage = try JKParameterCatalog.encode(id: "lcdBuzzerTriggerVal", value: 3620, variant: .jk02_32s, settings: settings())
        XCTAssertEqual(Array(voltage[6...9]), [0x24, 0x0E, 0, 0])
    }

    func testDeviceInfoDecodePreservesRawOutOfRangeValuesForRepair() throws {
        var frame = [UInt8](repeating: 0, count: 300)
        frame.replaceSubrange(0..<4, with: [0x55, 0xAA, 0xEB, 0x90]); frame[4] = 3
        frame[234] = 11; frame[235] = 4; frame[236] = 6
        for (offset, value) in [(238, -10), (242, 0), (246, 3620), (250, 3580), (254, 110000), (258, 98000)] {
            let raw = UInt32(bitPattern: Int32(value))
            for index in 0..<4 { frame[offset + index] = UInt8(truncatingIfNeeded: raw >> (index * 8)) }
        }
        frame[299] = frame.prefix(299).reduce(0, &+)
        var snapshot = JKBMSSettings()
        snapshot.extendedValues = JKParameterCatalog.decode(frame: Data(frame), variant: .jk02_32s)
        XCTAssertEqual(snapshot.extendedValues["lcdBuzzerTriggerVal"], -10)
        XCTAssertEqual(snapshot.extendedValues["dry1TriggerVal"], 3620)
        XCTAssertEqual(snapshot.extendedValues["dry2ReleaseVal"], 98000)
        XCTAssertTrue(JKParameterCatalog.matches(id: "lcdBuzzerTriggerVal", value: -10, settings: snapshot))
        XCTAssertFalse(JKParameterCatalog.matches(id: "lcdBuzzerTriggerVal", value: -9, settings: snapshot))
        frame[238] ^= 1
        XCTAssertTrue(JKAlarmThresholds.decode(frame: Data(frame), variant: .jk02_32s).isEmpty)
        XCTAssertTrue(JKAlarmThresholds.decode(frame: Data([0x55]), variant: .jk02_32s).isEmpty)
    }

    func testInvalidPairsFractionalValuesAndMissingContextAreRejected() {
        let snapshot = settings()
        for value in [0, 3580, 3500, 5001, 3620.5, Double.nan, Double.infinity] {
            XCTAssertFalse(JKParameterCatalog.isValueAvailable(id: "lcdBuzzerTriggerVal", value: value, settings: snapshot))
        }
        XCTAssertTrue(JKParameterCatalog.isValueAvailable(id: "lcdBuzzerTriggerVal", value: 3650, settings: snapshot))
        XCTAssertFalse(JKParameterCatalog.isValueAvailable(id: "lcdBuzzerTriggerVal", value: 3650, settings: JKBMSSettings()))
        let stale = settings(source: 8) // Existing mV values are not valid degrees.
        XCTAssertFalse(JKAlarmThresholds.rule(id: "lcdBuzzerTriggerVal", settings: stale)!.contains(3620))
        XCTAssertTrue(JKAlarmThresholds.isValueAvailable(id: "lcdBuzzerTriggerVal", value: 60, settings: stale))
        XCTAssertTrue(JKParameterCatalog.readbackNeedsDeviceInfo(id: "dry2ReleaseVal"))
    }

    func testImportValidatesFinalPairAndOrdersIntermediateWrites() throws {
        let snapshot = settings(source: 1, trigger: 25, release: 30)
        let values = ["lcdBuzzerTrigger": 1.0, "lcdBuzzerTriggerVal": 50.0, "lcdBuzzerReleaseVal": 60.0]
        let updates = try JKAlarmThresholds.importUpdates(values, settings: snapshot)
        XCTAssertEqual(updates.map { $0.0 }, ["lcdBuzzerReleaseVal", "lcdBuzzerTriggerVal"])
        var projected = snapshot
        for (id, value) in updates {
            XCTAssertNoThrow(try JKModernCodec.encode(command: .setParameter(id: id, value: value), variant: .jk02_32s, settings: projected))
            projected.extendedValues[id] = value
        }
        XCTAssertThrowsError(try JKAlarmThresholds.importUpdates(["lcdBuzzerTrigger": 8, "lcdBuzzerTriggerVal": 50], settings: snapshot))
        XCTAssertThrowsError(try JKAlarmThresholds.importUpdates(["lcdBuzzerTriggerVal": 10], settings: snapshot))
        XCTAssertThrowsError(try JKAlarmThresholds.importUpdates(["lcdBuzzerTrigger": 1, "lcdBuzzerTriggerVal": 50, "lcdBuzzerReleaseVal": 40], settings: snapshot))
    }

    func testManagerRejectsStaleEditorAndInvalidImportWithoutOtherMutations() throws {
        let manager = JKBluetoothManager(enableBluetooth: false)
        manager.setDemoMode(true)
        defer { manager.setDemoMode(false) }
        for (id, value) in settings(source: 1, trigger: 25, release: 30).extendedValues {
            manager.simulator.execute(command: .setParameter(id: id, value: value))
        }
        manager.send(command: .requestSettings)
        manager.setAlarmThreshold(id: "lcdBuzzerTriggerVal", value: 20, expectedSource: 8, expectedDevice: manager.connectedDevice?.id)
        XCTAssertEqual(manager.settings.extendedValues["lcdBuzzerTriggerVal"], 25)
        XCTAssertNotNil(manager.lastErrorMessage)
        manager.setAlarmThreshold(id: "lcdBuzzerTriggerVal", value: 20, expectedSource: 1, expectedDevice: UUID())
        XCTAssertEqual(manager.settings.extendedValues["lcdBuzzerTriggerVal"], 25)
        manager.setAlarmThreshold(id: "lcdBuzzerTriggerVal", value: 20, expectedSource: 1, expectedDevice: manager.connectedDevice?.id)
        XCTAssertEqual(manager.settings.extendedValues["lcdBuzzerTriggerVal"], 20)
        let capacity = manager.settings.batteryCapacity
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(manager.exportSettingsJSON.utf8)) as? [String: Any])
        object["settings"] = ["batteryCapacity": 200.0, "lcdBuzzerTrigger": 1.0, "lcdBuzzerTriggerVal": 90.0, "lcdBuzzerReleaseVal": 30.0]
        manager.importSettingsJSON(String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self))
        XCTAssertEqual(manager.settings.batteryCapacity, capacity)
        XCTAssertEqual(manager.settings.extendedValues["lcdBuzzerTriggerVal"], 20)
    }
    func testBoardCapabilityAndVisibilityFlagsGateThresholdWrites() throws {
        let manager = JKBluetoothManager(enableBluetooth: false)
        var frame = [UInt8](repeating: 0, count: 300)
        frame.replaceSubrange(0..<4, with: [0x55, 0xAA, 0xEB, 0x90]); frame[4] = 3
        frame[21] = 32; frame[298] = 1; frame[234] = 4
        let fields = JKOriginalSchema.fields(family: "JK-BXAXS-XP", type: 3)
        let commands = try XCTUnwrap(fields.first { $0.key == "cmdSupportFlags" })
        let visible = try XCTUnwrap(fields.first { $0.key == "enableFlags" })
        frame[commands.offset + 0xAC / 8] |= 1 << (0xAC % 8)
        frame[visible.offset + 25 / 8] |= 1 << (25 % 8)
        func receive() {
            frame[299] = frame.prefix(299).reduce(0, &+)
            manager.receive(Data(frame))
        }
        receive()
        XCTAssertEqual(manager.originalSchemaName, "JK-BXAXS-XP")
        XCTAssertTrue(manager.alarmFieldVisible("lcdBuzzerTriggerVal"))
        XCTAssertTrue(manager.supports(command: .setParameter(id: "lcdBuzzerTriggerVal", value: 3620)))
        XCTAssertFalse(manager.supports(command: .setParameter(id: "lcdBuzzerReleaseVal", value: 3580)))
        frame[commands.offset + 0xAC / 8] = 0
        receive()
        XCTAssertFalse(manager.supports(command: .setParameter(id: "lcdBuzzerTriggerVal", value: 3620)))
        frame[visible.offset + 25 / 8] = 0
        receive()
        XCTAssertFalse(manager.alarmFieldVisible("lcdBuzzerTriggerVal"))
    }

    func testBackupRoundtripKeepsRawUnitsAndAppliesValidPairInOrder() throws {
        let manager = JKBluetoothManager(enableBluetooth: false)
        manager.setDemoMode(true)
        defer { manager.setDemoMode(false) }
        for (id, value) in settings(source: 1, trigger: 25, release: 30).extendedValues {
            manager.simulator.execute(command: .setParameter(id: id, value: value))
        }
        manager.send(command: .requestSettings)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(manager.exportSettingsJSON.utf8)) as? [String: Any])
        let exported = try XCTUnwrap(original["settings"] as? [String: Double])
        XCTAssertEqual(exported["lcdBuzzerTrigger"], 1)
        XCTAssertEqual(exported["lcdBuzzerTriggerVal"], 25)
        var replacement = original
        replacement["settings"] = ["lcdBuzzerTrigger": 1.0, "lcdBuzzerTriggerVal": 50.0, "lcdBuzzerReleaseVal": 60.0]
        manager.importSettingsJSON(String(decoding: try JSONSerialization.data(withJSONObject: replacement), as: UTF8.self))
        XCTAssertNil(manager.lastErrorMessage)
        XCTAssertEqual(manager.settings.extendedValues["lcdBuzzerTriggerVal"], 50)
        XCTAssertEqual(manager.settings.extendedValues["lcdBuzzerReleaseVal"], 60)
    }

    func testHighSOCUsesPercentIntegersAndExistingSignedThresholdRegisters() throws {
        for channel in JKAlarmThresholds.channels {
            let snapshot = settings(channel, source: 13, trigger: 90, release: 80)
            let definition = try XCTUnwrap(JKAlarmThresholds.definition(id: channel.triggerID, settings: snapshot))
            XCTAssertEqual(definition.unit, "%")
            XCTAssertEqual(definition.range, 0...99)
            XCTAssertTrue(JKAlarmThresholds.isValueAvailable(id: channel.triggerID, value: 99, settings: snapshot))
            for value in [-1, 0, 80, 90.5, 100] {
                XCTAssertFalse(JKAlarmThresholds.isValueAvailable(id: channel.triggerID, value: value, settings: snapshot))
            }
            XCTAssertFalse(JKAlarmThresholds.isValueAvailable(id: channel.releaseID, value: 90, settings: snapshot))
            let packet = try JKModernCodec.encode(command: .setParameter(id: channel.triggerID, value: 90), variant: .jk02_32s, settings: snapshot)
            XCTAssertEqual(packet[4], channel.triggerRegister)
            XCTAssertEqual(Array(packet[6...9]), [90, 0, 0, 0])
            XCTAssertTrue(JKParameterCatalog.matches(id: channel.triggerID, value: 90, settings: snapshot))
        }
    }

    func testHighSOCImportMaintainsHysteresisAndRejectsOldSourceContext() throws {
        let snapshot = settings(source: 13, trigger: 90, release: 80)
        let updates = try JKAlarmThresholds.importUpdates([
            "lcdBuzzerTrigger": 13, "lcdBuzzerTriggerVal": 70, "lcdBuzzerReleaseVal": 60
        ], settings: snapshot)
        XCTAssertEqual(updates.map { $0.0 }, ["lcdBuzzerReleaseVal", "lcdBuzzerTriggerVal"])
        XCTAssertThrowsError(try JKAlarmThresholds.importUpdates([
            "lcdBuzzerTrigger": 13, "lcdBuzzerTriggerVal": 70, "lcdBuzzerReleaseVal": 80
        ], settings: snapshot))
        XCTAssertThrowsError(try JKAlarmThresholds.importUpdates([
            "lcdBuzzerTrigger": 1, "lcdBuzzerTriggerVal": 70, "lcdBuzzerReleaseVal": 60
        ], settings: snapshot))
    }

}
