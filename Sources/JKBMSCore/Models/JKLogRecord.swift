import Foundation

/// Device event time is uptime seconds, not a Unix timestamp.
public struct JKLogRecord: Identifiable, Hashable {
    public let index: Int
    public let uptime: UInt32
    public let code: UInt8
    public var id: String { "\(index)-\(uptime)-\(code)" }
    public var uptimeDescription: String {
        String(format: "%u天 %02u:%02u:%02u", uptime / 86400, (uptime % 86400) / 3600, (uptime % 3600) / 60, uptime % 60)
    }
    public var event: String {
        switch code {
        case 0x01: return "开机"
        case 0x02: return "关机"
        case 0x03: return "App关闭充电"
        case 0x04: return "App开启充电"
        case 0x05: return "App关闭放电"
        case 0x06: return "App开启放电"
        case 0x07: return "远程关闭充电"
        case 0x08: return "远程开启充电"
        case 0x09: return "远程关闭放电"
        case 0x0A: return "远程开启放电"
        case 0x0B: return "MOS过温保护"
        case 0x0C: return "MOS过温保护解除"
        case 0x0D: return "电流传感器异常"
        case 0x0E: return "电流传感器恢复"
        case 0x0F: return "协处理器通信异常"
        case 0x10: return "协处理器通信恢复"
        case 0x11: return "单体过压保护"
        case 0x12: return "单体过压保护解除"
        case 0x13: return "电池过压保护"
        case 0x14: return "电池过压保护解除"
        case 0x15: return "充电过流保护"
        case 0x16: return "充电过流保护解除"
        case 0x17: return "充电短路保护"
        case 0x18: return "充电短路保护解除"
        case 0x19: return "充电过温保护"
        case 0x1A: return "充电过温保护解除"
        case 0x1B: return "充电低温保护"
        case 0x1C: return "充电低温保护解除"
        case 0x1D: return "单体欠压保护"
        case 0x1E: return "单体欠压保护解除"
        case 0x1F: return "电池欠压保护"
        case 0x20: return "电池欠压保护解除"
        case 0x21: return "放电过流保护"
        case 0x22: return "放电过流保护解除"
        case 0x23: return "放电短路保护"
        case 0x24: return "放电短路保护解除"
        case 0x25: return "放电过温保护"
        case 0x26: return "放电过温保护解除"
        case 0x27: return "看门狗复位"
        case 0x28: return "放电二级短路保护"
        case 0x29: return "手动开启应急"
        case 0x2A: return "手动关闭应急"
        case 0x2B: return "应急自动结束"
        case 0x2C: return "App关机"
        case 0x2D: return "按键关机"
        case 0x2E: return "放电开启失败"
        case 0x2F: return "RS485关机"
        case 0x30...0x37: return "CAN/RS485充放电控制"
        case 0x38: return "进入休眠"
        case 0x39: return "充电MOS异常"
        case 0x3A: return "放电MOS异常"
        case 0x3B: return "时间校准"
        case 0x3C: return "电芯串数不正确"
        case 0x3D: return "按键开启应急"
        case 0x3E: return "按键关闭应急"
        case 0x3F: return "按键强制加热"
        case 0x40: return "放电二级过流保护"
        case 0x41: return "放电三级过流保护"
        case 0x42: return "短路保护解除失败"
        case 0x43: return "应用三元锂预设"
        case 0x44: return "应用磷酸铁锂预设"
        case 0x45: return "应用钛酸锂预设"
        case 0x46: return "远程开启应急"
        case 0x47: return "远程关闭应急"
        case 0x48: return "放电低温保护"
        case 0x49: return "放电低温保护解除"
        case 0x64...0x83: return "单体\(Int(code) - 0x63)过压保护"
        default: return String(format: "设备事件 0x%02X", code)
        }
    }
}

public enum JKLogbookCodec {
    // syssi/esphome-jk-bms jk_bms_ble.cpp::decode_logbook_: type5, count at6, entries at11, 5B each.
    public static func decode(_ frame: Data) -> [JKLogRecord]? {
        guard JKModernCodec.isValid(frame: frame) else { return nil }
        let bytes = [UInt8](frame.prefix(300))
        guard bytes[4] == 5 else { return nil }
        func u32(_ index: Int) -> UInt32 {
            (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[index + $1]) << (8 * $1) }
        }
        let count = min(Int(u32(6)), 50)
        return (0..<count).map { index in
            JKLogRecord(index: index + 1, uptime: u32(11 + index * 5), code: bytes[15 + index * 5])
        }
    }
}
