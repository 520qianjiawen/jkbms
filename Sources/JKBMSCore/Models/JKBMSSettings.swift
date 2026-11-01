import Foundation

public struct JKBMSSettings: Hashable {
    public var originalValues: [String: Double] = [:]
    public var extendedValues: [String: Double] = [:]
    public var cellCount: Int
    public var batteryCapacity: Double // Ah
    public var balanceTriggerVoltage: Double // V (e.g. 0.005)
    public var balanceMaxCurrent: Double // A (e.g. 1.0 or 2.0)
    public var cellOvervoltageProtection: Double // V
    public var cellOvervoltageRecovery: Double // V
    public var cellUndervoltageProtection: Double // V
    public var cellUndervoltageRecovery: Double // V
    public var continuousChargeCurrent: Double // A
    public var continuousDischargeCurrent: Double // A
    public var mosOverTempProtection: Double // °C
    public var batteryChargeOverTempProtection: Double // °C
    public var batteryDischargeOverTempProtection: Double // °C
    public var batteryChargeUnderTempProtection: Double // °C
    public var batteryDischargeUnderTempProtection: Double // °C
    public var isChargeEnabled: Bool = false
    public var isDischargeEnabled: Bool = false
    public var isBalanceEnabled: Bool = false
    public var isHeatingEnabled: Bool = false
    public var password: String

    public init(
        cellCount: Int = 16,
        batteryCapacity: Double = 100.0,
        balanceTriggerVoltage: Double = 0.005,
        balanceMaxCurrent: Double = 1.0,
        cellOvervoltageProtection: Double = 3.65,
        cellOvervoltageRecovery: Double = 3.45,
        cellUndervoltageProtection: Double = 2.50,
        cellUndervoltageRecovery: Double = 2.65,
        continuousChargeCurrent: Double = 50.0,
        continuousDischargeCurrent: Double = 100.0,
        mosOverTempProtection: Double = 85.0,
        batteryChargeOverTempProtection: Double = 60.0,
        batteryDischargeOverTempProtection: Double = 65.0,
        batteryChargeUnderTempProtection: Double = 0.0,
        batteryDischargeUnderTempProtection: Double = -10.0,
        password: String = ""
    ) {
        self.cellCount = cellCount
        self.batteryCapacity = batteryCapacity
        self.balanceTriggerVoltage = balanceTriggerVoltage
        self.balanceMaxCurrent = balanceMaxCurrent
        self.cellOvervoltageProtection = cellOvervoltageProtection
        self.cellOvervoltageRecovery = cellOvervoltageRecovery
        self.cellUndervoltageProtection = cellUndervoltageProtection
        self.cellUndervoltageRecovery = cellUndervoltageRecovery
        self.continuousChargeCurrent = continuousChargeCurrent
        self.continuousDischargeCurrent = continuousDischargeCurrent
        self.mosOverTempProtection = mosOverTempProtection
        self.batteryChargeOverTempProtection = batteryChargeOverTempProtection
        self.batteryDischargeOverTempProtection = batteryDischargeOverTempProtection
        self.batteryChargeUnderTempProtection = batteryChargeUnderTempProtection
        self.batteryDischargeUnderTempProtection = batteryDischargeUnderTempProtection
        self.password = password
    }

    /// Presets matching official JK-BMS one-key configuration
    public static func lifepo4Preset(cellCount: Int = 16, capacity: Double = 100.0) -> JKBMSSettings {
        var s = JKBMSSettings(cellCount: cellCount, batteryCapacity: capacity)
        s.cellOvervoltageProtection = 3.65
        s.cellOvervoltageRecovery = 3.45
        s.cellUndervoltageProtection = 2.50
        s.cellUndervoltageRecovery = 2.65
        s.balanceTriggerVoltage = 0.005
        return s
    }

    public static func liIonPreset(cellCount: Int = 16, capacity: Double = 100.0) -> JKBMSSettings {
        var s = JKBMSSettings(cellCount: cellCount, batteryCapacity: capacity)
        s.cellOvervoltageProtection = 4.25
        s.cellOvervoltageRecovery = 4.15
        s.cellUndervoltageProtection = 3.00
        s.cellUndervoltageRecovery = 3.20
        s.balanceTriggerVoltage = 0.010
        return s
    }

    public static func ltoPreset(cellCount: Int = 16, capacity: Double = 100.0) -> JKBMSSettings {
        var s = JKBMSSettings(cellCount: cellCount, batteryCapacity: capacity)
        s.cellOvervoltageProtection = 2.80
        s.cellOvervoltageRecovery = 2.65
        s.cellUndervoltageProtection = 1.80
        s.cellUndervoltageRecovery = 2.00
        s.balanceTriggerVoltage = 0.010
        return s
    }
}
