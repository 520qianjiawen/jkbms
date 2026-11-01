import Foundation

public struct JKBMSAlarm: Identifiable, Hashable {
    public enum Severity: String, Hashable {
        case warning
        case critical
    }

    public let id: String
    public let bit: Int
    public let name: String
    public let severity: Severity
    public let timestamp: Date

    public init(bit: Int, name: String, severity: Severity = .warning, timestamp: Date = Date()) {
        self.id = "alarm_\(bit)"
        self.bit = bit
        self.name = name
        self.severity = severity
        self.timestamp = timestamp
    }

    public static func parseAlarms(from bitmask: UInt32) -> [JKBMSAlarm] {
        var alarms: [JKBMSAlarm] = []

        let definitions: [(bit: Int, name: String, critical: Bool)] = [
            (0, "低容量报警 (Low Capacity)", false),
            (1, "MOS管过温保护 (MOS Over-temperature)", true),
            (2, "充电过压保护 (Charge Over-voltage)", true),
            (3, "放电欠压保护 (Discharge Under-voltage)", true),
            (4, "电池过温保护 (Battery Over-temperature)", true),
            (5, "充电过流保护 (Charge Over-current)", true),
            (6, "放电过流保护 (Discharge Over-current)", true),
            (7, "单体压差过大 (Cell Delta V Abnormal)", false),
            (8, "电池箱过温保护 (Box Over-temperature)", true),
            (9, "电池低温保护 (Battery Under-temperature)", true),
            (10, "单体电芯过压保护 (Cell Over-voltage)", true),
            (11, "单体电芯欠压保护 (Cell Under-voltage)", true),
            (12, "保护板309A保护 (Hardware 309A Protection)", true),
            (13, "保护板309B保护 (Hardware 309B Protection)", true),
            (14, "保留告警位14", false),
            (15, "保留告警位15", false)
        ]

        for def in definitions {
            if (bitmask & (1 << def.bit)) != 0 {
                alarms.append(JKBMSAlarm(
                    bit: def.bit,
                    name: def.name,
                    severity: def.critical ? .critical : .warning
                ))
            }
        }

        return alarms
    }
}

extension JKBMSAlarm {
    /// JK02 bit positions differ from the legacy 4E57 protocol.
    public static func parseModern(from mask: UInt32) -> [JKBMSAlarm] {
        let names = ["均衡采样线电阻异常", "MOS过温保护", "电芯串数与设置不符", "未定义告警位3", "电池已充满", "电池包过压", "充电过流", "充电短路", "充电过温", "充电低温", "协处理器通信异常", "电芯欠压", "电池包欠压", "放电过流", "放电短路", "放电过温", "充电MOS异常", "放电MOS异常", "GPS断开", "请及时修改密码", "放电开启失败", "电池过温", "温度传感器异常", "PL模块异常", "短路保护释放失败", "二级放电过流", "三级放电过流", "放电低温", "GPS远程锁定", "未定义告警位29", "未定义告警位30", "未定义告警位31"]
        return (0..<32).compactMap { bit in
            guard mask & (UInt32(1) << bit) != 0 else { return nil }
            return JKBMSAlarm(bit: bit, name: names[bit], severity: [0, 4, 18, 19, 29, 30, 31].contains(bit) ? .warning : .critical)
        }
    }
}
