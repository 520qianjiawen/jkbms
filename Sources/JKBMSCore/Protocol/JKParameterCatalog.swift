import Foundation

public struct JKParameterDefinition: Identifiable {
    public let id: String
    public let title: String
    public let group: String
    public let unit: String
    public let step: Double
    public let range: ClosedRange<Double>
    public let isSwitch: Bool
    public var options: [Int: String]? = nil
}

/// Additional read/write fields documented in syssi/esphome-jk-bms (Apache-2.0).
/// Reference: https://github.com/syssi/esphome-jk-bms/tree/main/components/jk_bms_ble
/// A successful BLE write is not a device acknowledgment; compare a fresh readback.
public enum JKParameterCatalog {
    private enum Encoding { case u32, s32, u8, s8, float32, bit(Int) }
    private struct WireField {
        let register: UInt8
        let offset: Int
        var frameType: UInt8 = 1
        var factor: Double = 1
        var length: UInt8 = 4
        var encoding: Encoding = .u32
        var allowedRange: ClosedRange<Double>? = nil
        var capabilityMaskOffset: Int? = nil
    }
    private struct Entry {
        let definition: JKParameterDefinition
        let wireFields: [String: WireField]
    }
    public static var definitions: [JKParameterDefinition] { entries.map(\.definition) }

    private static func common(_ register: UInt8, _ offset: Int, factor: Double = 1,
                               encoding: Encoding = .u32) -> [String: WireField] {
        let field = WireField(register: register, offset: offset, factor: factor, encoding: encoding)
        return [JKProtocolVariant.jk02_24s.rawValue: field, JKProtocolVariant.jk02_32s.rawValue: field]
    }
    private static func modern(_ register: UInt8, _ offset: Int, factor: Double = 1,
                               length: UInt8 = 4, encoding: Encoding = .u32,
                               frameType: UInt8 = 1) -> [String: WireField] {
        [JKProtocolVariant.jk02_32s.rawValue: WireField(register: register, offset: offset, frameType: frameType,
                                                     factor: factor, length: length, encoding: encoding)]
    }
    private static func number(_ id: String, _ title: String, _ group: String, _ unit: String,
                               _ step: Double, _ range: ClosedRange<Double>, _ fields: [String: WireField]) -> Entry {
        Entry(definition: JKParameterDefinition(id: id, title: title, group: group, unit: unit,
                                                step: step, range: range, isSwitch: false), wireFields: fields)
    }
    private static func toggle(_ id: String, _ title: String, _ register: UInt8, _ bit: Int) -> Entry {
        Entry(definition: JKParameterDefinition(id: id, title: title, group: "扩展控制开关", unit: "",
                                                step: 1, range: 0...1, isSwitch: true),
              wireFields: modern(register, bit < 8 ? 282 : 283, encoding: .bit(bit % 8)))
    }
    private static let powerOffFields: [String: WireField] = {
        var fields = common(0x0B, 46, factor: 1000)
        fields[JKProtocolVariant.jk04.rawValue] = WireField(register: 0x20, offset: 38, encoding: .float32, allowedRange: 2...3.7)
        return fields
    }()
    private static let balanceStartFields: [String: WireField] = [
        JKProtocolVariant.jk02_24s.rawValue: WireField(register: 0x26, offset: 138, factor: 1000),
        JKProtocolVariant.jk02_32s.rawValue: WireField(register: 0x22, offset: 138, factor: 1000),
        JKProtocolVariant.jk04.rawValue: WireField(register: 0x58, offset: 98, encoding: .float32, allowedRange: 1...4.2)
    ]
    private static let shortCircuitFields: [String: WireField] = [
        JKProtocolVariant.jk02_24s.rawValue: WireField(register: 0x25, offset: 134),
        JKProtocolVariant.jk02_32s.rawValue: WireField(register: 0x21, offset: 134)
    ]

    private static func choice(_ id: String, _ title: String, _ register: UInt8, _ offset: Int,
                               options: [Int: String], maskOffset: Int? = nil) -> Entry {
        var field = WireField(register: register, offset: offset, frameType: 3, length: 2,
                              encoding: .u8, capabilityMaskOffset: maskOffset)
        if id == "multiplexedPortMode" {
            field = WireField(register: register, offset: offset, encoding: .bit(3))
        }
        return Entry(definition: JKParameterDefinition(id: id, title: title, group: "通信与报警选择", unit: "",
                      step: 1, range: 0...Double(options.keys.max() ?? 0), isSwitch: false, options: options),
                     wireFields: [JKProtocolVariant.jk02_32s.rawValue: field])
    }

    private static let uartOptions: [Int: String] = [
        0: "4G-GPS Remote module Common protocol V4.2",
        1: "JK BMS RS485 Modbus V1.0",
        2: "NIU U SERIES",
        3: "China tower shared battery cabinet V1.1",
        4: "PACE_RS485_Modbus_V1.3",
        5: "PYLON_low_voltage_Protocol_RS485_V3.5",
        6: "Growatt_BMS_RS485_Protocol_1xSxxP_ESS_Rev2.01",
        7: "Voltronic_Inverter_and_BMS_485_communication_protocol_20200325",
        8: "China tower shared battery cabinet V2.0",
        9: "WOW_RS485_Modbus_V1.3",
        10: "JK BMS LCD Protocol V2.0",
        11: "UART1 User customization",
        12: "UART2 User customization",
        13: "(9600) JK BMS RS485 Modbus V1.0",
        14: "(9600) PYLON_low_voltage_Protocol_RS485_V3.5",
        15: "JK BMS PBxx SERIES LCD Protocol V1.0",
        16: "JK BMS LIN BUS V1.0",
        17: "RS485 Protocol 17",
        18: "RS485 Protocol 18",
        19: "RS485 Protocol 19",
        20: "RS485 Protocol 20"
    ]

    private static let canOptions: [Int: String] = [
        0: "JK BMS CAN Protocol (250K) V2.0",
        1: "Deye Low-voltage hybrid inverter CAN communication protocol V1.0",
        2: "PYLON-Low-voltage-V1.2",
        3: "Growatt BMS CAN-Bus-protocol-low-voltage_Rev_05",
        4: "Victron_CANbus_BMS_protocol_20170717",
        5: "MEGAREVO_Hybird_BMSCAN_Protocol_V1.0",
        6: "JK BMS CAN Protocol (500K) V2.0",
        7: "INVT BMS CAN Bus protocol V1.02",
        8: "GoodWe LV BMS Protocol (EX/EM/S-BP/BP)",
        9: "FSS-ConnectingBat-TI-en-10 Version 1.0",
        10: "MUST PV1800F-CAN communication Protocol1.04.04",
        11: "LuxpowerTek Battery CAN protocol V01",
        12: "CAN BUS User customization 1",
        13: "CAN BUS User customization 2"
    ]

    private static let triggerOptions: [Int: String] = [
        0: "关闭",
        1: "低SOC",
        2: "总压过高",
        3: "总压过低",
        4: "单体过压",
        5: "单体欠压",
        6: "充电过流",
        7: "放电过流",
        8: "电池过温",
        9: "MOS过温",
        10: "系统报警",
        11: "电池低温",
        12: "远程控制",
        13: "SOC高于阈值",
        14: "MOS异常"
    ]

    private static let entries: [Entry] = [
        number("soc100Voltage", "SOC 100% 电压", "电压与均衡", "V", 0.001, 0.003...4.35, common(0x07, 30, factor: 1000)),
        number("soc0Voltage", "SOC 0% 电压", "电压与均衡", "V", 0.001, 0.003...4.35, common(0x08, 34, factor: 1000)),
        number("requestedChargeVoltage", "推荐充电电压 RCV", "电压与均衡", "V", 0.001, 0.003...4.35, common(0x09, 38, factor: 1000)),
        number("requestedFloatVoltage", "推荐浮充电压 RFV", "电压与均衡", "V", 0.001, 0.003...4.35, common(0x0A, 42, factor: 1000)),
        number("powerOffVoltage", "自动关机电压", "电压与均衡", "V", 0.01, 1.2...4.35, powerOffFields),
        number("balancingStartVoltage", "均衡起始电压", "电压与均衡", "V", 0.01, 1.2...4.25, balanceStartFields),
        number("requestedChargeHours", "RCV 保持时间", "浮充与休眠", "h", 0.1, 0...18.2, modern(0xB3, 266, factor: 10, length: 1, encoding: .u8, frameType: 3)),
        number("requestedFloatHours", "RFV 保持时间", "浮充与休眠", "h", 0.1, 0...18.2, modern(0xB4, 267, factor: 10, length: 1, encoding: .u8, frameType: 3)),
        number("reBulkSOC", "退出浮充 SOC 差", "浮充与休眠", "%", 1, 0...50, modern(0xB7, 278, length: 1, encoding: .u8, frameType: 3)),
        number("smartSleepHours", "智能休眠时间", "浮充与休眠", "h", 1, 1...100, modern(0x39, 286, length: 1, encoding: .u8)),
        number("chargeOCPDelay", "充电过流保护延时", "保护延时", "s", 1, 2...600, common(0x0D, 54)),
        number("chargeOCPRecovery", "充电过流恢复时间", "保护延时", "s", 1, 2...600, common(0x0E, 58)),
        number("dischargeOCPDelay", "放电过流保护延时", "保护延时", "s", 1, 2...600, common(0x10, 66)),
        number("dischargeOCPRecovery", "放电过流恢复时间", "保护延时", "s", 1, 2...600, common(0x11, 70)),
        number("shortCircuitDelay", "短路保护延时", "保护延时", "μs", 1, 0...1000000, shortCircuitFields),
        number("shortCircuitRecovery", "短路保护恢复时间", "保护延时", "s", 1, 2...600, common(0x12, 74)),
        number("dischargePrechargeTime", "放电预充时间", "保护延时", "s", 1, 0...255, modern(0x25, 274)),
        number("emergencyDuration", "应急启动时长", "保护延时", "min", 1, 1...255, modern(0xB5, 269, length: 1, encoding: .u8, frameType: 3)),
        number("chargeOverTempRecovery", "充电过温恢复", "温度恢复与加热", "°C", 0.1, 0...100, common(0x15, 86, factor: 10)),
        number("dischargeOverTempRecovery", "放电过温恢复", "温度恢复与加热", "°C", 0.1, 0...100, common(0x17, 94, factor: 10)),
        number("chargeUnderTempRecovery", "充电低温恢复", "温度恢复与加热", "°C", 0.1, -45...20, common(0x19, 102, factor: 10, encoding: .s32)),
        number("dischargeUnderTempRecovery", "放电低温恢复", "温度恢复与加热", "°C", 1, -40...100, modern(0x3B, 297, length: 1, encoding: .s8)),
        number("mosOverTempRecovery", "MOS 过温恢复", "温度恢复与加热", "°C", 0.1, 40...120, common(0x1B, 110, factor: 10, encoding: .s32)),
        number("heatingStartTemperature", "加热启动温度", "温度恢复与加热", "°C", 1, -40...100, modern(0x37, 284, length: 1, encoding: .s8)),
        number("heatingStopTemperature", "加热停止温度", "温度恢复与加热", "°C", 1, -40...100, modern(0x38, 285, length: 1, encoding: .s8)),
        toggle("disableTemperatureSensors", "屏蔽温度传感器", 0x28, 1),
        toggle("displayAlwaysOn", "显示屏常亮", 0x2B, 4),
        toggle("smartSleepEnabled", "智能休眠", 0x2D, 6),
        toggle("disablePCLModule", "禁用并联限流模块", 0x2E, 7),
        toggle("timedStoredData", "定时存储数据", 0x2F, 8),
        toggle("chargingFloatMode", "充电浮充模式", 0x30, 9),
        toggle("emergencyButtonTrigger", "按键触发应急", 0x31, 10),
        toggle("dryContactIntermittent", "干接点报警间歇", 0x32, 11),
        toggle("dischargeOCP2", "二级放电过流保护", 0x33, 12),
        toggle("dischargeOCP3", "三级放电过流保护", 0x34, 13),
        toggle("gpsLockedCharging", "GPS 充电锁定", 0x35, 14),
        toggle("gpsLockedDischarging", "GPS 放电锁定", 0x36, 15),
        choice("uart1Protocol", "UART1 协议", 0xA5, 184, options: uartOptions, maskOffset: 186),
        choice("uart2Protocol", "UART2 协议", 0xA8, 218, options: uartOptions, maskOffset: 219),
        choice("uart3Protocol", "UART3 协议", 0xB6, 270, options: uartOptions, maskOffset: 271),
        choice("canProtocol", "CAN 协议", 0xA6, 185, options: canOptions, maskOffset: 202),
        choice("lcdBuzzerTrigger", "显示器报警触发源", 0xA9, 234, options: triggerOptions),
        choice("dry1Trigger", "干接点1触发源", 0xAA, 235, options: triggerOptions),
        choice("dry2Trigger", "干接点2触发源", 0xAB, 236, options: triggerOptions),
        choice("multiplexedPortMode", "复用端口模式", 0x2A, 282, options: [0: "CAN", 1: "RS485"])
    ]

    public static func supports(id: String, variant: JKProtocolVariant) -> Bool {
        entries.contains { $0.definition.id == id && $0.wireFields[variant.rawValue] != nil }
    }
    /// These fields are read from 0x03 rather than the settings frame (0x01).
    public static func readbackNeedsDeviceInfo(id: String) -> Bool {
        entries.first(where: { $0.definition.id == id })?.wireFields[JKProtocolVariant.jk02_32s.rawValue]?.frameType == 3
    }

    public static func encode(id: String, value: Double, variant: JKProtocolVariant) throws -> Data {
        guard let entry = entries.first(where: { $0.definition.id == id }),
              let field = entry.wireFields[variant.rawValue] else { throw JKProtocolError.unsupported }
        guard value.isFinite, entry.definition.range.contains(value),
              field.allowedRange?.contains(value) ?? true,
              !entry.definition.isSwitch || value == 0 || value == 1 else { throw JKProtocolError.invalidValue }
        if let options = entry.definition.options {
            guard value == value.rounded(), options[Int(value)] != nil else { throw JKProtocolError.invalidValue }
        }
        let raw: UInt32
        if case .float32 = field.encoding {
            raw = Float(value).bitPattern
        } else {
            let scaled = value * field.factor
            guard abs(scaled - scaled.rounded()) < 0.00001,
                  scaled >= Double(Int32.min), scaled <= Double(Int32.max),
                  field.length != 1 || (-128...255).contains(scaled) else { throw JKProtocolError.invalidValue }
            raw = UInt32(bitPattern: Int32(scaled.rounded()))
        }
        return JKModernCodec.command(register: field.register, value: raw, length: field.length)
    }

    /// Returns only fields carried by this validated frame. Merge with earlier results.
    public static func decode(frame: Data, variant: JKProtocolVariant) -> [String: Double] {
        guard JKModernCodec.isValid(frame: frame) else { return [:] }
        let bytes = [UInt8](frame.prefix(300))
        var values: [String: Double] = [:]
        for entry in entries {
            guard let field = entry.wireFields[variant.rawValue], bytes[4] == field.frameType else { continue }
            let value: Double
            switch field.encoding {
            case .u8: value = Double(bytes[field.offset]) / field.factor
            case .s8: value = Double(Int8(bitPattern: bytes[field.offset])) / field.factor
            case .bit(let bit): value = bytes[field.offset] & (1 << bit) == 0 ? 0 : 1
            case .u32, .s32, .float32:
                let raw = (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[field.offset + $1]) << (8 * $1) }
                switch field.encoding {
                case .s32: value = Double(Int32(bitPattern: raw)) / field.factor
                case .float32: value = Double(Float(bitPattern: raw))
                default: value = Double(raw) / field.factor
                }
            }
            if value.isFinite, entry.definition.range.contains(value), field.allowedRange?.contains(value) ?? true {
                values[entry.definition.id] = value
                if let maskOffset = field.capabilityMaskOffset {
                    let mask = (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[maskOffset + $1]) << (8 * $1) }
                    values[entry.definition.id + ".enabledMask"] = Double(mask)
                }
            }
        }
        return values
    }


    /// Applies the protocol allow-mask advertised by this board. Unknown protocols are never guessed.
    public static func availableOptions(id: String, settings: JKBMSSettings) -> [Int: String] {
        guard let entry = entries.first(where: { $0.definition.id == id }),
              let options = entry.definition.options else { return [:] }
        let masked = entry.wireFields.values.contains(where: { $0.capabilityMaskOffset != nil })
        guard masked else { return options }
        guard let value = settings.extendedValues[id + ".enabledMask"], value.isFinite,
              value >= 0, value <= Double(UInt32.max) else { return [:] }
        let mask = UInt32(value)
        return options.filter { $0.key < 32 && mask & (1 << $0.key) != 0 }
    }

    public static func isValueAvailable(id: String, value: Double, settings: JKBMSSettings) -> Bool {
        guard let definition = definitions.first(where: { $0.id == id }), value.isFinite else { return false }
        guard definition.options != nil else { return definition.range.contains(value) }
        return value == value.rounded() && availableOptions(id: id, settings: settings)[Int(value)] != nil
    }

    public static func matches(id: String, value: Double, settings: JKBMSSettings) -> Bool {
        guard let actual = settings.extendedValues[id], actual.isFinite, value.isFinite,
              let definition = definitions.first(where: { $0.id == id }) else { return false }
        let tolerance = definition.step < 1 ? definition.step * 0.51 : 0.000001
        return abs(actual - value) <= tolerance
    }
}
