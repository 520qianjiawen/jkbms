import Foundation

public struct DeviceCatalog {
    public struct DeviceModelItem: Identifiable, Hashable {
        public var id: String { series + "/" + name }
        public let name: String
        public let count: Int
        public let series: String
        public let isBeta: Bool

        public init(name: String, count: Int, series: String, isBeta: Bool = false) {
            self.name = name
            self.count = count
            self.series = series
            self.isBeta = isBeta
        }
    }

    public static let supportedSeries: [String] = [
        "JK-B1A24S",
        "JK-B1A24S-P",
        "JK-B1A32S-P",
        "JK-DZ08-B1A24S",
        "JK-B1A24S-PLW",
        "JK-B1A24S-PSR",
        "JK-BXAXS-XP"
    ]

    /// Complete model directory recovered from the original app; catalog membership is not runtime verification.
    public static var defaultModels: [DeviceModelItem] { JKOriginalSchema.deviceModels }
}
