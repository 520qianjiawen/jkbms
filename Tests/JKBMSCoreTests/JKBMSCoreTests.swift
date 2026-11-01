import XCTest
@testable import JKBMSCore

final class JKBMSCoreTests: XCTestCase {
    func testTelemetryRequestsAndChecksums() throws {
        let modern = JKModernCodec.command(register: 0x96)
        XCTAssertEqual(modern.count, 20)
        XCTAssertEqual(Array(modern.prefix(6)), [0xAA, 0x55, 0x90, 0xEB, 0x96, 0])
        XCTAssertEqual(modern[19], modern.prefix(19).reduce(0, &+))
        let legacy = JKPacketCodec.encode(command: .requestTelemetry)
        XCTAssertEqual(legacy.count, 21)
        XCTAssertTrue(JKPacketCodec.isValid(data: legacy))
        XCTAssertEqual(legacy[9], 2)
        XCTAssertTrue(JKPacketCodec.encode(command: .setCharge(enabled: true)).isEmpty)
    }

    func testModernRegisterEncodingAndSignedTemperature() throws {
        let packet = try JKModernCodec.encode(command: .setCharge(enabled: true), variant: .jk02_32s)
        XCTAssertEqual(packet[4], 0x1D); XCTAssertEqual(packet[5], 4); XCTAssertEqual(packet[6], 1)
        let temp = try JKModernCodec.encode(command: .setChargeUnderTemperature(celsius: -22), variant: .jk02_32s)
        XCTAssertEqual(temp[4], 0x18)
        XCTAssertEqual(Array(temp[6...9]), [0x24, 0xFF, 0xFF, 0xFF])
        let discharge = try JKModernCodec.encode(command: .setDischargeUnderTemperature(celsius: -20), variant: .jk02_32s)
        XCTAssertEqual(discharge[4], 0x3A); XCTAssertEqual(discharge[5], 1); XCTAssertEqual(discharge[6], 0xEC)
        let capacity = try JKModernCodec.encode(command: .setCapacity(ah: 310), variant: .jk02_24s)
        XCTAssertEqual(capacity[4], 0x20); XCTAssertEqual(Array(capacity[6...9]), [0xF0, 0xBA, 0x04, 0])
        let heat = try JKModernCodec.encode(command: .setHeating(enabled: true), variant: .jk02_32s)
        XCTAssertEqual(heat[4], 0x27)
        XCTAssertEqual(try JKModernCodec.encode(command: .restartBoard, variant: .jk02_32s)[4], 0x66)
        XCTAssertEqual(try JKModernCodec.encode(command: .shutdownBoard, variant: .jk02_32s)[5], 0)
    }

    func testUnsupportedOperationsAndInvalidValuesAreRejected() {
        for cmd in [JKCommand.setCapacity(ah: .nan), .setCapacity(ah: .infinity), .setCellCount(count: 33), .setBalanceTriggerVoltage(volts: -1), .setChargeUnderTemperature(celsius: -100), .setContinuousChargeCurrent(amps: 0)] {
            XCTAssertThrowsError(try JKModernCodec.encode(command: cmd, variant: .jk02_32s))
        }
        XCTAssertThrowsError(try JKModernCodec.encode(command: .setCharge(enabled: true), variant: .automatic))
        XCTAssertThrowsError(try JKModernCodec.encode(command: .setCharge(enabled: true), variant: .jk04))
        XCTAssertThrowsError(try JKModernCodec.encode(command: .setDischargeUnderTemperature(celsius: -20), variant: .jk02_24s))
        XCTAssertThrowsError(try JKModernCodec.encode(command: .setPassword(newPass: "000000"), variant: .jk02_32s))
        XCTAssertThrowsError(try JKModernCodec.encode(command: .customRegister(reg: 1, data: [1]), variant: .jk02_32s))
    }

    func testJK04FloatWriteEncoding() throws {
        let packet = try JKModernCodec.encode(command: .setBalanceMaxCurrent(amps: 4.5), variant: .jk04)
        XCTAssertEqual(packet[4], 0x68); XCTAssertEqual(packet[5], 4)
        XCTAssertEqual(Array(packet[6...9]), [0, 0, 0x90, 0x40])
        let count = try JKModernCodec.encode(command: .setCellCount(count: 16), variant: .jk04)
        XCTAssertEqual(count[5], 2)
    }

    func testCaptured24SStatus() throws {
        let frame = JKProtocolFixtures.CELL_INFO_JK02_24S_V10
        let s = try XCTUnwrap(JKModernCodec.parse(frame: frame, variant: .jk02_24s)?.status)
        XCTAssertEqual(s.cellVoltages.count, 24)
        XCTAssertEqual(s.batteryVoltage, 78.735, accuracy: 0.001)
        XCTAssertEqual(s.minCellVoltage, 3.279, accuracy: 0.001)
        XCTAssertEqual(s.maxCellVoltage, 3.285, accuracy: 0.001)
        XCTAssertEqual(s.mosTemperature, 23.4, accuracy: 0.01)
        XCTAssertEqual(s.soc, 85)
        XCTAssertTrue(s.isChargeEnabled); XCTAssertFalse(s.isDischargeEnabled)
    }

    func testCapturedNegativeTemperatures() throws {
        let s = try XCTUnwrap(JKModernCodec.parse(frame: JKProtocolFixtures.CELL_INFO_JK02_24S_V10_NEG_TEMPS, variant: .jk02_24s)?.status)
        XCTAssertEqual(s.cellVoltages.count, 13)
        XCTAssertEqual(s.batteryT1, -3.1, accuracy: 0.01)
        XCTAssertEqual(s.batteryT2, -2.9, accuracy: 0.01)
        XCTAssertEqual(s.mosTemperature, 0.5, accuracy: 0.01)
    }

    func testCaptured32SPBStatusOffsets() throws {
        let s = try XCTUnwrap(JKModernCodec.parse(frame: JKProtocolFixtures.CELL_INFO_JK02_32S_V14, variant: .jk02_32s)?.status)
        XCTAssertEqual(s.cellVoltages.count, 16)
        XCTAssertEqual(s.batteryVoltage, 49.526, accuracy: 0.001)
        XCTAssertEqual(s.minCellVoltage, 2.851, accuracy: 0.001)
        XCTAssertEqual(s.maxCellVoltage, 3.175, accuracy: 0.001)
        XCTAssertEqual(s.deltaVoltage, 0.324, accuracy: 0.001)
        XCTAssertEqual(s.mosTemperature, 18.2, accuracy: 0.01)
        XCTAssertEqual(s.batteryT1, 16.8, accuracy: 0.01)
        XCTAssertEqual(s.remainingCapacity, 1.007, accuracy: 0.001)
        XCTAssertEqual(s.soc, 50)
        XCTAssertEqual(s.uptimeSeconds, 124641)
        XCTAssertTrue(s.isChargeEnabled); XCTAssertTrue(s.isDischargeEnabled)
    }

    func testAbsentTemperatureSensorsAreUnknown() throws {
        var frame = JKProtocolFixtures.CELL_INFO_JK02_32S_V14
        frame[214] = 0
        frame[299] = frame.prefix(299).reduce(0, &+)
        let s = try XCTUnwrap(JKModernCodec.parse(frame: frame, variant: .jk02_32s)?.status)
        XCTAssertTrue(s.mosTemperature.isNaN); XCTAssertTrue(s.batteryT1.isNaN); XCTAssertTrue(s.batteryT2.isNaN)
        XCTAssertTrue(s.extraTemperatures.allSatisfy(\.isNaN))
        XCTAssertEqual(JKModernCodec.detectVariant(frame: frame), .jk02_32s)
    }

    func testCaptured32SSignedCurrentBothDirections() throws {
        let charging = try XCTUnwrap(JKModernCodec.parse(frame: JKProtocolFixtures.CELL_INFO_JK02_32S_V15, variant: .jk02_32s)?.status)
        let discharging = try XCTUnwrap(JKModernCodec.parse(frame: JKProtocolFixtures.CELL_INFO_JK02_32S_V19, variant: .jk02_32s)?.status)
        XCTAssertEqual(charging.batteryCurrent, 31.881, accuracy: 0.001)
        XCTAssertEqual(discharging.batteryCurrent, -0.727, accuracy: 0.001)
    }

    func testCapturedJK04FloatStatusAndSettings() throws {
        let s = try XCTUnwrap(JKModernCodec.parse(frame: JKProtocolFixtures.CELL_INFO_JK04, variant: .jk04)?.status)
        XCTAssertEqual(s.cellVoltages.count, 16)
        XCTAssertEqual(s.batteryVoltage, 53.691, accuracy: 0.02)
        XCTAssertTrue(s.batteryCurrent.isNaN); XCTAssertTrue(s.soc.isNaN)
        XCTAssertTrue(s.mosTemperature.isNaN); XCTAssertTrue(s.totalCapacity.isNaN)
        XCTAssertTrue(s.totalCycleCapacity.isNaN); XCTAssertFalse(s.hasCycleCount)
        let settings = try XCTUnwrap(JKModernCodec.parse(frame: JKProtocolFixtures.SETTINGS_JK04_B5A24S, variant: .jk04)?.settings)
        XCTAssertEqual(settings.cellCount, 16)
        XCTAssertEqual(settings.balanceTriggerVoltage, 0.008, accuracy: 0.0001)
        XCTAssertEqual(settings.balanceMaxCurrent, 4.5, accuracy: 0.001)
    }

    func testCapturedDeviceInfoAndSettings() throws {
        let info = try XCTUnwrap(JKModernCodec.parse(frame: JKProtocolFixtures.DEVICE_INFO_JK02_32S_V14, variant: .automatic)?.info)
        XCTAssertEqual(info.model, "JK_PB2A16S15P"); XCTAssertEqual(info.hardware, "14.XA"); XCTAssertEqual(info.firmware, "14.20")
        XCTAssertEqual(info.serial, "3092572134"); XCTAssertEqual(info.manufactureDate, "20231118")
        XCTAssertEqual(info.devicePassword, "1234"); XCTAssertEqual(info.setupPassword, "123457")
        let settings = try XCTUnwrap(JKModernCodec.parse(frame: JKProtocolFixtures.SETTINGS_JK02_32S_V19, variant: .jk02_32s)?.settings)
        XCTAssertEqual(settings.cellCount, 16)
        XCTAssertEqual(settings.batteryCapacity, 314, accuracy: 0.001)
        XCTAssertTrue(settings.isChargeEnabled)
        XCTAssertTrue(settings.isDischargeEnabled)
    }

    func testMalformedDeviceInformationCannotBecomeEmptyCredentials() {
        var frame = JKProtocolFixtures.DEVICE_INFO_JK02_32S_V14
        frame[118] = 0xFF
        frame[299] = frame.prefix(299).reduce(0, &+)
        XCTAssertNil(JKModernCodec.parse(frame: frame, variant: .automatic))
        frame.replaceSubrange(6..<22, with: repeatElement(UInt8(0), count: 16))
        frame[299] = frame.prefix(299).reduce(0, &+)
        XCTAssertNil(JKModernCodec.parse(frame: frame, variant: .automatic))
    }

    func testAutomaticDetectionAcrossCapturedLayouts() {
        let cases: [(Data, JKProtocolVariant)] = [
            (JKProtocolFixtures.CELL_INFO_JK02_24S_V10, .jk02_24s),
            (JKProtocolFixtures.CELL_INFO_JK02_24S_V10_NEG_TEMPS, .jk02_24s),
            (JKProtocolFixtures.CELL_INFO_JK02_32S_V11, .jk02_32s),
            (JKProtocolFixtures.CELL_INFO_JK02_32S_V14, .jk02_32s),
            (JKProtocolFixtures.CELL_INFO_JK02_32S_V15, .jk02_32s),
            (JKProtocolFixtures.CELL_INFO_JK02_32S_V19, .jk02_32s),
            (JKProtocolFixtures.CELL_INFO_JK04, .jk04),
            (JKProtocolFixtures.CELL_INFO_JK04_B5A24S, .jk04)
        ]
        for (frame, expected) in cases { XCTAssertEqual(JKModernCodec.detectVariant(frame: frame), expected) }
        XCTAssertNil(JKModernCodec.detectVariant(frame: JKProtocolFixtures.DEVICE_INFO_JK02_32S_V14))
    }

    func testCorruptionAndAllTruncationsAreRejected() {
        let frame = JKProtocolFixtures.CELL_INFO_JK02_32S_V14
        for length in 0..<300 { XCTAssertNil(JKModernCodec.parse(frame: Data(frame.prefix(length)), variant: .jk02_32s)) }
        var corrupt = frame; corrupt[120] ^= 1
        XCTAssertNil(JKModernCodec.parse(frame: corrupt, variant: .jk02_32s))
        // Valid CRC with invalid payload must not cause crashes or invent telemetry.
        var invalid = Data(repeating: 0, count: 300)
        invalid.replaceSubrange(0..<5, with: [0x55, 0xAA, 0xEB, 0x90, 2])
        invalid[299] = invalid.prefix(299).reduce(0, &+)
        XCTAssertNil(JKModernCodec.detectVariant(frame: invalid))
    }

    func testAssemblerSplitAtEveryBoundaryAndCoalescedFrames() {
        let frame = JKProtocolFixtures.CELL_INFO_JK02_32S_V14
        for boundary in 1..<300 {
            var assembler = JKStreamAssembler()
            XCTAssertTrue(assembler.append(Data(frame.prefix(boundary))).isEmpty)
            XCTAssertEqual(assembler.append(Data(frame.dropFirst(boundary))), [frame])
        }
        var assembler = JKStreamAssembler()
        XCTAssertEqual(assembler.append(frame + frame), [frame, frame])
        XCTAssertEqual(assembler.append(Data([1, 2, 3]) + frame), [frame])
    }

    func testAssemblerRecoversFromCorruptAnd320ByteTrailer() {
        var assembler = JKStreamAssembler()
        let frame = JKProtocolFixtures.CELL_INFO_JK02_24S_V10
        var corrupt = frame; corrupt[299] ^= 1
        XCTAssertEqual(assembler.append(corrupt + frame), [frame])
        let trailer = JKModernCodec.command(register: 0x96)
        XCTAssertEqual(assembler.append(frame + trailer + frame), [frame, frame])
        XCTAssertTrue(assembler.append(Data([0x4E, 0x57, 0, 0]) + frame).contains(frame))
        XCTAssertTrue(assembler.append(Data([0x4E, 0x57, 0x0F, 0xFE]) + frame).contains(frame))
        XCTAssertEqual(assembler.append(Data(repeating: 0xFE, count: 20000) + frame), [frame])
        XCTAssertLessThan(assembler.bufferedByteCount, 4097)
    }

    func testLegacyValidatedFrameAndSettings() throws {
        let frame = legacyFixture()
        XCTAssertTrue(JKPacketCodec.isValid(data: frame))
        let s = try XCTUnwrap(JKPacketCodec.decode(data: frame))
        XCTAssertEqual(s.cellVoltages.count, 4)
        XCTAssertEqual(s.batteryVoltage, 13.32, accuracy: 0.01)
        XCTAssertEqual(s.batteryCurrent, 2.5, accuracy: 0.01)
        XCTAssertEqual(s.mosTemperature, -5)
        XCTAssertEqual(JKPacketCodec.decodeSettings(data: frame)?.cellOvervoltageProtection ?? 0, 3.65, accuracy: 0.001)
        var bad = frame; bad[30] ^= 1
        XCTAssertNil(JKPacketCodec.decode(data: bad))
        for n in 0..<frame.count { XCTAssertNil(JKPacketCodec.decode(data: Data(frame.prefix(n)))) }
        var assembler = JKStreamAssembler()
        XCTAssertEqual(assembler.append(Data(frame.prefix(5))), [])
        XCTAssertEqual(assembler.append(Data(frame.dropFirst(5))), [frame])
    }

    func testDefaultStatusContainsNoDemoValuesAndEmptyStatsReset() {
        var s = JKBMSStatus()
        XCTAssertTrue(s.cellVoltages.isEmpty); XCTAssertTrue(s.deviceSN.isEmpty)
        XCTAssertEqual(s.batteryVoltage, 0); XCTAssertEqual(s.soc, 0)
        XCTAssertFalse(s.isChargeEnabled)
        s.cellVoltages = [3.2, 3.4]; s.recalculateStats(); XCTAssertEqual(s.deltaVoltage, 0.2, accuracy: 0.001)
        s.cellVoltages = []; s.recalculateStats(); XCTAssertEqual(s.deltaVoltage, 0); XCTAssertEqual(s.averageVoltage, 0)
    }

    func testModernAlarmBitsAndReadbackComparison() {
        let alarms = JKBMSAlarm.parseModern(from: (1 << 16) | (1 << 27))
        XCTAssertEqual(alarms.map(\.bit), [16, 27])
        XCTAssertTrue(alarms[0].name.contains("MOS"))
        var settings = JKBMSSettings(); settings.isBalanceEnabled = true
        XCTAssertTrue(JKModernCodec.matches(command: .setBalance(enabled: true), status: JKBMSStatus(), settings: settings))
        XCTAssertFalse(JKModernCodec.matches(command: .setBalance(enabled: false), status: JKBMSStatus(), settings: settings))
        settings.batteryChargeUnderTempProtection = -20
        XCTAssertTrue(JKModernCodec.matches(command: .setChargeUnderTemperature(celsius: -20), status: JKBMSStatus(), settings: settings))
    }

    private func legacyFixture() -> Data {
        var payload = [UInt8](repeating: 0, count: 235)
        payload[0] = 0x79; payload[1] = 12
        for i in 0..<4 { payload[2 + i * 3] = UInt8(i + 1); payload[3 + i * 3] = 0x0D; payload[4 + i * 3] = 0x02 }
        let o = 15
        func u16(_ i: Int, _ value: UInt16) { payload[i] = UInt8(value >> 8); payload[i + 1] = UInt8(truncatingIfNeeded: value) }
        for (i, tag) in [(o - 1, UInt8(0x80)), (o + 8, 0x83), (o + 11, 0x84), (o + 14, 0x85), (o + 218, 0xC0)] { payload[i] = tag }
        u16(o, 105); u16(o + 9, 1332); u16(o + 12, 0x80FA); payload[o + 15] = 90; payload[o + 219] = 1
        u16(o + 42, 3650)
        var bytes: [UInt8] = [0x4E, 0x57, 0, 0, 0, 0, 0, 0, 0x06, 0, 1] + payload + [0, 0, 0, 0, 0x68, 0, 0]
        let length = bytes.count
        bytes[2] = UInt8(length >> 8); bytes[3] = UInt8(truncatingIfNeeded: length)
        let crc = bytes.reduce(UInt16(0)) { $0 &+ UInt16($1) }
        bytes += [UInt8(crc >> 8), UInt8(truncatingIfNeeded: crc)]
        return Data(bytes)
    }
}
