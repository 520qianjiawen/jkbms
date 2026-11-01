import XCTest
@testable import JKBMSCore

final class JKParameterCatalogTests: XCTestCase {
    private func frame(type: UInt8 = 1, fields: [(Int, UInt32)] = [], bytes: [(Int, UInt8)] = []) -> Data {
        var data = [UInt8](repeating: 0, count: 300)
        data.replaceSubrange(0..<4, with: [0x55, 0xAA, 0xEB, 0x90])
        data[4] = type
        for (offset, value) in fields {
            for index in 0..<4 { data[offset + index] = UInt8(truncatingIfNeeded: value >> (8 * index)) }
        }
        for (offset, value) in bytes { data[offset] = value }
        data[299] = data.prefix(299).reduce(0, &+)
        return Data(data)
    }

    func testCatalogIDsAreUniqueAndUnsupportedVariantsStayClosed() {
        let definitions = JKParameterCatalog.definitions
        XCTAssertEqual(definitions.count, Set(definitions.map(\.id)).count)
        XCTAssertGreaterThanOrEqual(definitions.count, 45)
        for definition in definitions {
            XCTAssertFalse(JKParameterCatalog.supports(id: definition.id, variant: .automatic))
            XCTAssertFalse(JKParameterCatalog.supports(id: definition.id, variant: .legacy))
        }
        XCTAssertTrue(JKParameterCatalog.supports(id: "chargeOCPRecovery", variant: .jk02_24s))
        XCTAssertFalse(JKParameterCatalog.supports(id: "heatingStartTemperature", variant: .jk02_24s))
        XCTAssertTrue(JKParameterCatalog.supports(id: "heatingStartTemperature", variant: .jk02_32s))
    }

    func testRegisterDifferencesAndNegativeTemperatureEncoding() throws {
        let oldStart = try JKParameterCatalog.encode(id: "balancingStartVoltage", value: 3.4, variant: .jk02_24s)
        let newStart = try JKParameterCatalog.encode(id: "balancingStartVoltage", value: 3.4, variant: .jk02_32s)
        XCTAssertEqual(oldStart[4], 0x26)
        XCTAssertEqual(newStart[4], 0x22)
        XCTAssertEqual(Array(newStart[6...9]), [0x48, 0x0D, 0, 0])
        let cold = try JKParameterCatalog.encode(id: "chargeUnderTempRecovery", value: -9.0, variant: .jk02_32s)
        XCTAssertEqual(cold[4], 0x19)
        XCTAssertEqual(Array(cold[6...9]), [0xA6, 0xFF, 0xFF, 0xFF])
        let heating = try JKParameterCatalog.encode(id: "heatingStartTemperature", value: -20, variant: .jk02_32s)
        XCTAssertEqual(heating[4], 0x37)
        XCTAssertEqual(heating[5], 1)
        XCTAssertEqual(heating[6], 0xEC)
        XCTAssertEqual(heating[19], heating.prefix(19).reduce(0, &+))
    }

    func testJK04UsesFloatAndItsOwnRange() throws {
        let packet = try JKParameterCatalog.encode(id: "powerOffVoltage", value: 3.25, variant: .jk04)
        XCTAssertEqual(packet[4], 0x20)
        XCTAssertEqual(Array(packet[6...9]), [0x00, 0x00, 0x50, 0x40])
        XCTAssertThrowsError(try JKParameterCatalog.encode(id: "powerOffVoltage", value: 4, variant: .jk04))
        XCTAssertThrowsError(try JKParameterCatalog.encode(id: "balancingStartVoltage", value: 4.25, variant: .jk04))
        let decoded = JKParameterCatalog.decode(frame: frame(fields: [(38, Float(3.25).bitPattern), (98, Float(3.4).bitPattern)]), variant: .jk04)
        XCTAssertEqual(decoded["powerOffVoltage"] ?? 0, 3.25, accuracy: 0.0001)
        XCTAssertEqual(decoded["balancingStartVoltage"] ?? 0, 3.4, accuracy: 0.0001)
        XCTAssertNil(decoded["chargeOCPRecovery"])
    }

    func testSettingsDecodeSignedValuesAndBothControlBytes() {
        let received = frame(fields: [(30, 3650), (54, 30), (102, UInt32(bitPattern: -90)), (110, 780)],
                             bytes: [(282, 0b11010010), (283, 0b10101001), (284, 0xEC), (285, 5), (286, 23), (297, 0xF6)])
        let values = JKParameterCatalog.decode(frame: received, variant: .jk02_32s)
        XCTAssertEqual(values["soc100Voltage"] ?? 0, 3.65, accuracy: 0.0001)
        XCTAssertEqual(values["chargeOCPDelay"], 30)
        XCTAssertEqual(values["chargeUnderTempRecovery"], -9)
        XCTAssertEqual(values["mosOverTempRecovery"], 78)
        XCTAssertEqual(values["heatingStartTemperature"], -20)
        XCTAssertEqual(values["dischargeUnderTempRecovery"], -10)
        XCTAssertEqual(values["smartSleepHours"], 23)
        XCTAssertEqual(values["disableTemperatureSensors"], 1)
        XCTAssertEqual(values["displayAlwaysOn"], 1)
        XCTAssertEqual(values["disablePCLModule"], 1)
        XCTAssertEqual(values["timedStoredData"], 1)
        XCTAssertEqual(values["dryContactIntermittent"], 1)
        XCTAssertEqual(values["gpsLockedDischarging"], 1)
        XCTAssertEqual(values["gpsLockedCharging"], 0)
        XCTAssertNil(values["requestedChargeHours"])
    }

    func testDeviceInfoReadbackIsSeparateAndMasksLimitProtocolChoices() throws {
        let received = frame(type: 3, fields: [(186, 0b1010), (202, 0b10001), (219, 2), (271, 1)],
                             bytes: [(184, 1), (185, 4), (218, 1), (234, 11), (266, 10), (267, 80), (269, 5), (278, 15)])
        var settings = JKBMSSettings()
        settings.extendedValues = JKParameterCatalog.decode(frame: received, variant: .jk02_32s)
        XCTAssertEqual(settings.extendedValues["requestedChargeHours"], 1)
        XCTAssertEqual(settings.extendedValues["requestedFloatHours"], 8)
        XCTAssertEqual(settings.extendedValues["emergencyDuration"], 5)
        XCTAssertEqual(settings.extendedValues["reBulkSOC"], 15)
        XCTAssertEqual(Set(JKParameterCatalog.availableOptions(id: "uart1Protocol", settings: settings).keys), [1, 3])
        XCTAssertEqual(Set(JKParameterCatalog.availableOptions(id: "canProtocol", settings: settings).keys), [0, 4])
        XCTAssertTrue(JKParameterCatalog.isValueAvailable(id: "uart1Protocol", value: 1, settings: settings))
        XCTAssertFalse(JKParameterCatalog.isValueAvailable(id: "uart1Protocol", value: 2, settings: settings))
        XCTAssertFalse(JKParameterCatalog.isValueAvailable(id: "uart1Protocol", value: 1, settings: JKBMSSettings()))
        XCTAssertTrue(JKParameterCatalog.readbackNeedsDeviceInfo(id: "uart1Protocol"))
        XCTAssertFalse(JKParameterCatalog.readbackNeedsDeviceInfo(id: "multiplexedPortMode"))
        let packet = try JKParameterCatalog.encode(id: "uart1Protocol", value: 3, variant: .jk02_32s)
        XCTAssertEqual(packet[4], 0xA5)
        XCTAssertEqual(packet[5], 2)
        XCTAssertEqual(packet[6], 3)
        XCTAssertThrowsError(try JKParameterCatalog.encode(id: "canProtocol", value: 99, variant: .jk02_32s))
    }

    func testInvalidFramesInvalidValuesAndFalseAcknowledgmentsAreRejected() throws {
        var received = frame(fields: [(54, 30)])
        received[20] ^= 1
        XCTAssertTrue(JKParameterCatalog.decode(frame: received, variant: .jk02_32s).isEmpty)
        XCTAssertTrue(JKParameterCatalog.decode(frame: Data([0x55, 0xAA]), variant: .jk02_32s).isEmpty)
        XCTAssertThrowsError(try JKParameterCatalog.encode(id: "chargeOCPDelay", value: .nan, variant: .jk02_32s))
        XCTAssertThrowsError(try JKParameterCatalog.encode(id: "chargeOCPDelay", value: 2.5, variant: .jk02_32s))
        XCTAssertThrowsError(try JKParameterCatalog.encode(id: "gpsLockedCharging", value: 0.5, variant: .jk02_32s))
        XCTAssertThrowsError(try JKParameterCatalog.encode(id: "unknown", value: 1, variant: .jk02_32s))
        var settings = JKBMSSettings()
        XCTAssertFalse(JKParameterCatalog.matches(id: "chargeOCPDelay", value: 30, settings: settings))
        settings.extendedValues["chargeOCPDelay"] = 30
        XCTAssertTrue(JKParameterCatalog.matches(id: "chargeOCPDelay", value: 30, settings: settings))
        XCTAssertFalse(JKParameterCatalog.matches(id: "chargeOCPDelay", value: 31, settings: settings))
    }
}
