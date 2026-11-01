import Foundation

public final class JKSimulator: ObservableObject {
    @Published public var currentStatus: JKBMSStatus
    @Published public var currentSettings: JKBMSSettings
    @Published public var isRunning: Bool = false

    private var timer: Timer?
    private var simTime: TimeInterval = 0

    public init() {
        // Default 16S LiFePO4 pack
        let defaultVoltages = [
            3.332, 3.328, 3.335, 3.330,
            3.331, 3.329, 3.334, 3.333,
            3.328, 3.332, 3.336, 3.331,
            3.330, 3.329, 3.334, 3.332
        ]
        let defaultResistances = [
            0.78, 0.85, 0.82, 0.90,
            0.88, 0.79, 0.84, 0.86,
            0.81, 0.83, 0.89, 0.80,
            0.87, 0.82, 0.85, 0.83
        ]

        self.currentStatus = JKBMSStatus(
            cellVoltages: defaultVoltages,
            cellWireResistances: defaultResistances,
            balancingCellIndices: [10], // Cell 11 is balancing
            batteryVoltage: 53.30,
            batteryCurrent: 12.5, // 12.5A charging
            soc: 82.0,
            remainingCapacity: 82.0,
            totalCapacity: 100.0,
            cycleCount: 28,
            totalCycleCapacity: 2800.0,
            mosTemperature: 29.0,
            batteryT1: 24.5,
            batteryT2: 24.8,
            ambientTemperature: 23.0,
            isChargeEnabled: true,
            isDischargeEnabled: true,
            isBalanceEnabled: true,
            isHeatingEnabled: false,
            alarms: [],
            deviceModel: "JK-B2A24S-20P",
            hardwareVersion: "HW-V11.XA",
            firmwareVersion: "FW-V15.30",
            deviceSN: "JK202610280088",
            uptimeSeconds: 123456,
            manufactureDate: "2026-03-14"
        )
        self.currentSettings = JKBMSSettings.lifepo4Preset(cellCount: 16, capacity: 100.0)
        self.currentSettings.isChargeEnabled = true
        self.currentSettings.isDischargeEnabled = true
        self.currentSettings.isBalanceEnabled = true
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    public func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        simTime += 1.0
        var status = currentStatus

        // Subtle realistic fluctuations
        let drift = sin(simTime / 5.0) * 0.002
        for i in 0..<status.cellVoltages.count {
            let cellNoise = sin(simTime + Double(i)) * 0.0008
            status.cellVoltages[i] = max(3.0, min(3.6, status.cellVoltages[i] + drift * 0.1 + cellNoise))
        }

        // Current fluctuations
        if status.isChargeEnabled && !status.isDischargeEnabled {
            status.batteryCurrent = 15.0 + sin(simTime / 3.0) * 0.5
        } else if !status.isChargeEnabled && status.isDischargeEnabled {
            status.batteryCurrent = -(22.0 + sin(simTime / 4.0) * 1.2)
        } else if status.isChargeEnabled && status.isDischargeEnabled {
            status.batteryCurrent = 8.4 + sin(simTime / 6.0) * 0.8
        } else {
            status.batteryCurrent = 0.0
        }

        let totalV = status.cellVoltages.reduce(0.0, +)
        status.batteryVoltage = totalV
        status.uptimeSeconds += 1

        // Balancing active on max cell
        if status.isBalanceEnabled && status.deltaVoltage > currentSettings.balanceTriggerVoltage {
            status.balancingCellIndices = [status.maxCellIndex]
        } else {
            status.balancingCellIndices = []
        }

        status.recalculateStats()
        self.currentStatus = status
    }

    public func execute(command: JKCommand) {
        switch command {
        case .setCharge(let enabled):
            currentStatus.isChargeEnabled = enabled
            currentSettings.isChargeEnabled = enabled
        case .setDischarge(let enabled):
            currentStatus.isDischargeEnabled = enabled
            currentSettings.isDischargeEnabled = enabled
        case .setBalance(let enabled):
            currentStatus.isBalanceEnabled = enabled
            currentSettings.isBalanceEnabled = enabled
        case .setEmergency(let enabled):
            currentStatus.isEmergencyEnabled = enabled
        case .setHeating(let enabled):
            currentStatus.isHeatingEnabled = enabled
            currentSettings.isHeatingEnabled = enabled
        case .setMosOverTemperature(let value):
            currentSettings.mosOverTempProtection = value
        case .setChargeOverTemperature(let value):
            currentSettings.batteryChargeOverTempProtection = value
        case .setDischargeOverTemperature(let value):
            currentSettings.batteryDischargeOverTempProtection = value
        case .setChargeUnderTemperature(let value):
            currentSettings.batteryChargeUnderTempProtection = value
        case .setDischargeUnderTemperature(let value):
            currentSettings.batteryDischargeUnderTempProtection = value
        case .setOriginalSwitch(_, let key, let bit, let enabled):
            let old = UInt32(currentSettings.originalValues[key] ?? 0)
            currentSettings.originalValues[key] = Double(enabled ? old | (1 << bit) : old & ~(1 << bit))
        case .setOriginalParameter(_, let key, let value):
            currentSettings.originalValues[key] = value
        case .setParameter(let id, let value):
            currentSettings.extendedValues[id] = value
        case .setCellCount(let count):
            currentSettings.cellCount = count
            if count > currentStatus.cellVoltages.count {
                let addCount = count - currentStatus.cellVoltages.count
                currentStatus.cellVoltages.append(contentsOf: Array(repeating: 3.330, count: addCount))
                currentStatus.cellWireResistances.append(contentsOf: Array(repeating: 0.85, count: addCount))
            } else if count < currentStatus.cellVoltages.count {
                currentStatus.cellVoltages = Array(currentStatus.cellVoltages.prefix(count))
                currentStatus.cellWireResistances = Array(currentStatus.cellWireResistances.prefix(count))
            }
            currentStatus.recalculateStats()
        case .setCapacity(let ah):
            currentSettings.batteryCapacity = ah
            currentStatus.totalCapacity = ah
        case .setBalanceTriggerVoltage(let volts):
            currentSettings.balanceTriggerVoltage = volts
        case .setBalanceMaxCurrent(let amps):
            currentSettings.balanceMaxCurrent = amps
        case .setCellOvervoltageProtection(let volts):
            currentSettings.cellOvervoltageProtection = volts
        case .setCellOvervoltageRecovery(let volts):
            currentSettings.cellOvervoltageRecovery = volts
        case .setCellUndervoltageProtection(let volts):
            currentSettings.cellUndervoltageProtection = volts
        case .setCellUndervoltageRecovery(let volts):
            currentSettings.cellUndervoltageRecovery = volts
        case .setContinuousChargeCurrent(let amps):
            currentSettings.continuousChargeCurrent = amps
        case .setContinuousDischargeCurrent(let amps):
            currentSettings.continuousDischargeCurrent = amps
        case .setPassword(let newPass):
            currentSettings.password = newPass
        case .restartBoard:
            currentStatus.uptimeSeconds = 0
        case .shutdownBoard:
            currentStatus.isChargeEnabled = false
            currentStatus.isDischargeEnabled = false
            currentStatus.isBalanceEnabled = false
        case .factoryRestore:
            currentSettings = JKBMSSettings.lifepo4Preset(cellCount: currentSettings.cellCount, capacity: 100.0)
        default:
            break
        }
    }
}
