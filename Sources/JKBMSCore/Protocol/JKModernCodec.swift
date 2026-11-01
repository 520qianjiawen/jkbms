import Foundation

public enum JKProtocolVariant: String, CaseIterable, Identifiable {
    case automatic, jk02_24s, jk02_32s, jk04, legacy
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .automatic: return "自动识别"
        case .jk02_24s: return "JK02 · 24S"
        case .jk02_32s: return "JK02 · 32S / PB"
        case .jk04: return "JK04 · 早期均衡器"
        case .legacy: return "旧版 4E57 · 只读"
        }
    }
}

public enum JKProtocolError: LocalizedError {
    case unsupported, invalidValue
    public var errorDescription: String? {
        switch self {
        case .unsupported: return "当前协议未支持此操作，请确认保护板协议版本。"
        case .invalidValue: return "参数超出允许范围，未发送到保护板。"
        }
    }
}

public struct JKDeviceInfo {
    public let model: String
    public let hardware: String
    public let firmware: String
    public let serial: String
    public let manufactureDate: String
    public let devicePassword: String
    public let setupPassword: String
    public let uptimeSeconds: UInt32
    public var suggestedVariant: JKProtocolVariant? {
        // Model hints never establish a layout; detectVariant validates status offsets.
        if model.uppercased().contains("PB") { return .jk02_32s }
        return nil
    }
}

public struct JKDecodedFrame {
    public let type: UInt8
    public var status: JKBMSStatus? = nil
    public var settings: JKBMSSettings? = nil
    public var info: JKDeviceInfo? = nil
}

/// JK BLE formats from syssi/esphome-jk-bms (Apache-2.0), jk_bms_ble.cpp and number.py.
/// A write is not an acknowledgement: the caller must request/read settings afterwards.
public enum JKModernCodec {
    public static func command(register: UInt8, value: UInt32 = 0, length: UInt8 = 0) -> Data {
        var bytes = [UInt8](repeating: 0, count: 20)
        bytes.replaceSubrange(0..<4, with: [0xAA, 0x55, 0x90, 0xEB])
        bytes[4] = register; bytes[5] = length
        for i in 0..<4 { bytes[6 + i] = UInt8(truncatingIfNeeded: value >> (8 * i)) }
        bytes[19] = bytes.prefix(19).reduce(0, &+)
        return Data(bytes)
    }

    public static func supports(command: JKCommand, variant: JKProtocolVariant) -> Bool {
        if case .setParameter(let id, _) = command, JKAlarmThresholds.isThreshold(id) {
            return JKParameterCatalog.supports(id: id, variant: variant)
        }
        return (try? encode(command: command, variant: variant)) != nil
    }

    public static func encode(command cmd: JKCommand, variant: JKProtocolVariant, settings: JKBMSSettings? = nil) throws -> Data {
        switch cmd {
        case .setOriginalSwitch(let family, let key, let bit, let enabled):
            return try JKOriginalSchema.encodeSwitch(key: key, bit: bit, enabled: enabled, family: family)
        case .setOriginalParameter(let family, let key, let value):
            return try JKOriginalSchema.encode(key: key, value: value, family: family)
        case .setParameter(let id, let value): return try JKParameterCatalog.encode(id: id, value: value, variant: variant, settings: settings)
        case .requestTelemetry, .requestSettings:
            return variant == .legacy ? JKPacketCodec.encode(command: .requestTelemetry) : command(register: 0x96)
        case .requestDeviceInfo:
            guard variant != .legacy else { throw JKProtocolError.unsupported }
            return command(register: 0x97)
        default: break
        }
        guard variant != .automatic && variant != .legacy else { throw JKProtocolError.unsupported }
        var register: UInt8
        var value: Double
        var factor: Double = 1
        var length: UInt8 = 4
        var range: ClosedRange<Double>
        switch cmd {
        case .setCharge(let enabled):
            guard variant != .jk04 else { throw JKProtocolError.unsupported }
            register = 0x1D; value = enabled ? 1 : 0; range = 0...1
        case .setDischarge(let enabled):
            guard variant != .jk04 else { throw JKProtocolError.unsupported }
            register = 0x1E; value = enabled ? 1 : 0; range = 0...1
        case .setBalance(let enabled):
            register = variant == .jk04 ? 0x6C : 0x1F
            length = variant == .jk04 ? 1 : 4; value = enabled ? 1 : 0; range = 0...1
        case .setEmergency(let enabled):
            guard variant == .jk02_32s else { throw JKProtocolError.unsupported }
            register = 0x6B; value = enabled ? 1 : 0; range = 0...1
        case .setHeating(let enabled):
            guard variant == .jk02_32s else { throw JKProtocolError.unsupported }
            register = 0x27; value = enabled ? 1 : 0; range = 0...1
        case .setCellCount(let count):
            register = 0x1C; value = Double(count); range = 1...(variant == .jk02_32s ? 32 : 24)
            if variant == .jk04 { length = 2 }
        case .setCapacity(let ah):
            guard variant != .jk04 else { throw JKProtocolError.unsupported }
            register = 0x20; value = ah; factor = 1000; range = 0.1...20000
        case .setBalanceTriggerVoltage(let volts):
            register = variant == .jk04 ? 0x64 : 0x06
            value = volts; factor = 1000; range = 0.002...1
        case .setBalanceMaxCurrent(let amps):
            register = variant == .jk04 ? 0x68 : 0x13
            value = amps; factor = 1000; range = 0.1...10
        case .setCellOvervoltageProtection(let volts):
            register = 0x04; value = volts; factor = 1000; range = 1.2...4.35
        case .setCellOvervoltageRecovery(let volts):
            register = 0x05; value = volts; factor = 1000; range = 1.2...4.35
        case .setCellUndervoltageProtection(let volts):
            register = 0x02; value = volts; factor = 1000; range = 1.2...4.35
        case .setCellUndervoltageRecovery(let volts):
            register = 0x03; value = volts; factor = 1000; range = 1.2...4.35
        case .setContinuousChargeCurrent(let amps):
            register = 0x0C; value = amps; factor = 1000; range = 1...1000
        case .setContinuousDischargeCurrent(let amps):
            register = 0x0F; value = amps; factor = 1000; range = 1...1000
        case .setMosOverTemperature(let celsius):
            register = 0x1A; value = celsius; factor = 10; range = 40...120
        case .setChargeOverTemperature(let celsius):
            register = 0x14; value = celsius; factor = 10; range = 0...100
        case .setDischargeOverTemperature(let celsius):
            register = 0x16; value = celsius; factor = 10; range = 0...100
        case .setChargeUnderTemperature(let celsius):
            register = 0x18; value = celsius; factor = 10; range = -45...30
        case .setDischargeUnderTemperature(let celsius):
            guard variant == .jk02_32s else { throw JKProtocolError.unsupported }
            register = 0x3A; value = celsius; length = 1; range = -45...30
        case .restartBoard, .shutdownBoard, .factoryRestore:
            guard variant == .jk02_32s else { throw JKProtocolError.unsupported }
            switch cmd { case .restartBoard: register = 0x66; case .shutdownBoard: register = 0x65; default: register = 0x9D }
            return command(register: register)
        default: throw JKProtocolError.unsupported
        }
        if variant == .jk04 {
            switch cmd {
            case .setBalance, .setCellCount, .setBalanceTriggerVoltage, .setBalanceMaxCurrent: break
            default: throw JKProtocolError.unsupported
            }
        }
        guard value.isFinite && range.contains(value) else { throw JKProtocolError.invalidValue }
        let raw: UInt32
        if variant == .jk04 && length == 4 { raw = Float(value).bitPattern }
        else { raw = UInt32(bitPattern: Int32((value * factor).rounded())) }
        return command(register: register, value: raw, length: length)
    }

    public static func isValid(frame: Data) -> Bool {
        let b = [UInt8](frame)
        return b.count >= 300 && Array(b.prefix(4)) == [0x55, 0xAA, 0xEB, 0x90] && b.prefix(299).reduce(0, &+) == b[299]
    }

    /// Require a unique structurally plausible status layout. Hardware/firmware numbers
    /// alone do not determine JK BLE packet layouts (e.g. HW8 JK04 exists).
    public static func detectVariant(frame: Data, info: JKDeviceInfo? = nil, settingsFrame: Data? = nil) -> JKProtocolVariant? {
        guard isValid(frame: frame), frame[frame.startIndex + 4] == 2 else { return nil }
        var candidates: [JKProtocolVariant] = []
        let b = [UInt8](frame.prefix(300))
        let r = Reader(bytes: b)
        for variant in [JKProtocolVariant.jk02_24s, .jk02_32s, .jk04] {
            guard let decoded = parse(frame: frame, variant: variant), let s = decoded.status,
                  !s.cellVoltages.isEmpty, s.cellVoltages.allSatisfy({ $0 == 0 || (0.5...5.5).contains($0) }),
                  s.batteryVoltage.isFinite, s.batteryVoltage > 0 else { continue }
            if variant != .jk04 {
                let offset = variant == .jk02_32s ? 32 : 0
                let sum = s.cellVoltages.reduce(0, +)
                guard abs(sum - s.batteryVoltage) < max(0.5, sum * 0.05),
                      b[166 + offset] <= 1, b[167 + offset] <= 1,
                      abs(s.batteryCurrent) < 2000, (!s.mosTemperature.isFinite || (-70...160).contains(s.mosTemperature)) else { continue }
            } else {
                guard s.cellWireResistances.allSatisfy({ $0.isFinite && (0...10000).contains($0) }),
                      s.balanceCurrent.isFinite, abs(s.balanceCurrent) < 20,
                      b[220] <= 2 else { continue }
                // A little-endian float voltage array is structurally distinct from JK02's mV uint16 array.
                guard (0..<s.cellVoltages.count).allSatisfy({ r.float(6 + $0 * 4) >= 0.5 }) else { continue }
            }
            if let settingsFrame, let settings = parse(frame: settingsFrame, variant: variant)?.settings {
                guard settings.cellCount == s.cellVoltages.count else { continue }
            }
            candidates.append(variant)
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    public static func parse(frame: Data, variant: JKProtocolVariant) -> JKDecodedFrame? {
        guard isValid(frame: frame) else { return nil }
        let b = [UInt8](frame.prefix(300))
        let r = Reader(bytes: b)
        if b[4] == 3 {
            // Invalid text must not become an empty setup password and accidentally unlock writes.
            let modelLength = b[298] != 0 && (1...32).contains(Int(b[21])) ? 15 : 16
            guard r.printable(6, modelLength), !r.text(6, modelLength).isEmpty,
                  r.printable(22, 8), !r.text(22, 8).isEmpty,
                  r.printable(30, 8), !r.text(30, 8).isEmpty,
                  r.printable(62, 16), r.printable(118, 16) else { return nil }
            let date = r.text(78, 6)
            let info = JKDeviceInfo(model: r.text(6, modelLength), hardware: r.text(22, 8), firmware: r.text(30, 8), serial: r.text(86, 11), manufactureDate: date.isEmpty ? "" : "20" + date, devicePassword: r.text(62, 16), setupPassword: r.text(118, 16), uptimeSeconds: r.u32(38))
            return JKDecodedFrame(type: 3, info: info)
        }
        guard variant != .automatic && variant != .legacy else { return nil }
        if b[4] == 1 {
            var s = JKBMSSettings()
            s.password = ""
            if variant == .jk04 {
                s.cellCount = Int(r.u16(34)); s.balanceTriggerVoltage = r.float(106); s.balanceMaxCurrent = r.float(110)
                s.isBalanceEnabled = b[114] != 0
                // JK04 is a balancer; it has no evidenced charge/MOS/temperature protection fields.
                s.batteryCapacity = .nan; s.cellOvervoltageProtection = .nan; s.cellOvervoltageRecovery = .nan
                s.cellUndervoltageProtection = .nan; s.cellUndervoltageRecovery = .nan
                s.continuousChargeCurrent = .nan; s.continuousDischargeCurrent = .nan
                s.mosOverTempProtection = .nan; s.batteryChargeOverTempProtection = .nan; s.batteryDischargeOverTempProtection = .nan
                s.batteryChargeUnderTempProtection = .nan; s.batteryDischargeUnderTempProtection = .nan
            } else {
                s.cellUndervoltageProtection = Double(r.u32(10)) / 1000
                s.cellUndervoltageRecovery = Double(r.u32(14)) / 1000
                s.cellOvervoltageProtection = Double(r.u32(18)) / 1000
                s.cellOvervoltageRecovery = Double(r.u32(22)) / 1000
                s.balanceTriggerVoltage = Double(r.u32(26)) / 1000
                s.continuousChargeCurrent = Double(r.u32(50)) / 1000
                s.continuousDischargeCurrent = Double(r.u32(62)) / 1000
                s.balanceMaxCurrent = Double(r.u32(78)) / 1000
                s.batteryChargeOverTempProtection = Double(r.i32(82)) / 10
                s.batteryDischargeOverTempProtection = Double(r.i32(90)) / 10
                s.batteryChargeUnderTempProtection = Double(r.i32(98)) / 10
                s.mosOverTempProtection = Double(r.i32(106)) / 10
                s.cellCount = Int(r.u32(114)); s.isChargeEnabled = b[118] != 0
                s.isDischargeEnabled = b[122] != 0; s.isBalanceEnabled = b[126] != 0
                s.batteryCapacity = Double(r.u32(130)) / 1000
                s.isHeatingEnabled = variant == .jk02_32s && b[282] & 1 != 0
                s.batteryDischargeUnderTempProtection = variant == .jk02_32s ? Double(Int8(bitPattern: b[296])) : 0
            }
            guard (1...(variant == .jk02_32s ? 32 : 24)).contains(s.cellCount), s.balanceTriggerVoltage.isFinite, s.balanceMaxCurrent.isFinite else { return nil }
            s.extendedValues = JKParameterCatalog.decode(frame: frame, variant: variant)
            return JKDecodedFrame(type: 1, settings: s)
        }
        guard b[4] == 2 else { return nil }
        var s = JKBMSStatus()
        s.ambientTemperature = .nan
        if variant == .jk04 {
            let voltages = (0..<24).map { r.float(6 + $0 * 4) }
            guard voltages.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 6 }) else { return nil }
            let count = (voltages.lastIndex(where: { $0 > 0 }) ?? -1) + 1
            guard count > 0 else { return nil }
            s.cellVoltages = Array(voltages.prefix(count))
            // UI uses milliohm, whereas JK04 frame holds Ohm.
            s.cellWireResistances = (0..<count).map { r.float(102 + $0 * 4) * 1000 }
            s.batteryVoltage = s.cellVoltages.reduce(0, +)
            s.isBalanceEnabled = b[220] != 0; s.balanceCurrent = r.float(222); s.uptimeSeconds = r.u32(286)
            s.batteryCurrent = .nan; s.soc = .nan; s.remainingCapacity = .nan; s.totalCapacity = .nan
            s.totalCycleCapacity = .nan; s.stateOfHealth = .nan
            s.mosTemperature = .nan; s.batteryT1 = .nan; s.batteryT2 = .nan
        } else {
            let slots = variant == .jk02_32s ? 32 : 24
            let offset = variant == .jk02_32s ? 32 : 0
            let voltages = (0..<slots).map { Double(r.u16(6 + $0 * 2)) / 1000 }
            guard voltages.allSatisfy({ $0 <= 6 }) else { return nil }
            let mask = r.u32(54 + (offset / 2))
            let lastEnabled = (0..<slots).last(where: { mask & (UInt32(1) << $0) != 0 })
            let count = max((lastEnabled ?? -1) + 1, (voltages.lastIndex(where: { $0 > 0 }) ?? -1) + 1)
            guard count > 0 else { return nil }
            s.cellVoltages = Array(voltages.prefix(count))
            s.cellWireResistances = (0..<count).map { Double(r.u16(64 + offset / 2 + $0 * 2)) }
            s.batteryVoltage = Double(r.u32(118 + offset)) / 1000
            s.batteryCurrent = Double(r.i32(126 + offset)) / 1000
            s.batteryT1 = Double(r.i16(130 + offset)) / 10; s.batteryT2 = Double(r.i16(132 + offset)) / 10
            s.mosTemperature = Double(r.i16(variant == .jk02_32s ? 144 : 134)) / 10
            s.alarms = JKBMSAlarm.parseModern(from: variant == .jk02_32s ? r.u32(166) : UInt32(r.u16(136)))
            s.balanceCurrent = Double(r.i16(138 + offset)) / 1000
            s.isBalanceEnabled = b[140 + offset] != 0
            s.soc = Double(b[141 + offset]); guard s.soc <= 100 else { return nil }
            s.remainingCapacity = Double(r.u32(142 + offset)) / 1000
            s.totalCapacity = Double(r.u32(146 + offset)) / 1000
            s.hasCycleCount = true
            s.cycleCount = Int(r.u32(150 + offset)); s.totalCycleCapacity = Double(r.u32(154 + offset)) / 1000
            s.stateOfHealth = Double(b[158 + offset]); s.uptimeSeconds = r.u32(162 + offset)
            s.isChargeEnabled = b[166 + offset] != 0; s.isDischargeEnabled = b[167 + offset] != 0
            s.isHeatingEnabled = b[183 + offset] != 0
            s.isEmergencyEnabled = variant == .jk02_32s && r.u16(186 + offset) > 0
            // Original QML marks a sensor valid when its bit is SET (Main.qml onTempMosChanged).
            // The legacy name "tempSensorAbsent" in upstream comments is misleading.
            let absent = r.u16(182 + offset)
            if absent & 1 == 0 { s.mosTemperature = .nan }
            if absent & 2 == 0 { s.batteryT1 = .nan }
            if absent & 4 == 0 { s.batteryT2 = .nan }
            if variant == .jk02_32s {
                s.extraTemperatures = [r.i16(258), r.i16(256), r.i16(254)].enumerated().map { index, value in
                    absent & (UInt16(1) << (index + 3)) == 0 ? .nan : Double(value) / 10
                }
            }
        }
        s.recalculateStats()
        // Packet gives balancing action, not per-cell transfer membership. Do not invent indices.
        return JKDecodedFrame(type: 2, status: s)
    }

    public static func matches(command: JKCommand, status: JKBMSStatus, settings: JKBMSSettings) -> Bool {
        func close(_ a: Double, _ b: Double, tolerance: Double = 0.0006) -> Bool { abs(a - b) <= tolerance }
        switch command {
        case .setOriginalSwitch(_, let key, let bit, let enabled):
            guard let read = settings.originalValues[key], read.isFinite, read >= 0, read <= Double(UInt32.max), (0..<32).contains(bit) else { return false }
            return (UInt32(read) & (1 << bit) != 0) == enabled
        case .setOriginalParameter(_, let key, let value):
            guard let read = settings.originalValues[key] else { return false }
            return abs(read - value) < 0.0006
        case .setParameter(let id, let value): return JKParameterCatalog.matches(id: id, value: value, settings: settings)
        case .setCharge(let v): return settings.isChargeEnabled == v
        case .setDischarge(let v): return settings.isDischargeEnabled == v
        case .setBalance(let v): return settings.isBalanceEnabled == v
        case .setHeating(let v): return settings.isHeatingEnabled == v
        case .setEmergency(let v): return status.isEmergencyEnabled == v
        case .setCellCount(let v): return settings.cellCount == v
        case .setCapacity(let v): return close(settings.batteryCapacity, v)
        case .setBalanceTriggerVoltage(let v): return close(settings.balanceTriggerVoltage, v)
        case .setBalanceMaxCurrent(let v): return close(settings.balanceMaxCurrent, v)
        case .setCellOvervoltageProtection(let v): return close(settings.cellOvervoltageProtection, v)
        case .setCellOvervoltageRecovery(let v): return close(settings.cellOvervoltageRecovery, v)
        case .setCellUndervoltageProtection(let v): return close(settings.cellUndervoltageProtection, v)
        case .setCellUndervoltageRecovery(let v): return close(settings.cellUndervoltageRecovery, v)
        case .setContinuousChargeCurrent(let v): return close(settings.continuousChargeCurrent, v)
        case .setContinuousDischargeCurrent(let v): return close(settings.continuousDischargeCurrent, v)
        case .setMosOverTemperature(let v): return close(settings.mosOverTempProtection, v, tolerance: 0.051)
        case .setChargeOverTemperature(let v): return close(settings.batteryChargeOverTempProtection, v, tolerance: 0.051)
        case .setDischargeOverTemperature(let v): return close(settings.batteryDischargeOverTempProtection, v, tolerance: 0.051)
        case .setChargeUnderTemperature(let v): return close(settings.batteryChargeUnderTempProtection, v, tolerance: 0.051)
        case .setDischargeUnderTemperature(let v): return close(settings.batteryDischargeUnderTempProtection, v, tolerance: 0.51)
        default: return false
        }
    }

    private struct Reader {
        let bytes: [UInt8]
        func u16(_ i: Int) -> UInt16 { UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8 }
        func i16(_ i: Int) -> Int16 { Int16(bitPattern: u16(i)) }
        func u32(_ i: Int) -> UInt32 { UInt32(u16(i)) | UInt32(u16(i + 2)) << 16 }
        func i32(_ i: Int) -> Int32 { Int32(bitPattern: u32(i)) }
        func float(_ i: Int) -> Double { Double(Float(bitPattern: u32(i))) }
        func printable(_ i: Int, _ count: Int) -> Bool { bytes[i..<(i + count)].prefix(while: { $0 != 0 }).allSatisfy { (32...126).contains($0) } }
        func text(_ i: Int, _ count: Int) -> String { String(bytes: bytes[i..<(i + count)].prefix(while: { $0 != 0 }), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
    }
}
