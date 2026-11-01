import Foundation

public enum JKCommand {
    case requestTelemetry
    case requestSettings
    case requestDeviceInfo
    case setCharge(enabled: Bool)
    case setDischarge(enabled: Bool)
    case setBalance(enabled: Bool)
    case setEmergency(enabled: Bool)
    case setCellCount(count: Int)
    case setCapacity(ah: Double)
    case setBalanceTriggerVoltage(volts: Double)
    case setBalanceMaxCurrent(amps: Double)
    case setCellOvervoltageProtection(volts: Double)
    case setCellOvervoltageRecovery(volts: Double)
    case setCellUndervoltageProtection(volts: Double)
    case setCellUndervoltageRecovery(volts: Double)
    case setContinuousChargeCurrent(amps: Double)
    case setContinuousDischargeCurrent(amps: Double)
    case setHeating(enabled: Bool)
    case setMosOverTemperature(celsius: Double)
    case setChargeOverTemperature(celsius: Double)
    case setDischargeOverTemperature(celsius: Double)
    case setChargeUnderTemperature(celsius: Double)
    case setDischargeUnderTemperature(celsius: Double)
    case setPassword(newPass: String)
    case restartBoard
    case shutdownBoard
    case factoryRestore
    case setParameter(id: String, value: Double)
    case setOriginalSwitch(family: String, key: String, bit: Int, enabled: Bool)
    case setOriginalParameter(family: String, key: String, value: Double)
    case customRegister(reg: UInt8, data: [UInt8])
}
