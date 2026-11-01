import XCTest
@testable import JKBMSCore

final class JKOriginalSchemaTests: XCTestCase {
    func testAllSevenOriginalFamiliesLoadFromBundledResource() {
        XCTAssertEqual(JKOriginalSchema.families.count, 7)
        for family in JKOriginalSchema.families {
            XCTAssertFalse(JKOriginalSchema.fields(family: family, type: 1).isEmpty)
            XCTAssertFalse(JKOriginalSchema.fields(family: family, type: 2).isEmpty)
            XCTAssertFalse(JKOriginalSchema.fields(family: family, type: 3).isEmpty)
        }
    }
    func testOriginalXPSettingsAgreeWithCapturedDevice() throws {
        let values = JKOriginalSchema.decode(JKProtocolFixtures.SETTINGS_JK02_32S_V19, family: "JK-BXAXS-XP")
        let dictionary = Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) })
        XCTAssertEqual(dictionary["cellCount"]?.number, 16)
        XCTAssertEqual(dictionary["capBatCell"]?.number ?? -1, 314, accuracy: 0.001)
        let encoded = try JKOriginalSchema.encode(key: "volCellOV", value: 3.65, family: "JK-BXAXS-XP")
        XCTAssertEqual(encoded, try JKModernCodec.encode(command: .setCellOvervoltageProtection(volts: 3.65), variant: .jk02_32s))
    }
    func testOriginalDeviceFieldsDoNotReplacePasswordsWithDefaults() throws {
        let values = JKOriginalSchema.decode(JKProtocolFixtures.DEVICE_INFO_JK02_32S_V14, family: "JK-BXAXS-XP")
        let password = try XCTUnwrap(values.first(where: { $0.id == "settingPassword" }))
        XCTAssertTrue(password.field.isPrivate)
        XCTAssertEqual(password.text, "123457")
        var corrupted = JKProtocolFixtures.DEVICE_INFO_JK02_32S_V14
        corrupted[5] ^= 1
        XCTAssertTrue(JKOriginalSchema.decode(corrupted, family: "JK-BXAXS-XP").isEmpty)
    }
    func testOriginalRangesRejectNonfiniteAndOutOfRangeWrites() {
        XCTAssertThrowsError(try JKOriginalSchema.encode(key: "volCellOV", value: .nan, family: "JK-BXAXS-XP"))
        XCTAssertThrowsError(try JKOriginalSchema.encode(key: "volCellOV", value: 10, family: "JK-BXAXS-XP"))
        XCTAssertThrowsError(try JKOriginalSchema.encode(key: "bluetoothPwd", value: 1234, family: "JK-BXAXS-XP"))
    }
}

extension JKOriginalSchemaTests {
    func testOriginalCommandPayloadsAndPrivateTextLimits() throws {
        let packet = try JKOriginalCommands.text("native-test", kind: .name)
        XCTAssertEqual(packet[4], 0x9B)
        XCTAssertEqual(packet[5], 11)
        XCTAssertEqual(packet[19], packet.prefix(19).reduce(0, &+))
        XCTAssertThrowsError(try JKOriginalCommands.text("", kind: .settingsPassword))
        XCTAssertThrowsError(try JKOriginalCommands.text("1234567890123", kind: .settingsPassword))
        XCTAssertThrowsError(try JKOriginalCommands.text("中文名", kind: .name))
        let clock = try JKOriginalCommands.timeCalibration(date: Date(timeIntervalSince1970: 1577836860))
        XCTAssertEqual(clock[4], 0x6C); XCTAssertEqual(clock[5], 4)
        XCTAssertEqual(Array(clock[6..<10]), [60, 0, 0, 0])
    }
    func testOriginalDetailedLogRecordsAndMalformedCount() throws {
        var frame = [UInt8](repeating: 0, count: 300)
        frame.replaceSubrange(0..<4, with: [0x55, 0xAA, 0xEB, 0x90]); frame[4] = 6
        frame[6] = 10; frame[8] = 1; frame[9] = 60; frame[13] = 0x11
        frame[299] = frame.prefix(299).reduce(0, &+)
        let records = try XCTUnwrap(JKOriginalSchema.detailedLogs(Data(frame), family: "JK-BXAXS-XP"))
        XCTAssertEqual(records.count, 1); XCTAssertEqual(records[0].index, 10)
        XCTAssertEqual(records[0].date, Date(timeIntervalSince1970: 1577836860))
        XCTAssertEqual(records[0].event, "单体过压保护")
        frame[8] = 13; frame[299] = frame.prefix(299).reduce(0, &+)
        XCTAssertNil(JKOriginalSchema.detailedLogs(Data(frame), family: "JK-BXAXS-XP"))
    }
    func testManagerIntegratesCapturedOriginalIdentitySettingsAndStatusWithoutDemo() {
        let manager = JKBluetoothManager(enableBluetooth: false)
        manager.receive(JKProtocolFixtures.DEVICE_INFO_JK02_32S_V14)
        manager.receive(JKProtocolFixtures.SETTINGS_JK02_32S_V19)
        manager.receive(JKProtocolFixtures.CELL_INFO_JK02_32S_V14)
        XCTAssertFalse(manager.isSimulatorMode)
        XCTAssertEqual(manager.originalSchemaName, "JK-BXAXS-XP")
        XCTAssertTrue(manager.hasSettings)
        XCTAssertTrue(manager.requiresDevicePassword)
        XCTAssertFalse(manager.hasTelemetry) // captured device flags require the connection password
        XCTAssertEqual(manager.status.cellCount, 16)
        XCTAssertEqual(manager.status.batteryVoltage, 49.526, accuracy: 0.001)
        XCTAssertFalse(manager.originalDeviceInfo.contains(where: { $0.field.isPrivate }))
        XCTAssertFalse(manager.authenticate(password: "123456")) // no actual BLE session
        XCTAssertFalse(manager.canWrite)
    }
}

extension JKOriginalSchemaTests {
    func testOriginalJKCFGImportsBothValidatedFramesAndOmitsPasswordsFromPreview() throws {
        let data = JKProtocolFixtures.SETTINGS_JK02_32S_V19 + JKProtocolFixtures.DEVICE_INFO_JK02_32S_V14
        let backup = try JKOriginalBackup(data: data)
        XCTAssertEqual(backup.family, "JK-BXAXS-XP")
        XCTAssertEqual(backup.model, "JK_PB2A16S15P")
        XCTAssertEqual(backup.cellCount, 16)
        XCTAssertEqual(backup.values["original.capBatCell"], 314)
        XCTAssertFalse(backup.values.keys.contains(where: { $0.lowercased().contains("password") || $0.lowercased().contains("pwd") }))
        XCTAssertThrowsError(try JKOriginalBackup(data: Data(data.dropFirst())))
        XCTAssertThrowsError(try JKOriginalBackup(data: JKProtocolFixtures.DEVICE_INFO_JK02_32S_V14 + JKProtocolFixtures.SETTINGS_JK02_32S_V19))
        var damaged = data; damaged[30] ^= 1
        XCTAssertThrowsError(try JKOriginalBackup(data: damaged))
    }
    func testOriginalSwitchRegistersAgreeWithDocumentedSeparateSwitchCommands() throws {
        let heating = try JKOriginalSchema.encodeSwitch(key: "switchStatus", bit: 0, enabled: true, family: "JK-BXAXS-XP")
        XCTAssertEqual(heating, try JKModernCodec.encode(command: .setHeating(enabled: true), variant: .jk02_32s))
        XCTAssertEqual(try JKOriginalSchema.encodeSwitch(key: "switchStatus", bit: 15, enabled: false, family: "JK-BXAXS-XP")[4], 0x36)
        XCTAssertThrowsError(try JKOriginalSchema.encodeSwitch(key: "switchStatus", bit: 16, enabled: true, family: "JK-BXAXS-XP"))
    }
    func testOriginalDirectoryIsCompleteAndStable() {
        XCTAssertGreaterThan(DeviceCatalog.defaultModels.count, 100)
        XCTAssertEqual(Set(DeviceCatalog.defaultModels.map(\.id)).count, DeviceCatalog.defaultModels.count)
    }
}

extension JKOriginalSchemaTests {
    func testV2ModelMaximumCellByteDoesNotBecomeInvalidModelText() throws {
        var frame = JKProtocolFixtures.DEVICE_INFO_JK02_32S_V14
        frame.replaceSubrange(6..<21, with: Array("JK-BXAXS-XP".utf8) + [UInt8](repeating: 0, count: 4))
        frame[21] = 32; frame[298] = 1; frame[299] = frame.prefix(299).reduce(0, &+)
        XCTAssertEqual(JKOriginalSchema.identify(infoFrame: frame), "JK-BXAXS-XP")
        let info = try XCTUnwrap(JKModernCodec.parse(frame: frame, variant: .automatic)?.info)
        XCTAssertEqual(info.model, "JK-BXAXS-XP")
    }
    func testBluetoothLoginFlagKeepsLiveDataLockedUntilLocalConfirmation() throws {
        var info = JKProtocolFixtures.DEVICE_INFO_JK02_32S_V14
        let field = try XCTUnwrap(JKOriginalSchema.fields(family: "JK-BXAXS-XP", type: 3).first(where: { $0.key == "enableFlags" }))
        info[field.offset] |= 0x80
        info[299] = info.prefix(299).reduce(0, &+)
        let manager = JKBluetoothManager(enableBluetooth: false)
        manager.receive(info)
        manager.receive(JKProtocolFixtures.CELL_INFO_JK02_32S_V14)
        XCTAssertTrue(manager.requiresDevicePassword)
        XCTAssertFalse(manager.hasTelemetry)
        XCTAssertFalse(manager.canWrite)
        manager.disconnect()
        XCTAssertFalse(manager.requiresDevicePassword)
    }
}
