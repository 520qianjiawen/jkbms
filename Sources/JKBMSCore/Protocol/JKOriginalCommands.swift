import Foundation

public enum JKDeviceTextKind: String, CaseIterable, Identifiable {
    case name, bluetoothPassword, settingsPassword, userData, userData2
    public var id: String { rawValue }
    public var title: String {
        switch self { case .name: return "蓝牙名称"; case .bluetoothPassword: return "蓝牙连接密码"
        case .settingsPassword: return "参数设置密码"; case .userData: return "用户数据"; case .userData2: return "用户数据2" }
    }
    public var key: String {
        switch self { case .name: return "bluetoothName"; case .bluetoothPassword: return "bluetoothPwd"
        case .settingsPassword: return "settingPassword"; case .userData: return "userData"; case .userData2: return "userData2" }
    }
    public var register: UInt8 {
        switch self { case .name: return 0x9B; case .bluetoothPassword: return 0x9C
        case .settingsPassword: return 0xA0; case .userData: return 0x9F; case .userData2: return 0xA2 }
    }
    public var isPassword: Bool { self == .bluetoothPassword || self == .settingsPassword }
}

public enum JKOriginalCommands {
    /// Original global schema: AA5590EB, command, validSize, 13 data bytes, sum8.
    /// Original setName/setPassword wrappers pass QString.length, maxLength=12 in QML.
    /// Restrict to printable ASCII so Qt UTF-8/Latin-1 character counts agree exactly.
    public static func text(_ value: String, kind: JKDeviceTextKind) throws -> Data {
        let bytes = Array(value.utf8)
        guard !bytes.isEmpty, bytes.count <= 12, bytes.allSatisfy({ (0x20...0x7E).contains($0) }) else { throw JKProtocolError.invalidValue }
        var packet = [UInt8](repeating: 0, count: 20)
        packet.replaceSubrange(0..<4, with: [0xAA, 0x55, 0x90, 0xEB])
        packet[4] = kind.register; packet[5] = UInt8(bytes.count)
        packet.replaceSubrange(6..<(6 + bytes.count), with: bytes)
        packet[19] = packet.prefix(19).reduce(0, &+)
        return Data(packet)
    }
    // Device RTC uses UTC seconds since 2020-01-01T00:00:00Z, with a four-byte payload.
    public static func timeCalibration(date: Date) throws -> Data {
        let seconds = date.timeIntervalSince1970 - 1577836800
        guard seconds >= 0, seconds < Double(UInt32.max) else { throw JKProtocolError.invalidValue }
        return JKModernCodec.command(register: 0x6C, value: UInt32(seconds), length: 4)
    }
}

public struct JKDetailedLogRecord: Identifiable {
    public let index: Int
    public let values: [JKOriginalValue]
    public var id: Int { index }
    public var date: Date? {
        guard let seconds = values.first(where: { $0.id == "rtcCount" })?.number, seconds.isFinite else { return nil }
        return Date(timeIntervalSince1970: 1577836800 + seconds)
    }
    public var event: String {
        let code = values.first(where: { $0.id == "logCode" })?.number ?? 0
        return JKLogRecord(index: index, uptime: 0, code: UInt8(clamping: Int(code))).event
    }
}
