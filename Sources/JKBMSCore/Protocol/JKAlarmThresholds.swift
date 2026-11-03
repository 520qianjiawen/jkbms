import Foundation

/// Wire values remain integers in the units specified by JK's alarm table.
/// https://www.shop.jkbms.com/jk-bms-dry-contact-wiring-method-diagrams/
/// The original device-info layout supplies the six signed i32 fields below.
public enum JKAlarmThresholds {
    public struct Channel: Identifiable {
        public let id: String
        public let title: String
        public let triggerID: String
        public let releaseID: String
        public let triggerRegister: UInt8
        public let offset: Int
        public let visibleIndex: Int
    }
    public struct Rule {
        public let unit: String
        public let range: ClosedRange<Double>
        public let triggersBelow: Bool
        public var relationship: String { triggersBelow ? "触发值必须小于恢复值" : "触发值必须大于恢复值" }
        public func accepts(trigger: Double, release: Double) -> Bool {
            contains(trigger) && contains(release) && (triggersBelow ? trigger < release : trigger > release)
        }
        public func contains(_ value: Double) -> Bool {
            value.isFinite && value == value.rounded() && range.contains(value)
        }
    }
    public static let channels: [Channel] = [
        Channel(id: "lcdBuzzerTrigger", title: "显示器报警", triggerID: "lcdBuzzerTriggerVal", releaseID: "lcdBuzzerReleaseVal", triggerRegister: 0xAC, offset: 238, visibleIndex: 25),
        Channel(id: "dry1Trigger", title: "干接点1", triggerID: "dry1TriggerVal", releaseID: "dry1ReleaseVal", triggerRegister: 0xAE, offset: 246, visibleIndex: 27),
        Channel(id: "dry2Trigger", title: "干接点2", triggerID: "dry2TriggerVal", releaseID: "dry2ReleaseVal", triggerRegister: 0xB0, offset: 254, visibleIndex: 29)
    ]
    public static func channel(for id: String) -> Channel? {
        channels.first { $0.id == id || $0.triggerID == id || $0.releaseID == id }
    }
    public static func isThreshold(_ id: String) -> Bool { channel(for: id).map { $0.id != id } ?? false }
    public static func source(for id: String, settings: JKBMSSettings) -> Int? {
        guard let channel = channel(for: id), let value = settings.extendedValues[channel.id],
              value.isFinite else { return nil }
        return Int(exactly: value)
    }
    public static func rule(source: Int) -> Rule? {
        switch source {
        case 1: return Rule(unit: "%", range: 0...99, triggersBelow: true)
        case 2, 3: return Rule(unit: "mV", range: 0...105000, triggersBelow: source == 3)
        case 4, 5: return Rule(unit: "mV", range: 0...5000, triggersBelow: source == 5)
        case 6, 7: return Rule(unit: "mA", range: 0...1000000, triggersBelow: false)
        case 8, 9, 11: return Rule(unit: "℃", range: -50...150, triggersBelow: source == 11)
        // Original selector 13 is Above SoC. This conservative app policy uses
        // the documented SOC integer domain (0...99), with high-trigger hysteresis.
        // It is not a declaration of every firmware's accepted bounds or comparator.
        case 13: return Rule(unit: "%", range: 0...99, triggersBelow: false)
        default: return nil
        }
    }
    public static func rule(id: String, settings: JKBMSSettings) -> Rule? {
        source(for: id, settings: settings).flatMap { rule(source: $0) }
    }
    public static func register(id: String) -> UInt8? {
        guard isThreshold(id), let channel = channel(for: id) else { return nil }
        return channel.triggerRegister + (id == channel.releaseID ? 1 : 0)
    }
    public static func definition(id: String, settings: JKBMSSettings) -> JKParameterDefinition? {
        guard isThreshold(id), let channel = channel(for: id), let rule = rule(id: id, settings: settings) else { return nil }
        return JKParameterDefinition(id: id, title: channel.title + (id == channel.triggerID ? "触发值" : "恢复值"),
            group: "通信与报警选择", unit: rule.unit, step: 1, range: rule.range, isSwitch: false)
    }
    /// An out-of-range peer may be repaired; a missing peer blocks writes.
    public static func isValueAvailable(id: String, value: Double, settings: JKBMSSettings) -> Bool {
        guard isThreshold(id), let channel = channel(for: id), let rule = rule(id: id, settings: settings),
              rule.contains(value), settings.extendedValues[id] != nil else { return false }
        let peerID = id == channel.triggerID ? channel.releaseID : channel.triggerID
        guard let peer = settings.extendedValues[peerID] else { return false }
        if !rule.contains(peer) { return true }
        return rule.accepts(trigger: id == channel.triggerID ? value : peer,
                            release: id == channel.releaseID ? value : peer)
    }
    /// Threshold backups must identify their unit context. Changing the source is
    /// a separate readback step so stale raw numbers never acquire another unit.
    public static func importUpdates(_ values: [String: Double], settings: JKBMSSettings) throws -> [(String, Double)] {
        let updates = values.filter { isThreshold($0.key) }
        var final = settings
        for (id, value) in updates {
            guard let channel = channel(for: id),
                  let source = values[channel.id], source == settings.extendedValues[channel.id] else { throw JKProtocolError.invalidValue }
            final.extendedValues[id] = value
        }
        for (id, value) in updates {
            guard isValueAvailable(id: id, value: value, settings: final) else { throw JKProtocolError.invalidValue }
        }
        var remaining = updates.filter { settings.extendedValues[$0.key] != $0.value }
        var projected = settings
        var ordered: [(String, Double)] = []
        while !remaining.isEmpty {
            guard let id = remaining.keys.sorted().first(where: { isValueAvailable(id: $0, value: remaining[$0]!, settings: projected) }),
                  let value = remaining.removeValue(forKey: id) else { throw JKProtocolError.invalidValue }
            ordered.append((id, value)); projected.extendedValues[id] = value
        }
        return ordered
    }
    public static func encode(id: String, value: Double, variant: JKProtocolVariant, settings: JKBMSSettings?) throws -> Data {
        guard variant == .jk02_32s, let register = register(id: id) else { throw JKProtocolError.unsupported }
        guard let settings, isValueAvailable(id: id, value: value, settings: settings) else { throw JKProtocolError.invalidValue }
        return JKModernCodec.command(register: register, value: UInt32(bitPattern: Int32(value)), length: 4)
    }
    public static func decode(frame: Data, variant: JKProtocolVariant) -> [String: Double] {
        guard variant == .jk02_32s, JKModernCodec.isValid(frame: frame), frame[4] == 3 else { return [:] }
        var values: [String: Double] = [:]
        for channel in channels {
            for (id, offset) in [(channel.triggerID, channel.offset), (channel.releaseID, channel.offset + 4)] {
                let raw = (0..<4).reduce(UInt32(0)) { $0 | UInt32(frame[offset + $1]) << (8 * $1) }
                values[id] = Double(Int32(bitPattern: raw))
            }
        }
        return values
    }
}
