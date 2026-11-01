import Foundation

public struct JKDevice: Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var rssi: Int
    public var isConnected: Bool
    public var lastSeen: Date
    public var isSimulator: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        rssi: Int = -60,
        isConnected: Bool = false,
        lastSeen: Date = Date(),
        isSimulator: Bool = false
    ) {
        self.id = id
        self.name = name
        self.rssi = rssi
        self.isConnected = isConnected
        self.lastSeen = lastSeen
        self.isSimulator = isSimulator
    }
}
