import Foundation

public struct JKBMSStatus: Hashable {
    // Cell voltages (in Volts)
    public var cellVoltages: [Double]
    public var cellCount: Int

    // Wire resistances (in mΩ or Ω)
    public var cellWireResistances: [Double]

    // Key statistics computed from cellVoltages
    public var minCellIndex: Int // 0-based
    public var minCellVoltage: Double
    public var maxCellIndex: Int // 0-based
    public var maxCellVoltage: Double
    public var deltaVoltage: Double
    public var averageVoltage: Double
    public var balancingCellIndices: Set<Int> // 0-based

    // Battery pack status
    public var batteryVoltage: Double // V
    public var batteryCurrent: Double // A (+ = charge, - = discharge)
    public var batteryPower: Double // W
    public var soc: Double // State of Charge (0..100 %)
    public var remainingCapacity: Double // Ah
    public var totalCapacity: Double // Ah
    public var hasCycleCount: Bool = false
    public var cycleCount: Int
    public var totalCycleCapacity: Double // Ah

    // Temperatures (°C)
    public var mosTemperature: Double
    public var batteryT1: Double
    public var batteryT2: Double
    public var ambientTemperature: Double

    // MOS & switches
    public var isChargeEnabled: Bool
    public var isDischargeEnabled: Bool
    public var isBalanceEnabled: Bool
    public var isHeatingEnabled: Bool

    public var isEmergencyEnabled: Bool = false
    public var balanceCurrent: Double = 0
    public var stateOfHealth: Double = 0
    public var extraTemperatures: [Double] = []

    // Active alarms & protections
    public var alarms: [JKBMSAlarm]

    // Device metadata
    public var deviceModel: String
    public var hardwareVersion: String
    public var firmwareVersion: String
    public var deviceSN: String
    public var uptimeSeconds: UInt32
    public var manufactureDate: String

    public init(
        cellVoltages: [Double] = [],
        cellWireResistances: [Double] = [],
        balancingCellIndices: Set<Int> = [],
        batteryVoltage: Double = 0,
        batteryCurrent: Double = 0.0,
        soc: Double = 0,
        remainingCapacity: Double = 0,
        totalCapacity: Double = 0,
        cycleCount: Int = 0,
        totalCycleCapacity: Double = 0,
        mosTemperature: Double = 0,
        batteryT1: Double = 0,
        batteryT2: Double = 0,
        ambientTemperature: Double = 0,
        isChargeEnabled: Bool = false,
        isDischargeEnabled: Bool = false,
        isBalanceEnabled: Bool = false,
        isHeatingEnabled: Bool = false,
        alarms: [JKBMSAlarm] = [],
        deviceModel: String = "",
        hardwareVersion: String = "",
        firmwareVersion: String = "",
        deviceSN: String = "",
        uptimeSeconds: UInt32 = 0,
        manufactureDate: String = ""
    ) {
        self.cellVoltages = cellVoltages
        self.cellCount = cellVoltages.count
        self.cellWireResistances = cellWireResistances
        self.balancingCellIndices = balancingCellIndices

        if !cellVoltages.isEmpty {
            let minIndex = cellVoltages.indices.min(by: { cellVoltages[$0] < cellVoltages[$1] }) ?? 0
            let maxIndex = cellVoltages.indices.max(by: { cellVoltages[$0] < cellVoltages[$1] }) ?? 0
            self.minCellIndex = minIndex
            self.minCellVoltage = cellVoltages[minIndex]
            self.maxCellIndex = maxIndex
            self.maxCellVoltage = cellVoltages[maxIndex]
            self.deltaVoltage = cellVoltages[maxIndex] - cellVoltages[minIndex]
            let sum = cellVoltages.reduce(0.0, +)
            self.averageVoltage = sum / Double(cellVoltages.count)
        } else {
            self.minCellIndex = 0
            self.minCellVoltage = 0.0
            self.maxCellIndex = 0
            self.maxCellVoltage = 0.0
            self.deltaVoltage = 0.0
            self.averageVoltage = 0.0
        }

        self.batteryVoltage = batteryVoltage
        self.batteryCurrent = batteryCurrent
        self.batteryPower = batteryVoltage * abs(batteryCurrent)
        self.soc = soc
        self.remainingCapacity = remainingCapacity
        self.totalCapacity = totalCapacity
        self.cycleCount = cycleCount
        self.totalCycleCapacity = totalCycleCapacity

        self.mosTemperature = mosTemperature
        self.batteryT1 = batteryT1
        self.batteryT2 = batteryT2
        self.ambientTemperature = ambientTemperature

        self.isChargeEnabled = isChargeEnabled
        self.isDischargeEnabled = isDischargeEnabled
        self.isBalanceEnabled = isBalanceEnabled
        self.isHeatingEnabled = isHeatingEnabled
        self.alarms = alarms

        self.deviceModel = deviceModel
        self.hardwareVersion = hardwareVersion
        self.firmwareVersion = firmwareVersion
        self.deviceSN = deviceSN
        self.uptimeSeconds = uptimeSeconds
        self.manufactureDate = manufactureDate
    }

    /// Re-compute statistics after manual update
    public mutating func recalculateStats() {
        self.cellCount = cellVoltages.count
        if !cellVoltages.isEmpty {
            let minIndex = cellVoltages.indices.min(by: { cellVoltages[$0] < cellVoltages[$1] }) ?? 0
            let maxIndex = cellVoltages.indices.max(by: { cellVoltages[$0] < cellVoltages[$1] }) ?? 0
            self.minCellIndex = minIndex
            self.minCellVoltage = cellVoltages[minIndex]
            self.maxCellIndex = maxIndex
            self.maxCellVoltage = cellVoltages[maxIndex]
            self.deltaVoltage = cellVoltages[maxIndex] - cellVoltages[minIndex]
            let sum = cellVoltages.reduce(0.0, +)
            self.averageVoltage = sum / Double(cellVoltages.count)
        }
        else {
            minCellIndex = 0; maxCellIndex = 0
            minCellVoltage = 0; maxCellVoltage = 0
            deltaVoltage = 0; averageVoltage = 0
        }
        self.batteryPower = batteryVoltage * abs(batteryCurrent)
    }
}
