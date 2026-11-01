import Foundation

public struct JKOriginalField: Decodable, Identifiable {
    public let key: String
    public let title: String
    public let kind: String
    public let numeric: String
    public let offset: Int
    public let size: Int
    public let count: Int
    public let scale: Double
    public let unit: String
    public let decimals: Int
    public let command: Int
    public let minimum: Double?
    public let maximum: Double?
    public let options: [String: String]?
    public let children: [JKOriginalField]?
    public var id: String { key }
    public var isPrivate: Bool { ["bluetoothPwd", "settingPassword"].contains(key) }
}

public struct JKOriginalValue: Identifiable {
    public let field: JKOriginalField
    public let numbers: [Double]
    public let text: String?
    public let bytes: [UInt8]
    public var id: String { field.key }
    public var number: Double? { numbers.first }
    public var display: String {
        if let text { return text.isEmpty ? "—" : text }
        if !numbers.isEmpty {
            return numbers.map { value in
                guard value.isFinite else { return "—" }
                if let option = field.options?[String(Int(value))], field.kind != "bm" { return option }
                return String(format: "%.*f", min(field.decimals, 6), value)
            }.joined(separator: numbers.count > 1 ? " / " : "") + (field.unit.isEmpty ? "" : " " + field.unit)
        }
        return bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

/// Layouts recovered from the user-supplied original iOS app's protocore v4.13.1.
/// Defaults are intentionally omitted. Every value comes from a validated frame.
public enum JKOriginalSchema {
    private static let layouts: [String: [String: [JKOriginalField]]] = load("layouts") ?? [:]
    private struct Product: Decodable { let name: String; let count: Int; let beta: Bool? }
    private static let products: [String: [Product]] = load("devices") ?? [:]
    private static func load<T: Decodable>(_ name: String) -> T? {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "original"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    public static var deviceModels: [DeviceCatalog.DeviceModelItem] {
        var seen = Set<String>()
        return products.keys.sorted().flatMap { family in
            (products[family] ?? []).compactMap { product in
                guard seen.insert(family + "/" + product.name).inserted else { return nil }
                return DeviceCatalog.DeviceModelItem(name: product.name, count: product.count, series: family, isBeta: product.beta ?? false)
            }
        }
    }
    public static var families: [String] { layouts.keys.sorted() }
    public static func fields(family: String, type: UInt8) -> [JKOriginalField] {
        layouts[family]?[String(format: "%02X", type)] ?? []
    }
    public static func identify(infoFrame: Data) -> String? {
        guard JKModernCodec.isValid(frame: infoFrame), infoFrame[4] == 3 else { return nil }
        let b = [UInt8](infoFrame)
        // V2 adds maxCells in the last byte of the old 16-byte model field.
        if b[298] != 0, (1...32).contains(Int(b[21])) { return "JK-BXAXS-XP" }
        let model = String(bytes: b[6..<22].prefix(while: { $0 != 0 }), encoding: .ascii) ?? ""
        if layouts[model] != nil { return model }
        let matches = products.filter { _, values in values.contains(where: { $0.name == model }) }.map(\.key)
        return matches.count == 1 ? matches.first : nil
    }
    public static func decode(_ frame: Data, family: String) -> [JKOriginalValue] {
        guard JKModernCodec.isValid(frame: frame) else { return [] }
        let b = [UInt8](frame.prefix(300))
        return fields(family: family, type: b[4]).compactMap { field in
            guard field.offset >= 6, field.size >= 1, field.offset + field.size <= 300 else { return nil }
            let bytes = Array(b[field.offset..<(field.offset + field.size)])
            if field.kind == "a" && field.numeric == "i8" {
                let text = String(bytes: bytes.prefix(while: { $0 != 0 }), encoding: .utf8)
                return JKOriginalValue(field: field, numbers: [], text: text, bytes: bytes)
            }
            if field.kind == "cx" { return JKOriginalValue(field: field, numbers: [], text: nil, bytes: bytes) }
            let width = byteWidth(field.numeric)
            guard width > 0 else { return nil }
            let count = field.kind == "a" ? field.count : 1
            guard count * width <= bytes.count else { return nil }
            let values = (0..<count).map { index in numeric(Array(bytes[index * width..<(index + 1) * width]), type: field.numeric) * field.scale }
            return JKOriginalValue(field: field, numbers: values, text: nil, bytes: bytes)
        }
    }
    public static func byteWidth(_ type: String) -> Int {
        switch type { case "u8", "i8": return 1; case "u16", "i16": return 2
        case "u32", "i32", "f32": return 4; case "u64", "i64", "f64": return 8; default: return 0 }
    }
    static func numeric(_ bytes: [UInt8], type: String) -> Double {
        let raw = bytes.enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << ($1.offset * 8) }
        switch type {
        case "i8": return Double(Int8(bitPattern: UInt8(truncatingIfNeeded: raw)))
        case "i16": return Double(Int16(bitPattern: UInt16(truncatingIfNeeded: raw)))
        case "i32": return Double(Int32(bitPattern: UInt32(truncatingIfNeeded: raw)))
        case "i64": return Double(Int64(bitPattern: raw))
        case "f32": return Double(Float(bitPattern: UInt32(truncatingIfNeeded: raw)))
        case "f64": return Double(bitPattern: raw)
        default: return Double(raw)
        }
    }
    public static func writableField(key: String, family: String) -> JKOriginalField? {
        guard let field = fields(family: family, type: 4).first(where: { $0.key == key }),
              (field.kind == "n" && field.minimum != nil && field.maximum != nil || field.kind == "bv"), field.size <= 4 else { return nil }
        return field
    }
    public static func encode(key: String, value: Double, family: String) throws -> Data {
        guard let field = writableField(key: key, family: family), value.isFinite,
              (field.minimum ?? 0)...(key == "cellCount" && family == "JK-BXAXS-XP" ? 32 : (field.maximum ?? 1)) ~= value,
              field.scale > 0, (1...255).contains(field.command) else { throw JKProtocolError.invalidValue }
        let scaled = value / field.scale
        let raw: UInt32
        if field.numeric == "f32" { raw = Float(value).bitPattern }
        else {
            guard scaled >= Double(Int32.min), scaled <= Double(UInt32.max),
                  abs(scaled - scaled.rounded()) < 0.0001 else { throw JKProtocolError.invalidValue }
            raw = scaled < 0 ? UInt32(bitPattern: Int32(scaled.rounded())) : UInt32(scaled.rounded())
        }
        // Original Transfer.setValue numeric uses the field index and its native payload size.
        return JKModernCodec.command(register: UInt8(field.command), value: raw, length: UInt8(field.size))
    }

    public static func detailedLogs(_ frame: Data, family: String) -> [JKDetailedLogRecord]? {
        guard JKModernCodec.isValid(frame: frame), frame[4] == 6,
              let field = fields(family: family, type: 6).first(where: { $0.key == "record1" }),
              let children = field.children, field.size > 0 else { return nil }
        let bytes = [UInt8](frame)
        let begin = Int(bytes[6]) | Int(bytes[7]) << 8
        let count = Int(bytes[8])
        guard count <= 12, field.offset + field.size * count <= 299 else { return nil }
        return (0..<count).map { index in
            let values = children.compactMap { child -> JKOriginalValue? in
                let offset = child.offset + index * field.size
                guard offset + child.size <= 299 else { return nil }
                let raw = Array(bytes[offset..<(offset + child.size)])
                let number = numeric(raw, type: child.numeric) * child.scale
                return JKOriginalValue(field: child, numbers: [number], text: nil, bytes: raw)
            }
            return JKDetailedLogRecord(index: begin + index, values: values)
        }
    }

    public static func encodeSwitch(key: String, bit: Int, enabled: Bool, family: String) throws -> Data {
        guard let field = fields(family: family, type: 4).first(where: { $0.key == key && $0.kind == "bm" }),
              bit >= 0, bit < field.count, field.options?[String(bit)] != nil,
              field.command + bit <= 255 else { throw JKProtocolError.unsupported }
        return JKModernCodec.command(register: UInt8(field.command + bit), value: enabled ? 1 : 0, length: 4)
    }

    public static func bitEnabled(_ bytes: [UInt8], index: Int) -> Bool {
        index >= 0 && index / 8 < bytes.count && bytes[index / 8] & (1 << (index % 8)) != 0
    }
}
