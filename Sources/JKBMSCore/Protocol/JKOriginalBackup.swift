import Foundation

/// The JK configuration backup contains table01 followed by table03,
/// each exactly one complete response frame.
public struct JKOriginalBackup {
    public let family: String
    public let model: String
    public let firmware: String
    public let cellCount: Int
    public let values: [String: Double]
    public let protocolVariant: JKProtocolVariant
    public init(data: Data) throws {
        guard data.count == 600 else { throw JKProtocolError.invalidValue }
        let settings = Data(data.prefix(300)); let info = Data(data.suffix(300))
        guard JKModernCodec.isValid(frame: settings), settings[4] == 1,
              JKModernCodec.isValid(frame: info), info[4] == 3,
              let family = JKOriginalSchema.identify(infoFrame: info) else { throw JKProtocolError.invalidValue }
        self.family = family
        let identity = JKOriginalSchema.decode(info, family: family)
        model = identity.first(where: { $0.id == "manuDeviceID" })?.text ?? ""
        firmware = identity.first(where: { $0.id == "softwareVersion" })?.text ?? ""
        let fields = JKOriginalSchema.decode(settings, family: family)
        let count = fields.first(where: { $0.id == "cellCount" })?.number ?? 0
        guard count.isFinite, (1...32).contains(count) else { throw JKProtocolError.invalidValue }
        cellCount = Int(count)
        let cells = JKOriginalSchema.fields(family: family, type: 2).first(where: { $0.key == "cellVol" })
        protocolVariant = cells?.numeric == "f32" ? .jk04 : (cells?.count == 32 ? .jk02_32s : .jk02_24s)
        var values: [String: Double] = [:]
        for field in fields {
            if let number = field.number, number.isFinite,
               JKOriginalSchema.writableField(key: field.id, family: family) != nil { values["original." + field.id] = number }
        }
        for frame in [settings, info] {
            let extras = JKParameterCatalog.decode(frame: frame, variant: protocolVariant)
            for item in JKParameterCatalog.definitions {
                if let value = extras[item.id] { values[item.id] = value }
            }
        }
        self.values = values
    }
    public var previewObject: [String: Any] {
        ["schemaVersion": 1, "protocol": protocolVariant.rawValue, "deviceModel": model,
         "sourceFirmware": firmware, "sourceFamily": family, "cellCount": cellCount,
         "batteryChemistry": "未指定", "settings": values]
    }
}
