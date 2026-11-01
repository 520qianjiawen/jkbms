import Foundation

/// Legacy JK UART 4E57 framing. BLE JK02/JK04 must use JKModernCodec.
/// Register writes intentionally require a separately evidenced authentication flow.
public struct JKPacketCodec {
    public static let headerV1: [UInt8] = [0x4E, 0x57]
    public static let endMarker: UInt8 = 0x68

    public static func encode(command: JKCommand) -> Data {
        switch command {
        case .requestTelemetry, .requestSettings:
            var b: [UInt8] = [0x4E, 0x57, 0x00, 0x13, 0, 0, 0, 0, 0x06, 0x02, 0, 0, 0, 0, 0, 0, 0x68, 0, 0]
            let sum = b.reduce(UInt16(0)) { $0 &+ UInt16($1) }
            b += [UInt8(sum >> 8), UInt8(truncatingIfNeeded: sum)]
            return Data(b)
        default: return Data()
        }
    }

    public static func isValid(data: Data) -> Bool {
        let b = [UInt8](data)
        guard b.count >= 21, b[0] == 0x4E, b[1] == 0x57 else { return false }
        let length = Int(b[2]) << 8 | Int(b[3])
        guard length + 2 == b.count, b[b.count - 5] == 0x68 else { return false }
        let computed = b.prefix(length).reduce(UInt16(0)) { $0 &+ UInt16($1) }
        return computed == UInt16(b[length]) << 8 | UInt16(b[length + 1])
    }

    public static func decode(data: Data) -> JKBMSStatus? { decodeAll(data: data)?.status }
    public static func decodeSettings(data: Data) -> JKBMSSettings? { decodeAll(data: data)?.settings }

    private static func decodeAll(data: Data) -> (status: JKBMSStatus, settings: JKBMSSettings)? {
        guard isValid(data: data) else { return nil }
        let frame = [UInt8](data)
        guard frame[8] == 0x06, frame[10] == 1 || frame[10] == 2 else { return nil }
        let b = Array(frame[11..<(frame.count - 5)])
        guard b.count >= 2, b[0] == 0x79, b[1] > 0, b[1] % 3 == 0,
              b[1] <= 96, b.count >= Int(b[1]) + 223 else { return nil }
        func u16(_ i: Int) -> UInt16 { UInt16(b[i]) << 8 | UInt16(b[i + 1]) }
        func u32(_ i: Int) -> UInt32 { UInt32(u16(i)) << 16 | UInt32(u16(i + 2)) }
        func text(_ i: Int, _ n: Int) -> String { String(bytes: b[i..<(i + n)].prefix(while: { $0 != 0 }), encoding: .utf8) ?? "" }
        func temp(_ i: Int) -> Double { let v = Int(u16(i)); return Double(v > 100 ? 100 - v : v) }
        let offset = Int(b[1]) + 3
        let cells = Int(b[1]) / 3
        // Fixed register sequence from JK UART read-all records. Reject a mismatched layout.
        for (at, tag) in [(offset - 1, UInt8(0x80)), (offset + 8, 0x83), (offset + 11, 0x84), (offset + 14, 0x85), (offset + 218, 0xC0)] {
            guard b[at] == tag else { return nil }
        }
        var s = JKBMSStatus()
        s.cellVoltages = (0..<cells).map { Double(u16($0 * 3 + 3)) / 1000 }
        guard s.cellVoltages.allSatisfy({ (0...6).contains($0) }) else { return nil }
        s.mosTemperature = temp(offset); s.batteryT1 = temp(offset + 3); s.batteryT2 = temp(offset + 6)
        s.batteryVoltage = Double(u16(offset + 9)) / 100
        let raw = u16(offset + 12)
        let version = b[offset + 219]
        // Version-specific direction is defined in the upstream UART parser.
        let magnitude = Double(raw & 0x7FFF) / 100
        s.batteryCurrent = legacyCurrent(raw: raw, version: version, magnitude: magnitude)
        s.soc = Double(b[offset + 15]); guard s.soc <= 100 else { return nil }
        s.hasCycleCount = true
        s.ambientTemperature = .nan
        s.cycleCount = Int(u16(offset + 19)); s.totalCycleCapacity = Double(u32(offset + 22))
        s.alarms = JKBMSAlarm.parseAlarms(from: UInt32(u16(offset + 30)))
        let flags = u16(offset + 33)
        s.isChargeEnabled = flags & 1 != 0; s.isDischargeEnabled = flags & 2 != 0; s.isBalanceEnabled = flags & 4 != 0
        s.totalCapacity = Double(u32(offset + 118)); s.remainingCapacity = s.totalCapacity * s.soc / 100
        s.deviceModel = text(offset + 152, 8); s.firmwareVersion = text(offset + 171, 15)
        s.uptimeSeconds = UInt32(clamping: UInt64(u32(offset + 166)) * 60)
        s.manufactureDate = text(offset + 161, 4)
        s.deviceSN = text(offset + 194, 24)
        s.recalculateStats()
        var settings = JKBMSSettings()
        settings.cellCount = cells; settings.batteryCapacity = s.totalCapacity
        settings.cellOvervoltageProtection = Double(u16(offset + 42)) / 1000
        settings.cellOvervoltageRecovery = Double(u16(offset + 45)) / 1000
        settings.cellUndervoltageProtection = Double(u16(offset + 51)) / 1000
        settings.cellUndervoltageRecovery = Double(u16(offset + 54)) / 1000
        settings.continuousDischargeCurrent = Double(u16(offset + 63)); settings.continuousChargeCurrent = Double(u16(offset + 69))
        settings.balanceTriggerVoltage = Double(u16(offset + 78)) / 1000; settings.balanceMaxCurrent = 0
        settings.isBalanceEnabled = b[offset + 81] != 0
        settings.mosOverTempProtection = Double(u16(offset + 83))
        settings.batteryChargeOverTempProtection = Double(u16(offset + 98)); settings.batteryDischargeOverTempProtection = Double(u16(offset + 101))
        settings.batteryChargeUnderTempProtection = Double(Int16(bitPattern: u16(offset + 104)))
        settings.batteryDischargeUnderTempProtection = Double(Int16(bitPattern: u16(offset + 110)))
        settings.isChargeEnabled = b[offset + 123] != 0; settings.isDischargeEnabled = b[offset + 125] != 0
        settings.password = text(offset + 139, 10)
        return (s, settings)
    }

    private static func legacyCurrent(raw: UInt16, version: UInt8, magnitude: Double) -> Double {
        // Only protocol version 1 has an evidenced direction encoding.
        guard version == 1 else { return .nan }
        return raw & 0x8000 != 0 ? magnitude : -magnitude
    }
}
