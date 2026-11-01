import Foundation
import CoreBluetooth
import Combine

private struct JKSettingsDocument: Codable {
    let schemaVersion: Int
    let `protocol`: String
    let deviceModel: String
    let cellCount: Int
    let batteryChemistry: String
    let settings: [String: Double]
}

/// Owns one BLE session. A BLE link alone never means that usable battery data was received.
public final class JKBluetoothManager: NSObject, ObservableObject {
    public static let shared = JKBluetoothManager()
    public static let serviceUUID = CBUUID(string: "FFE0")
    public static let notifyUUID = CBUUID(string: "FFE1")
    public static let writeUUID = CBUUID(string: "FFE1")

    @Published public private(set) var bluetoothState: CBManagerState = .unknown
    @Published public private(set) var isScanning = false
    @Published public private(set) var isConnected = false
    @Published public private(set) var isConnecting = false
    @Published public private(set) var discoveredDevices: [JKDevice] = []
    @Published public private(set) var connectedDevice: JKDevice?
    @Published public var status = JKBMSStatus()
    @Published public var settings = JKBMSSettings()
    @Published public private(set) var isSimulatorMode = false
    @Published public var lastErrorMessage: String?
    @Published public private(set) var connectionMessage = "等待蓝牙就绪"
    @Published public private(set) var hasTelemetry = false
    @Published public private(set) var hasSettings = false
    @Published public private(set) var lastUpdate: Date?
    @Published public private(set) var commandMessage = ""
    @Published public private(set) var diagnosticLog = ""
    @Published public private(set) var isAuthenticated = false
    @Published public private(set) var isDeviceUnlocked = false
    @Published public private(set) var hasRememberedConnectionPassword = false
    @Published public private(set) var hasRememberedSettingsPassword = false
    @Published public private(set) var credentialMessage = ""
    private let credentials: JKDeviceCredentials
    public var requiresDevicePassword: Bool {
        guard !isSimulatorMode, !isDeviceUnlocked,
              let flags = originalRawInfo["enableFlags"], JKOriginalSchema.bitEnabled(flags.bytes, index: 7) else { return false }
        return !(originalRawInfo["bluetoothPwd"]?.text?.isEmpty ?? false)
    }
    @Published public private(set) var originalSchemaName = ""
    @Published public private(set) var originalRealtime: [JKOriginalValue] = []
    @Published public private(set) var originalSettings: [JKOriginalValue] = []
    @Published public private(set) var originalDeviceInfo: [JKOriginalValue] = []
    private var originalRawSettings: [String: JKOriginalValue] = [:]
    private var originalRawInfo: [String: JKOriginalValue] = [:]
    @Published public private(set) var detailedLogs: [JKDetailedLogRecord] = []
    @Published public private(set) var detailedLogMessage = "尚未读取详细历史"
    @Published public private(set) var isDownloadingDetailedLogs = false
    private var pendingIdentity: (kind: JKDeviceTextKind, value: String, deadline: Date)?
    private var pendingClock: (seconds: UInt32, deadline: Date)?
    private var pendingCalibration: (voltage: Bool, value: Double, deadline: Date)?
    private var pendingEraseDeadline: Date?
    private var pendingPreset: (chemistry: Int, settingsRead: Bool, deadline: Date)?
    private var exclusiveMutationPending: Bool {
        pendingIdentity != nil || pendingClock != nil || pendingCalibration != nil || pendingEraseDeadline != nil || pendingPreset != nil
    }
    private var detailedLastPage = Date.distantPast
    @Published public private(set) var systemLogs: [JKLogRecord] = []
    @Published public private(set) var logbookMessage = "尚未读取设备系统日志"
    @Published public var protocolVariant: JKProtocolVariant = .automatic
    @Published public private(set) var detectedProtocol: JKProtocolVariant = .automatic

    public var maximumCellCount: Int {
        if let maximum = originalRawInfo["maxCells"]?.number, maximum.isFinite, (1...32).contains(maximum) { return Int(maximum) }
        if let model = deviceInfo?.model,
           let item = JKOriginalSchema.deviceModels.first(where: { $0.name == model && $0.series == originalSchemaName }) { return item.count }
        return min(32, JKOriginalSchema.fields(family: originalSchemaName, type: 2).first(where: { $0.key == "cellVol" })?.count ?? 32)
    }
    public var supportsPasswordChange: Bool { isSimulatorMode || originalCommandSupported(0xA0) }
    public var supportsSystemCommands: Bool { isSimulatorMode || detectedProtocol == .jk02_32s }
    public var canWrite: Bool {
        isConnected && hasSettings && hasTelemetry && !requiresDevicePassword && (isSimulatorMode ||
            (isAuthenticated && detectedProtocol != .automatic))
    }
    public let simulator = JKSimulator()

    private var centralManager: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var activePeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var assembler = JKStreamAssembler()
    private var deviceInfo: JKDeviceInfo?
    private var settingsFrame: Data?
    private var deviceInfoFrame: Data?
    private var undecodedFrames: [Data] = []
    private var sessionID = UUID()
    private var userDisconnected = false
    private var reconnectAttempts = 0
    private var scanTimeout: Timer?
    private var sessionTimeout: Timer?
    private var monitorTimer: Timer?
    private var transportTimer: Timer?
    private var transportQueue: [Data] = []
    private var awaitingWriteResponse = false
    private var writes: [JKCommand] = []
    private var pendingWrite: JKCommand?
    private var pendingDeadline: Date?
    private var lastRequest = Date.distantPast
    private var cancellables = Set<AnyCancellable>()
    private var persistDiagnostics = false

    public override convenience init() { self.init(enableBluetooth: true) }

    public init(enableBluetooth: Bool, credentialStore: JKCredentialStore = JKKeychainCredentialStore()) {
        credentials = JKDeviceCredentials(store: credentialStore)
        super.init()
        persistDiagnostics = enableBluetooth
        simulator.$currentStatus.receive(on: DispatchQueue.main).sink { [weak self] value in
            guard let self, self.isSimulatorMode else { return }
            self.status = value
            self.hasTelemetry = true
            self.lastUpdate = Date()
        }.store(in: &cancellables)
        simulator.$currentSettings.receive(on: DispatchQueue.main).sink { [weak self] value in
            guard let self, self.isSimulatorMode else { return }
            self.settings = value
            self.hasSettings = true
        }.store(in: &cancellables)
        if enableBluetooth { centralManager = CBCentralManager(delegate: self, queue: .main) }
    }

    public func setDemoMode(_ enabled: Bool) {
        guard enabled != isSimulatorMode else { return }
        disconnect()
        isSimulatorMode = enabled
        discoveredDevices = []
        if enabled {
            let device = JKDevice(id: UUID(uuidString: "00000000-0000-0000-0000-00000000B2A0")!,
                                  name: "JK-B2A24S（演示设备）", isConnected: true, isSimulator: true)
            connectedDevice = device
            discoveredDevices = [device]
            isConnected = true
            isAuthenticated = true
            status = simulator.currentStatus
            settings = simulator.currentSettings
            hasSettings = true
            hasTelemetry = true
            lastUpdate = Date()
            connectionMessage = "演示模式 · 数据由本地模拟器生成"
            simulator.start()
        } else {
            connectionMessage = "真实设备模式 · 请连接保护板"
            if bluetoothState == .poweredOn { startScan() }
        }
        log(enabled ? "进入演示模式" : "退出演示模式")
    }

    public func startScan() {
        guard !isSimulatorMode else { return }
        guard let central = centralManager, central.state == .poweredOn else {
            fail(bluetoothState == .unauthorized ? "请在系统设置中允许本应用使用蓝牙" : "蓝牙尚未开启或不可用")
            return
        }
        guard !isConnecting && !isConnected else { return }
        lastErrorMessage = nil
        discoveredDevices = []
        peripherals = [:]
        isScanning = true
        connectionMessage = "正在搜索附近保护板"
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        log("开始扫描 BLE 广播")
        scanTimeout?.invalidate()
        scanTimeout = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            self?.stopScan()
        }
    }

    public func stopScan() {
        centralManager?.stopScan()
        scanTimeout?.invalidate()
        scanTimeout = nil
        isScanning = false
        if !isConnected && !isConnecting {
            connectionMessage = discoveredDevices.isEmpty ? "未发现设备 · 请确认保护板通电并靠近手机" : "请选择要连接的保护板"
        }
    }

    public func connect(to device: JKDevice) {
        if device.isSimulator {
            if isSimulatorMode { setDemoMode(false) }
            setDemoMode(true); return
        }
        guard bluetoothState == .poweredOn else { fail("蓝牙尚未开启或未获授权"); return }
        let peripheral = peripherals[device.id] ?? centralManager?.retrievePeripherals(withIdentifiers: [device.id]).first
        guard let peripheral else { fail("设备已不在扫描结果中，请重新扫描"); return }
        if isSimulatorMode { setDemoMode(false) }
        disconnect()
        stopScan()
        userDisconnected = false
        reconnectAttempts = 0
        beginConnection(peripheral, name: device.name)
    }

    private func beginConnection(_ peripheral: CBPeripheral, name: String) {
        resetSession()
        activePeripheral = peripheral
        peripheral.delegate = self
        connectedDevice = JKDevice(id: peripheral.identifier, name: name)
        credentials.beginSession(deviceID: peripheral.identifier)
        syncCredentialState()
        isConnecting = true
        lastErrorMessage = nil
        connectionMessage = "正在连接 \(name)"
        log("连接设备 \(name)")
        centralManager?.connect(peripheral, options: nil)
        let token = sessionID
        sessionTimeout = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            guard let self, self.sessionID == token, !self.hasTelemetry else { return }
            self.fail("连接或数据读取超时，请检查设备是否被其他应用占用")
            self.centralManager?.cancelPeripheralConnection(peripheral)
        }
    }

    public func disconnect() {
        userDisconnected = true
        stopScan()
        simulator.stop()
        if let peripheral = activePeripheral {
            activePeripheral = nil
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        resetSession()
        connectedDevice = nil
        connectionMessage = "未连接设备"
        discoveredDevices = discoveredDevices.map { value in
            var result = value; result.isConnected = false; return result
        }
    }

    private func resetSession() {
        sessionID = UUID()
        sessionTimeout?.invalidate(); sessionTimeout = nil
        monitorTimer?.invalidate(); monitorTimer = nil
        transportTimer?.invalidate(); transportTimer = nil
        transportQueue = []; awaitingWriteResponse = false
        if pendingWrite != nil || !writes.isEmpty { commandMessage = "连接已结束，未确认的操作已取消" }
        writes = []; pendingWrite = nil; pendingDeadline = nil
        writeCharacteristic = nil; notifyCharacteristic = nil
        assembler.reset(); deviceInfo = nil; settingsFrame = nil; deviceInfoFrame = nil; undecodedFrames = []
        originalSchemaName = ""; originalRealtime = []; originalSettings = []; originalDeviceInfo = []
        originalRawSettings = [:]; originalRawInfo = [:]
        systemLogs = []; logbookMessage = "尚未读取设备系统日志"
        pendingIdentity = nil; pendingClock = nil; pendingCalibration = nil; pendingEraseDeadline = nil; pendingPreset = nil
        detailedLogs = []; detailedLogMessage = "尚未读取详细历史"; isDownloadingDetailedLogs = false
        credentials.endSession()
        hasRememberedConnectionPassword = false; hasRememberedSettingsPassword = false; credentialMessage = ""
        isConnected = false; isConnecting = false; isAuthenticated = false; isDeviceUnlocked = false
        hasTelemetry = false; hasSettings = false; lastUpdate = nil
        detectedProtocol = .automatic
        status = JKBMSStatus(); settings = JKBMSSettings()
    }

    /// Matches the setting password read from this session's device information.
    /// This is an application edit lock, not a BLE authentication exchange.
    @discardableResult public func authenticate(password: String, remember: Bool = true) -> Bool {
        if isSimulatorMode { isAuthenticated = true; return true }
        guard !requiresDevicePassword else { fail("请先输入蓝牙连接密码"); return false }
        guard isConnected, deviceInfo != nil else { fail("正在读取设备信息，请稍后再试"); return false }
        guard credentials.verify(password, kind: .settings, remember: remember) else {
            fail("设置密码不匹配，请重新输入"); return false
        }
        syncCredentialState()
        lastErrorMessage = nil
        commandMessage = "设置密码已核对，修改已解锁"
        return true
    }

    @discardableResult public func unlockDevice(password: String, remember: Bool = true) -> Bool {
        guard isConnected, deviceInfo != nil,
              credentials.verify(password, kind: .connection, remember: remember) else {
            fail("蓝牙连接密码不匹配，请重新输入"); return false
        }
        syncCredentialState()
        lastErrorMessage = nil
        commandMessage = "蓝牙连接密码已核对"
        // Already received data can be shown immediately, rather than waiting for the next notification.
        if let update = lastUpdate, Date().timeIntervalSince(update) <= 8 {
            hasTelemetry = true
            connectionMessage = "实时通信正常 · " + (originalSchemaName.isEmpty ? detectedProtocol.displayName : originalSchemaName)
        }
        request(.requestTelemetry)
        return true
    }

    public func forgetRememberedPasswords() {
        credentials.forgetSavedPasswords()
        syncCredentialState()
        if credentialMessage.isEmpty { commandMessage = "已清除记住的密码，下次连接时重新输入" }
    }

    private func syncCredentialState() {
        isDeviceUnlocked = credentials.isVerified(.connection)
        isAuthenticated = credentials.isVerified(.settings)
        hasRememberedConnectionPassword = credentials.remembered.contains(.connection)
        hasRememberedSettingsPassword = credentials.remembered.contains(.settings)
        credentialMessage = credentials.storageMessage
        if credentialMessage.isEmpty, !credentials.changed.isEmpty {
            credentialMessage = "设备密码已变更，请重新输入；旧密码已清除。"
        }
    }

    public func supports(command supplied: JKCommand) -> Bool {
        let command = normalizeCommand(supplied)
        if case .setOriginalSwitch(_, let key, let bit, _) = command { return originalSwitchAvailable(key: key, bit: bit) }
        if case .setOriginalParameter(_, let key, _) = command { return originalCanEdit(key) }
        return isSimulatorMode || JKModernCodec.supports(command: command, variant: detectedProtocol)
    }

    public func send(command supplied: JKCommand) {
        let command = normalizeCommand(supplied)
        if isSimulatorMode {
            simulator.execute(command: command)
            status = simulator.currentStatus; settings = simulator.currentSettings
            commandMessage = "演示操作已执行（未发送到真实设备）"
            return
        }
        guard isConnected, writeCharacteristic != nil else { fail("尚未连接可通信的保护板"); return }
        if isRead(command) {
            request(command)
            return
        }
        guard canWrite else { fail("请等待读取设备参数并确认设置密码后再修改"); return }
        if case .setPassword(let value) = command { changeDeviceText(kind: .settingsPassword, value: value); return }
        guard !exclusiveMutationPending else { fail("请等待设备信息修改回读完成"); return }
        guard supports(command: command) else { fail("此设备协议尚不支持该操作"); return }
        if case .setOriginalParameter(_, "cellCount", let value) = command, value > Double(maximumCellCount) {
            fail("串数超过该型号上限（\(maximumCellCount)串）"); return
        }
        if case .setParameter(let id, let value) = command,
           !JKParameterCatalog.isValueAvailable(id: id, value: value, settings: settings) {
            fail("参数不在此设备公布的可选范围内"); return
        }
        do { _ = try JKModernCodec.encode(command: command, variant: detectedProtocol) }
        catch { fail(error.localizedDescription); return }
        guard writes.count < 128 else { fail("待写入操作过多，请等候回读完成"); return }
        writes.append(command)
        if pendingWrite == nil { processNextWrite() }
    }

    public func applyPreset(_ preset: JKBMSSettings) {
        guard canWrite else { fail("请先连接设备并解锁修改"); return }
        // Preserve the board's cell count and capacity. These presets only change the selected chemistry thresholds.
        let chemistry = preset.cellOvervoltageProtection < 3 ? 2 : (preset.cellOvervoltageProtection < 4 ? 0 : 1)
        let nativeRegister: UInt8 = chemistry == 0 ? 0x69 : (chemistry == 1 ? 0x68 : 0x6A)
        if !isSimulatorMode && originalCommandSupported(nativeRegister) {
            guard pendingWrite == nil, writes.isEmpty, pendingPreset == nil else { fail("请等待当前修改完成"); return }
            pendingPreset = (chemistry, false, Date().addingTimeInterval(10))
            commandMessage = "原版一键配置指令已发送，等待读取整组参数与电池类型"
            enqueue(JKModernCodec.command(register: nativeRegister))
            let token = sessionID
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self, self.sessionID == token else { return }; self.request(.requestSettings)
            }
            return
        }
        let commands: [JKCommand] = [
            .setCellOvervoltageProtection(volts: preset.cellOvervoltageProtection),
            .setCellOvervoltageRecovery(volts: preset.cellOvervoltageRecovery),
            .setCellUndervoltageProtection(volts: preset.cellUndervoltageProtection),
            .setCellUndervoltageRecovery(volts: preset.cellUndervoltageRecovery),
            .setBalanceTriggerVoltage(volts: preset.balanceTriggerVoltage)
        ].map(normalizeCommand)
        guard pendingWrite == nil, writes.isEmpty else { fail("请等待当前修改结束后再应用预设"); return }
        for command in commands {
            guard supports(command: command) else { fail("当前协议不支持该预设的全部参数"); return }
            if !isSimulatorMode {
                do { _ = try JKModernCodec.encode(command: command, variant: detectedProtocol) }
                catch { fail(error.localizedDescription); return }
            }
        }
        if isSimulatorMode { commands.forEach { send(command: $0) }; return }
        writes = commands
        commandMessage = "开始写入预设，逐项等待保护板回读"
        processNextWrite()
    }



    public func requestSystemLogs() {
        guard !isSimulatorMode, isConnected, detectedProtocol != .legacy,
              detectedProtocol != .automatic else { fail("请先连接并识别支持系统日志的保护板"); return }
        logbookMessage = "正在读取保护板系统日志"
        enqueue(JKModernCodec.command(register: 0xA1))
        let token = sessionID
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, self.sessionID == token, self.logbookMessage == "正在读取保护板系统日志" else { return }
            self.logbookMessage = "读取超时，设备可能不支持此日志命令"
        }
    }

    public var systemLogsCSV: String {
        let rows = systemLogs.map { record in
            "\(record.index),\(record.uptime),\(record.code),\(record.event)"
        }
        return (["index,uptime_seconds,event_code,event"] + rows).joined(separator: "\n")
    }

    /// Original format includes device information, including device credentials.
    /// Exposed only to the explicit Save Backup UI; never included in diagnostics.
    public var originalBackupData: Data? {
        guard let settingsFrame, let deviceInfoFrame, hasSettings,
              settingsFrame.count == 300, deviceInfoFrame.count == 300 else { return nil }
        return settingsFrame + deviceInfoFrame
    }

    public var exportSettingsJSON: String {
        guard hasSettings else { return "" }
        var values: [String: Double] = [
            "cellCount": Double(settings.cellCount), "batteryCapacity": settings.batteryCapacity,
            "balanceTriggerVoltage": settings.balanceTriggerVoltage, "balanceMaxCurrent": settings.balanceMaxCurrent,
            "cellOvervoltageProtection": settings.cellOvervoltageProtection,
            "cellOvervoltageRecovery": settings.cellOvervoltageRecovery,
            "cellUndervoltageProtection": settings.cellUndervoltageProtection,
            "cellUndervoltageRecovery": settings.cellUndervoltageRecovery,
            "continuousChargeCurrent": settings.continuousChargeCurrent,
            "continuousDischargeCurrent": settings.continuousDischargeCurrent,
            "mosOverTempProtection": settings.mosOverTempProtection,
            "batteryChargeOverTempProtection": settings.batteryChargeOverTempProtection,
            "batteryDischargeOverTempProtection": settings.batteryDischargeOverTempProtection,
            "batteryChargeUnderTempProtection": settings.batteryChargeUnderTempProtection,
            "batteryDischargeUnderTempProtection": settings.batteryDischargeUnderTempProtection
        ]
        values.merge(settings.extendedValues, uniquingKeysWith: { _, new in new })
        for (key, value) in settings.originalValues where originalCanEdit(key) {
            values["original." + key] = value
        }
        values = values.filter { key, value in
            guard value.isFinite, let command = configurationCommand(key: key, value: value) else { return false }
            return supports(command: command)
        }
        let document = JKSettingsDocument(schemaVersion: 1, protocol: detectedProtocol.rawValue,
            deviceModel: status.deviceModel, cellCount: settings.cellCount,
            batteryChemistry: "未指定", settings: values)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(document) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Called only after the UI has shown an import preview and the user confirms applying it.
    public func importSettingsJSON(_ text: String) {
        guard canWrite, pendingWrite == nil, writes.isEmpty, !exclusiveMutationPending else { fail("请先解锁修改并等候当前操作完成"); return }
        guard text.utf8.count <= 131072, let data = text.data(using: .utf8),
              let document = try? JSONDecoder().decode(JKSettingsDocument.self, from: data),
              document.schemaVersion == 1, !document.settings.isEmpty, document.settings.count <= 128 else {
            fail("配置文件格式无效或版本不受支持"); return
        }
        if let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let sourceFirmware = object["sourceFirmware"] as? String {
            guard document.deviceModel == status.deviceModel, sourceFirmware == status.firmwareVersion else {
                fail("原版备份的型号或固件版本与当前设备不一致，未写入"); return
            }
        }
        guard isSimulatorMode || document.protocol == detectedProtocol.rawValue else {
            fail("配置来自不同通信协议，未写入，请先核对目标设备"); return
        }
        var commands: [JKCommand] = []
        for (key, value) in document.settings.sorted(by: { $0.key < $1.key }) {
            guard value.isFinite, let supplied = configurationCommand(key: key, value: value), supports(command: supplied) else {
                fail("配置包含当前设备不支持的参数：\(key)"); return
            }
            let command = normalizeCommand(supplied)
            if case .setOriginalParameter(_, "cellCount", let value) = command, value > Double(maximumCellCount) {
                fail("备份串数超过当前型号上限，未写入"); return
            }
            if case .setParameter(let id, let value) = command,
               !JKParameterCatalog.isValueAvailable(id: id, value: value, settings: settings) {
                fail("参数 \(key) 不在目标设备公布的可选范围内"); return
            }
            do { _ = try JKModernCodec.encode(command: command, variant: isSimulatorMode ? .jk02_32s : detectedProtocol) }
            catch { fail("参数 \(key)：\(error.localizedDescription)"); return }
            if !JKModernCodec.matches(command: command, status: status, settings: settings) { commands.append(command) }
        }
        guard !commands.isEmpty else { commandMessage = "配置与设备回读值一致，无需写入"; return }
        if isSimulatorMode { commands.forEach { send(command: $0) }; return }
        writes = commands
        commandMessage = "开始导入 \(commands.count) 项参数，逐项回读验证"
        processNextWrite()
    }

    private func configurationCommand(key: String, value: Double) -> JKCommand? {
        switch key {
        case "cellCount": guard value.rounded() == value, (1...32).contains(value) else { return nil }; return .setCellCount(count: Int(value))
        case "batteryCapacity": return .setCapacity(ah: value)
        case "balanceTriggerVoltage": return .setBalanceTriggerVoltage(volts: value)
        case "balanceMaxCurrent": return .setBalanceMaxCurrent(amps: value)
        case "cellOvervoltageProtection": return .setCellOvervoltageProtection(volts: value)
        case "cellOvervoltageRecovery": return .setCellOvervoltageRecovery(volts: value)
        case "cellUndervoltageProtection": return .setCellUndervoltageProtection(volts: value)
        case "cellUndervoltageRecovery": return .setCellUndervoltageRecovery(volts: value)
        case "continuousChargeCurrent": return .setContinuousChargeCurrent(amps: value)
        case "continuousDischargeCurrent": return .setContinuousDischargeCurrent(amps: value)
        case "mosOverTempProtection": return .setMosOverTemperature(celsius: value)
        case "batteryChargeOverTempProtection": return .setChargeOverTemperature(celsius: value)
        case "batteryDischargeOverTempProtection": return .setDischargeOverTemperature(celsius: value)
        case "batteryChargeUnderTempProtection": return .setChargeUnderTemperature(celsius: value)
        case "batteryDischargeUnderTempProtection": return .setDischargeUnderTemperature(celsius: value)
        default:
            if key.hasPrefix("original.") {
                let original = String(key.dropFirst(9))
                guard JKOriginalSchema.writableField(key: original, family: originalSchemaName) != nil else { return nil }
                return .setOriginalParameter(family: originalSchemaName, key: original, value: value)
            }
            guard JKParameterCatalog.definitions.contains(where: { $0.id == key }) else { return nil }
            return .setParameter(id: key, value: value)
        }
    }

    private func isRead(_ command: JKCommand) -> Bool {
        switch command { case .requestTelemetry, .requestSettings, .requestDeviceInfo: return true; default: return false }
    }

    private func request(_ command: JKCommand) {
        do {
            let packet: Data
            if detectedProtocol == .legacy || protocolVariant == .legacy {
                packet = JKPacketCodec.encode(command: .requestTelemetry)
            } else {
                // Both requests use the same wire format across JK02 and JK04.
                packet = JKModernCodec.command(register: {
                    switch command { case .requestDeviceInfo: return UInt8(0x97); default: return UInt8(0x96) }
                }())
            }
            enqueue(packet)
            lastRequest = Date()
        }
    }

    private func processNextWrite() {
        guard pendingWrite == nil, !writes.isEmpty, canWrite else { return }
        let command = writes.removeFirst()
        do {
            let packet = try JKModernCodec.encode(command: command, variant: detectedProtocol)
            pendingWrite = command
            pendingDeadline = Date().addingTimeInterval(8)
            commandMessage = "指令发送中 · 等待设备回读确认"
            enqueue(packet)
            let token = sessionID
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, self.sessionID == token, self.pendingWrite != nil else { return }
                switch command {
                case .restartBoard, .shutdownBoard, .factoryRestore:
                    self.commandMessage = "系统指令已发送，执行结果需根据设备重连和参数回读确认"
                    // System commands do not have a documented success acknowledgment.
                    self.pendingWrite = nil; self.pendingDeadline = nil; self.writes = []
                default:
                    self.request(.requestSettings)
                    if case .setParameter = command { self.request(.requestDeviceInfo) }
                }
            }
        } catch { abortWrites(error.localizedDescription) }
    }

    private func verifyPendingWrite() {
        guard let command = pendingWrite else { return }
        if JKModernCodec.matches(command: command, status: status, settings: settings) {
            pendingWrite = nil; pendingDeadline = nil
            commandMessage = writes.isEmpty ? "已由保护板回读确认" : "本项回读一致，继续写入其余 \(writes.count) 项"
            let token = sessionID
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, self.sessionID == token else { return }; self.processNextWrite()
            }
        }
    }

    private func abortWrites(_ reason: String) {
        pendingWrite = nil; pendingDeadline = nil; writes = []
        // Do not replay a possibly already applied mutation on reconnect.
        transportQueue = []
        commandMessage = "操作未确认：\(reason)"
        fail(reason)
    }

    private func enqueue(_ packet: Data) {
        guard let peripheral = activePeripheral, let characteristic = writeCharacteristic else { return }
        let type: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        let chunkSize = max(1, peripheral.maximumWriteValueLength(for: type))
        for offset in stride(from: 0, to: packet.count, by: chunkSize) {
            transportQueue.append(packet.subdata(in: offset..<min(packet.count, offset + chunkSize)))
        }
        if transportTimer == nil {
            transportTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in self?.pumpTransport() }
        }
        pumpTransport()
    }

    private func pumpTransport() {
        guard !awaitingWriteResponse, !transportQueue.isEmpty,
              let peripheral = activePeripheral, peripheral.state == .connected,
              let characteristic = writeCharacteristic else { return }
        let withoutResponse = characteristic.properties.contains(.writeWithoutResponse)
        if withoutResponse && !peripheral.canSendWriteWithoutResponse { return }
        let packet = transportQueue.removeFirst()
        awaitingWriteResponse = !withoutResponse
        peripheral.writeValue(packet, for: characteristic, type: withoutResponse ? .withoutResponse : .withResponse)
        // Log only type/register, never payloads (device info carries passwords).
        log("TX \(packet.count) bytes" + (packet.count >= 5 ? String(format: " · command 0x%02X", packet[4]) : ""))
        if transportQueue.isEmpty && !awaitingWriteResponse { transportTimer?.invalidate(); transportTimer = nil }
    }

    private func beginHandshake() {
        guard let peripheral = activePeripheral, let notify = notifyCharacteristic, let write = writeCharacteristic,
              notify.isNotifying else { return }
        log("通知订阅成功，读写特征就绪 · \(write.uuid.uuidString)")
        isConnected = true; isConnecting = false
        connectedDevice?.isConnected = true
        detectedProtocol = protocolVariant
        connectionMessage = "蓝牙已连接 · 正在读取设备信息并识别协议"
        if protocolVariant == .legacy {
            request(.requestTelemetry)
        } else {
            request(.requestDeviceInfo)
            let token = sessionID
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self, self.sessionID == token, peripheral == self.activePeripheral else { return }
                self.request(.requestSettings)
            }
        }
        monitorTimer?.invalidate()
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.monitor() }
    }

    private func monitor() {
        if let pending = pendingIdentity, Date() > pending.deadline {
            pendingIdentity = nil; fail("设备信息修改未获回读确认，请重新读取并核对")
            commandMessage = "修改未确认"
        }
        if let clock = pendingClock, Date() > clock.deadline {
            pendingClock = nil; commandMessage = "时间校准未获回读确认"
        }
        if let calibration = pendingCalibration, Date() > calibration.deadline {
            pendingCalibration = nil; commandMessage = "校准未获测量值回读确认，请检查实际测量条件"
        }
        if let preset = pendingPreset, Date() > preset.deadline {
            pendingPreset = nil; commandMessage = "一键配置尚未获得完整参数与电池类型回读确认"
        }
        if let deadline = pendingEraseDeadline, Date() > deadline {
            pendingEraseDeadline = nil; commandMessage = "清除指令未获设备历史计数回读确认"
        }
        if isDownloadingDetailedLogs && Date().timeIntervalSince(detailedLastPage) > 12 {
            isDownloadingDetailedLogs = false; detailedLogMessage = "下载中断或超时，已保留 \(detailedLogs.count) 条记录"
        }
        if let deadline = pendingDeadline, Date() > deadline { abortWrites("设备未回传与请求一致的参数，请核对保护板状态") }
        if let update = lastUpdate, Date().timeIntervalSince(update) > 8 {
            hasTelemetry = false
            connectionMessage = "蓝牙仍连接，但实时数据已超时"
        }
        guard pendingWrite == nil, transportQueue.isEmpty, Date().timeIntervalSince(lastRequest) > 5 else { return }
        if protocolVariant == .automatic && deviceInfo == nil && !hasTelemetry {
            enqueue(JKPacketCodec.encode(command: .requestTelemetry))
            request(.requestDeviceInfo)
        }
        if detectedProtocol == .legacy || !hasTelemetry || !hasSettings { request(.requestTelemetry) }
    }

    func receive(_ frame: Data) {
        guard frame.count >= 5 else { return }
        if frame[0] == 0x4E {
            if protocolVariant != .automatic && protocolVariant != .legacy { return }
            guard let decoded = JKPacketCodec.decode(data: frame) else { log("旧版帧解析失败"); return }
            detectedProtocol = .legacy
            status = decoded
            hasTelemetry = !requiresDevicePassword; lastUpdate = Date()
            if let parsedSettings = JKPacketCodec.decodeSettings(data: frame) { settings = parsedSettings; hasSettings = true }
            connectionMessage = "已收到旧版协议数据（写入按支持能力开放）"
            sessionTimeout?.invalidate()
            verifyPendingWrite()
            return
        }
        let frameType = frame[4]
        if frameType == 3, let family = JKOriginalSchema.identify(infoFrame: frame) {
            originalSchemaName = family
            if protocolVariant == .automatic {
                let cells = JKOriginalSchema.fields(family: family, type: 2).first(where: { $0.key == "cellVol" })
                if cells?.numeric == "f32" { detectedProtocol = .jk04 }
                else if cells?.count == 32 { detectedProtocol = .jk02_32s }
                else if cells?.count == 24 { detectedProtocol = .jk02_24s }
            }
        }
        updateOriginalFields(frame)
        if frameType == 6 { receiveDetailedLogs(frame); return }
        if frameType == 5, let records = JKLogbookCodec.decode(frame) {
            systemLogs = records
            logbookMessage = "已读取 \(records.count) 条设备事件（时间为设备运行时间）"
            return
        }
        log(String(format: "RX type 0x%02X · %d bytes · checksum valid", frameType, frame.count))
        if frameType == 0x01 { settingsFrame = frame }
        if frameType == 0x03 { deviceInfoFrame = frame }
        let extra = JKParameterCatalog.decode(frame: frame, variant: detectedProtocol)
        settings.extendedValues.merge(extra, uniquingKeysWith: { _, new in new })
        if frameType == 0x03, let info = JKModernCodec.parse(frame: frame, variant: .jk02_24s)?.info {
            deviceInfo = info
            credentials.update(connection: info.devicePassword, settings: info.setupPassword)
            syncCredentialState()
            applyInfo(info)
        }
        if detectedProtocol == .automatic {
            if let variant = JKModernCodec.detectVariant(frame: frame, info: deviceInfo, settingsFrame: settingsFrame) {
                detectedProtocol = variant
                log("识别协议：\(variant.displayName)")
                let buffered = undecodedFrames
                undecodedFrames = []
                for bufferedFrame in buffered { decodeModern(bufferedFrame) }
            } else {
                if frameType == 0x01 || frameType == 0x02 {
                    undecodedFrames.append(frame)
                    undecodedFrames = Array(undecodedFrames.suffix(4))
                    if !hasTelemetry { connectionMessage = "蓝牙已连接 · 等待足够的数据识别通信协议" }
                }
                verifyPendingWrite()
                return
            }
        }
        decodeModern(frame)
        // Schema fields take precedence for the exact identified product family.
        updateOriginalFields(frame)
    }

    private func decodeModern(_ frame: Data) {
        guard let decoded = JKModernCodec.parse(frame: frame, variant: detectedProtocol) else { log("帧布局与当前协议不匹配"); return }
        if var value = decoded.status {
            if let info = deviceInfo {
                value.deviceModel = info.model; value.hardwareVersion = info.hardware
                value.firmwareVersion = info.firmware; value.deviceSN = info.serial
                value.manufactureDate = info.manufactureDate
            }
            status = value
            hasTelemetry = !requiresDevicePassword; lastUpdate = Date()
            reconnectAttempts = 0
            sessionTimeout?.invalidate()
            connectionMessage = requiresDevicePassword ? "已连接 · 请在设备页确认蓝牙连接密码" : "实时通信正常 · \(detectedProtocol.displayName)"
        }
        if var value = decoded.settings, originalSchemaName.isEmpty {
            value.extendedValues.merge(settings.extendedValues, uniquingKeysWith: { current, _ in current })
            value.originalValues = settings.originalValues
            settings = value
            hasSettings = true
        }
        settings.extendedValues.merge(JKParameterCatalog.decode(frame: frame, variant: detectedProtocol), uniquingKeysWith: { _, new in new })
        verifyPendingWrite()
    }

    private func applyInfo(_ info: JKDeviceInfo) {
        status.deviceModel = info.model; status.hardwareVersion = info.hardware
        status.firmwareVersion = info.firmware; status.deviceSN = info.serial
        status.manufactureDate = info.manufactureDate
        status.uptimeSeconds = info.uptimeSeconds
        log("已读取设备身份：\(info.model) · HW \(info.hardware) · FW \(info.firmware)")
    }




    public func originalCommandSupported(_ command: UInt8) -> Bool {
        guard !originalSchemaName.isEmpty else { return false }
        if let flags = originalRawInfo["cmdSupportFlags"] {
            return JKOriginalSchema.bitEnabled(flags.bytes, index: Int(command))
        }
        return command == 0x9B || command == 0x9C || command == 0xA0 || command == 0x9F
    }

    public func changeDeviceText(kind: JKDeviceTextKind, value: String, oldPassword: String = "") {
        guard canWrite, originalCommandSupported(kind.register),
              pendingWrite == nil, writes.isEmpty, !exclusiveMutationPending else {
            fail("设备未开放此操作，或仍有修改待确认"); return
        }
        if kind == .bluetoothPassword {
            guard let old = originalRawInfo[kind.key]?.text, old == oldPassword else { fail("当前蓝牙连接密码不匹配"); return }
        }
        do {
            let packet = try JKOriginalCommands.text(value, kind: kind)
            pendingIdentity = (kind, value, Date().addingTimeInterval(8))
            commandMessage = "正在修改\(kind.title)，等待设备信息回读"
            enqueue(packet)
            let token = sessionID
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self, self.sessionID == token else { return }; self.request(.requestDeviceInfo)
            }
        } catch { fail("请输入1至12位英文字母、数字或ASCII符号") }
    }


    public func calibrateSensor(voltage: Bool, reference: Double) {
        let command: UInt8 = voltage ? 0x64 : 0x67
        guard canWrite, originalCommandSupported(command), pendingWrite == nil, writes.isEmpty, !exclusiveMutationPending,
              reference.isFinite, (voltage ? 1.0...200.0 : 0.0...2000.0).contains(reference) else {
            fail("设备未开放此校准或参考数值超出原版允许范围"); return
        }
        pendingCalibration = (voltage, reference, Date().addingTimeInterval(8))
        commandMessage = "校准已发送，等待实时测量值回读"
        enqueue(JKModernCodec.command(register: command, value: UInt32((reference * 1000).rounded()), length: 4))
    }

    public func eraseAllDeviceData() {
        guard canWrite, originalCommandSupported(0xA3), pendingWrite == nil, writes.isEmpty, !exclusiveMutationPending else {
            fail("设备未开放清除数据操作"); return
        }
        pendingEraseDeadline = Date().addingTimeInterval(10)
        commandMessage = "清除数据指令已发送，等待设备历史计数回读"
        enqueue(JKModernCodec.command(register: 0xA3))
    }

    public func calibrateDeviceTime() {
        guard canWrite, originalCommandSupported(0x6C), pendingWrite == nil, writes.isEmpty, !exclusiveMutationPending else {
            fail("设备未开放时间校准，或尚未解锁修改"); return
        }
        do {
            let now = Date(); let packet = try JKOriginalCommands.timeCalibration(date: now)
            pendingClock = (UInt32(now.timeIntervalSince1970 - 1577836800), now.addingTimeInterval(8))
            commandMessage = "时间校准已发送，等待设备RTC回读"
            enqueue(packet)
        } catch { fail(error.localizedDescription) }
    }

    public var supportsDetailedLogs: Bool {
        originalCommandSupported(0xA7) && !JKOriginalSchema.fields(family: originalSchemaName, type: 6).isEmpty
    }
    public func requestDetailedLogs() {
        guard isConnected, supportsDetailedLogs, !isSimulatorMode else { fail("当前设备未开放详细历史下载"); return }
        detailedLogs = []; isDownloadingDetailedLogs = true; detailedLastPage = Date()
        detailedLogMessage = "正在请求详细历史"
        // Request the detailed history stream with a zero-length payload.
        enqueue(JKModernCodec.command(register: 0xA7))
    }
    public func cancelDetailedLogs() { isDownloadingDetailedLogs = false; detailedLogMessage = "下载已停止，保留 \(detailedLogs.count) 条记录" }
    private func receiveDetailedLogs(_ frame: Data) {
        guard isDownloadingDetailedLogs,
              let records = JKOriginalSchema.detailedLogs(frame, family: originalSchemaName) else { return }
        detailedLastPage = Date()
        var merged = Dictionary(detailedLogs.map { ($0.index, $0) }, uniquingKeysWith: { _, new in new })
        for record in records { merged[record.index] = record }
        detailedLogs = merged.values.sorted { $0.index < $1.index }
        let expected = originalRealtime.first(where: { $0.id == "detailLogsCount" })?.number ?? 0
        let complete = records.isEmpty || records.count < 12 || (expected > 0 && Double(detailedLogs.count) >= expected)
        detailedLogMessage = "已读取 \(detailedLogs.count) 条" + (expected > 0 ? " / \(Int(expected)) 条" : "") + (complete ? " · 下载完成" : " · 继续接收")
        if complete || detailedLogs.count >= 10000 { isDownloadingDetailedLogs = false }
    }
    public var detailedLogsCSV: String {
        let rows = detailedLogs.map { record -> String in
            let date = record.date.map { ISO8601DateFormatter().string(from: $0) } ?? ""
            let values = record.values.map { "\($0.id)=\($0.display)" }.joined(separator: ";")
            return "\(record.index),\(date),\(record.event),\(values)"
        }
        return (["index,timestamp,event,values"] + rows).joined(separator: "\n")
    }

    private func normalizeCommand(_ command: JKCommand) -> JKCommand {
        guard !originalSchemaName.isEmpty, !isSimulatorMode else { return command }
        var keys: [String] = []; var value: Double = 0
        switch command {
        case .setCharge(let v): keys = ["batChargeEn", "barChargeEnable"]; value = v ? 1 : 0
        case .setDischarge(let v): keys = ["batDischargeEn", "batDischargeEnable"]; value = v ? 1 : 0
        case .setBalance(let v): keys = ["balanEn", "equEnable"]; value = v ? 1 : 0
        case .setCellCount(let v): keys = ["cellCount"]; value = Double(v)
        case .setCapacity(let v): keys = ["capBatCell", "batCellCapacity"]; value = v
        case .setBalanceTriggerVoltage(let v): keys = ["volBalanTrig", "equTrigVol"]; value = v
        case .setBalanceMaxCurrent(let v): keys = ["curBalanMax", "equMaxCurrent"]; value = v
        case .setCellOvervoltageProtection(let v): keys = ["volCellOV", "cellFullVol"]; value = v
        case .setCellOvervoltageRecovery(let v): keys = ["volCellOVPR", "cellFullVolRecovery"]; value = v
        case .setCellUndervoltageProtection(let v): keys = ["volCellUV", "cellUnderVol"]; value = v
        case .setCellUndervoltageRecovery(let v): keys = ["volCellUVPR", "cellUnderVolRecovery"]; value = v
        case .setContinuousChargeCurrent(let v): keys = ["timBatCOC", "batChargeMaxCurrent"]; value = v
        case .setContinuousDischargeCurrent(let v): keys = ["timBatDcOC", "batDischargeMaxCurrent"]; value = v
        case .setMosOverTemperature(let v): keys = ["tmpMosOT"]; value = v
        case .setChargeOverTemperature(let v): keys = ["tmpBatCOT", "batChargeHTempProtect"]; value = v
        case .setDischargeOverTemperature(let v): keys = ["tmpBatDcOT", "batDischargeHTempProtect"]; value = v
        case .setChargeUnderTemperature(let v): keys = ["tmpBatCUT", "batChargeLTempProtect"]; value = v
        case .setDischargeUnderTemperature(let v): keys = ["tmpBatDCHUT"]; value = v
        default: return command
        }
        guard let key = keys.first(where: { JKOriginalSchema.writableField(key: $0, family: originalSchemaName) != nil }) else { return command }
        return .setOriginalParameter(family: originalSchemaName, key: key, value: value)
    }

    private func applyOriginalSettings(_ fields: [String: JKOriginalValue]) {
        func number(_ keys: String...) -> Double { keys.compactMap { fields[$0]?.number }.first ?? .nan }
        let count = number("cellCount")
        guard count.isFinite, (1...32).contains(count) else { return }
        settings.cellCount = Int(count)
        settings.batteryCapacity = number("capBatCell", "batCellCapacity")
        settings.balanceTriggerVoltage = number("volBalanTrig", "equTrigVol")
        settings.balanceMaxCurrent = number("curBalanMax", "equMaxCurrent")
        settings.cellOvervoltageProtection = number("volCellOV", "cellFullVol")
        settings.cellOvervoltageRecovery = number("volCellOVPR", "cellFullVolRecovery")
        settings.cellUndervoltageProtection = number("volCellUV", "cellUnderVol")
        settings.cellUndervoltageRecovery = number("volCellUVPR", "cellUnderVolRecovery")
        settings.continuousChargeCurrent = number("timBatCOC", "batChargeMaxCurrent")
        settings.continuousDischargeCurrent = number("timBatDcOC", "batDischargeMaxCurrent")
        settings.mosOverTempProtection = number("tmpMosOT")
        settings.batteryChargeOverTempProtection = number("tmpBatCOT", "batChargeHTempProtect")
        settings.batteryDischargeOverTempProtection = number("tmpBatDcOT", "batDischargeHTempProtect")
        settings.batteryChargeUnderTempProtection = number("tmpBatCUT", "batChargeLTempProtect")
        settings.batteryDischargeUnderTempProtection = number("tmpBatDCHUT")
        settings.isChargeEnabled = number("batChargeEn", "barChargeEnable") == 1
        settings.isDischargeEnabled = number("batDischargeEn", "batDischargeEnable") == 1
        settings.isBalanceEnabled = number("balanEn", "equEnable") == 1
        let switches = number("switchStatus")
        settings.isHeatingEnabled = switches.isFinite && UInt32(clamping: Int(switches)) & 1 != 0
        hasSettings = true
    }

    public func originalSwitchAvailable(key: String, bit: Int) -> Bool {
        guard let field = JKOriginalSchema.fields(family: originalSchemaName, type: 4).first(where: { $0.key == key && $0.kind == "bm" }),
              originalRawSettings[key] != nil, bit >= 0, bit < field.count, field.options?[String(bit)] != nil else { return false }
        let command = field.command + bit
        if let flags = originalRawInfo["cmdSupportFlags"], !JKOriginalSchema.bitEnabled(flags.bytes, index: command) { return false }
        if let flags = originalRawSettings["enableFlags"], !JKOriginalSchema.bitEnabled(flags.bytes, index: command) { return false }
        return true
    }
    public func setOriginalSwitch(key: String, bit: Int, enabled: Bool) {
        send(command: .setOriginalSwitch(family: originalSchemaName, key: key, bit: bit, enabled: enabled))
    }

    public func originalCanEdit(_ key: String) -> Bool {
        guard let field = JKOriginalSchema.writableField(key: key, family: originalSchemaName),
              originalRawSettings[key] != nil else { return false }
        if let flags = originalRawInfo["cmdSupportFlags"], !JKOriginalSchema.bitEnabled(flags.bytes, index: field.command) { return false }
        if let flags = originalRawSettings["enableFlags"], !JKOriginalSchema.bitEnabled(flags.bytes, index: field.command) { return false }
        return true
    }

    public func setOriginalParameter(key: String, value: Double) {
        send(command: .setOriginalParameter(family: originalSchemaName, key: key, value: value))
    }

    private func updateOriginalFields(_ frame: Data) {
        guard !originalSchemaName.isEmpty else { return }
        let values = JKOriginalSchema.decode(frame, family: originalSchemaName)
        guard !values.isEmpty else { return }
        let type = frame[4]
        let dictionary = Dictionary(values.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        if type == 3 {
            originalRawInfo = dictionary
            if let pending = pendingIdentity, dictionary[pending.kind.key]?.text == pending.value {
                pendingIdentity = nil
                if pending.kind == .settingsPassword { credentials.confirmedChange(pending.value, kind: .settings) }
                if pending.kind == .bluetoothPassword { credentials.confirmedChange(pending.value, kind: .connection) }
                syncCredentialState()
                commandMessage = "设备已回传确认新的\(pending.kind.title)"
            }
            originalDeviceInfo = values.filter { !$0.field.isPrivate && !$0.id.hasSuffix("Flags") }
        } else if type == 1 {
            if var preset = pendingPreset { preset.settingsRead = true; pendingPreset = preset }
            originalRawSettings = dictionary
            originalSettings = values.filter { !$0.id.hasSuffix("Flags") }
            settings.originalValues = dictionary.compactMapValues(\.number)
            applyOriginalSettings(dictionary)
        } else if type == 2 {
            if let clock = pendingClock, let actual = dictionary["rtcCounter"]?.number,
               abs(actual - Double(clock.seconds)) <= 15 {
                pendingClock = nil; commandMessage = "设备时间校准已由回读确认"
            }
            originalRealtime = values.filter { !$0.id.hasSuffix("Flags") }
            if let parsed = originalStatus(dictionary) {
                status = parsed; hasTelemetry = !requiresDevicePassword; lastUpdate = Date()
                connectionMessage = requiresDevicePassword ? "已连接 · 请在设备页确认蓝牙连接密码" : "实时通信正常 · \(originalSchemaName)"
                sessionTimeout?.invalidate()
            }
        }
    }

    private func originalStatus(_ fields: [String: JKOriginalValue]) -> JKBMSStatus? {
        guard let cells = fields["cellVol"]?.numbers, !cells.isEmpty,
              cells.allSatisfy({ $0.isFinite && (0...6).contains($0) }),
              let last = cells.lastIndex(where: { $0 > 0.1 }) else { return nil }
        func number(_ key: String) -> Double { fields[key]?.number ?? .nan }
        func unsigned(_ key: String) -> UInt32 { let v = number(key); return v.isFinite && v >= 0 && v <= Double(UInt32.max) ? UInt32(v) : 0 }
        let temps = fields["batTemp"]?.numbers ?? []
        let switchMask = unsigned("sysMosStatus")
        let current = number("batCurrent")
        let cycleCount = unsigned("socCycleCount")
        let info = deviceInfo
        var result = JKBMSStatus(cellVoltages: Array(cells.prefix(last + 1)),
            cellWireResistances: Array((fields["cellWireRes"]?.numbers ?? []).prefix(last + 1)),
            batteryVoltage: number("batVol"), batteryCurrent: current,
            soc: number("socRelativeStateOfCharge"), remainingCapacity: number("socCapabilityRemain"),
            totalCapacity: number("socFullChargeCapacity"), cycleCount: Int(cycleCount),
            totalCycleCapacity: number("socCycleCapacity"),
            mosTemperature: fields["tempMos"]?.number ?? fields["sysMosTemp"]?.number ?? .nan,
            batteryT1: fields["batTemp1"]?.number ?? temps.first ?? .nan,
            batteryT2: fields["batTemp2"]?.number ?? (temps.count > 1 ? temps[1] : .nan),
            ambientTemperature: .nan,
            isChargeEnabled: fields["chargeStatus"]?.number.map { $0 != 0 } ?? (switchMask & 1 != 0),
            isDischargeEnabled: fields["dischargeStatus"]?.number.map { $0 != 0 } ?? (switchMask & 2 != 0),
            isBalanceEnabled: unsigned("equStatus") != 0,
            isHeatingEnabled: unsigned("heatingStatus") != 0 || unsigned("heatStatus") != 0,
            deviceModel: info?.model ?? "", hardwareVersion: info?.hardware ?? "",
            firmwareVersion: info?.firmware ?? "", deviceSN: info?.serial ?? "",
            uptimeSeconds: unsigned("runtime"), manufactureDate: info?.manufactureDate ?? "")
        if !result.batteryVoltage.isFinite { result.batteryVoltage = result.cellVoltages.reduce(0, +) }
        // The original schema's wire resistance scale is in mΩ, unlike the upstream Ohm labels.
        if fields["cellWireRes"]?.field.unit == "Ω" {
            result.cellWireResistances = result.cellWireResistances.map { $0 * 1000 }
        }
        result.hasCycleCount = fields["socCycleCount"] != nil
        result.balanceCurrent = number("equCurrent")
        result.stateOfHealth = number("sOCSOH")
        result.isEmergencyEnabled = unsigned("timeEmerg") > 0
        result.extraTemperatures = ["batTemp3", "batTemp4", "batTemp5"].map(number)
        if let present = fields["tempSensorAbsent"]?.number, present.isFinite {
            let bits = UInt32(clamping: Int(present))
            if bits & 1 == 0 { result.mosTemperature = .nan }
            if bits & 2 == 0 { result.batteryT1 = .nan }
            if bits & 4 == 0 { result.batteryT2 = .nan }
            for i in 0..<3 where bits & (1 << (i + 3)) == 0 { result.extraTemperatures[i] = .nan }
        }
        if let alarm = fields["sysAlarm"], let mask = alarm.number, mask.isFinite, mask >= 0 {
            let bits = UInt64(mask)
            result.alarms = (0..<min(alarm.field.size * 8, 32)).compactMap { bit in
                guard bits & (UInt64(1) << bit) != 0 else { return nil }
                return JKBMSAlarm(bit: bit, name: alarm.field.options?[String(bit)] ?? "设备告警 \(bit)", severity: .critical)
            }
        }
        result.recalculateStats()
        if let calibration = pendingCalibration {
            let actual = calibration.voltage ? result.batteryVoltage : abs(result.batteryCurrent)
            if actual.isFinite, abs(actual - calibration.value) <= (calibration.voltage ? 0.2 : 1) {
                pendingCalibration = nil; commandMessage = "设备测量值已回读，与校准参考值一致"
            }
        }
        if let preset = pendingPreset, preset.settingsRead, number("batteryType") == Double(preset.chemistry) {
            pendingPreset = nil; commandMessage = "设备整组参数和电池类型已回读，一键配置已确认"
        }
        if pendingEraseDeadline != nil, number("detailLogsCount") == 0 {
            pendingEraseDeadline = nil; detailedLogs = []; commandMessage = "设备详细历史计数已回读为0"
        }
        return result
    }

    private func fail(_ message: String) { lastErrorMessage = message; log("提示：\(message)") }
    private func log(_ message: String) {
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm:ss"
        let line = "[\(formatter.string(from: Date()))] \(message)"
        diagnosticLog = (diagnosticLog.components(separatedBy: "\n") + [line]).suffix(180).joined(separator: "\n")
        if persistDiagnostics, let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? diagnosticLog.write(to: directory.appendingPathComponent("jkbms-ble-diagnostics.log"), atomically: true, encoding: .utf8)
        }
    }
}

extension JKBluetoothManager: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state
        guard !isSimulatorMode else { return }
        if central.state == .poweredOn { if !isConnected && !isConnecting { startScan() } }
        else {
            disconnect()
            switch central.state {
            case .unauthorized: connectionMessage = "蓝牙访问未授权，请前往系统设置允许"
            case .poweredOff: connectionMessage = "蓝牙已关闭，请开启手机蓝牙"
            case .unsupported: connectionMessage = "此设备不支持蓝牙低功耗通信"
            default: connectionMessage = "等待蓝牙就绪"
            }
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard !isSimulatorMode else { return }
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "未命名 BLE 设备"
        let advertised = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []) +
            (advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] ?? [])
        let lower = name.lowercased()
        guard advertised.contains(Self.serviceUUID) || ["jk", "bms", "b1a", "b2a", "bd6", "pb1", "pb2", "b5a"].contains(where: lower.contains) else { return }
        peripherals[peripheral.identifier] = peripheral
        let device = JKDevice(id: peripheral.identifier, name: name, rssi: RSSI.intValue, lastSeen: Date())
        if let index = discoveredDevices.firstIndex(where: { $0.id == device.id }) {
            discoveredDevices[index].rssi = device.rssi; discoveredDevices[index].lastSeen = device.lastSeen
            discoveredDevices[index].name = name
        } else { discoveredDevices.append(device); log("发现 \(name)") }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral == activePeripheral else { return }
        connectionMessage = "设备已连接 · 正在发现蓝牙服务"
        peripheral.discoverServices([Self.serviceUUID])
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral == activePeripheral else { return }
        resetSession(); activePeripheral = nil; connectedDevice = nil
        connectionMessage = "连接失败，请重试"
        fail(error?.localizedDescription ?? "设备连接失败")
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral == activePeripheral else { return }
        let reconnect = !userDisconnected && !isSimulatorMode && reconnectAttempts < 3 && central.state == .poweredOn
        let name = connectedDevice?.name ?? peripheral.name ?? "JK-BMS"
        resetSession(); activePeripheral = nil
        if reconnect {
            reconnectAttempts += 1
            connectionMessage = "连接已断开 · 正在准备第 \(reconnectAttempts) 次重连"
            let token = sessionID
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, self.sessionID == token, !self.userDisconnected, !self.isSimulatorMode else { return }
                self.beginConnection(peripheral, name: name)
            }
        } else { connectedDevice = nil; connectionMessage = "设备已断开" }
        if let error { log("断开原因：\(error.localizedDescription)") }
    }
}

extension JKBluetoothManager: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral == activePeripheral else { return }
        if let error { fail(error.localizedDescription); centralManager?.cancelPeripheralConnection(peripheral); return }
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            fail("设备未提供兼容的 FFE0 服务"); centralManager?.cancelPeripheralConnection(peripheral); return
        }
        connectionMessage = "正在发现读写特征"
        peripheral.discoverCharacteristics([Self.notifyUUID], for: service)
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral == activePeripheral else { return }
        if let error { fail(error.localizedDescription); return }
        // Some JK modules expose two FFE1 characteristics. Select each by properties, not only UUID.
        let characteristics = service.characteristics?.filter { $0.uuid == Self.notifyUUID } ?? []
        writeCharacteristic = characteristics.first(where: { $0.properties.contains(.writeWithoutResponse) }) ??
            characteristics.first(where: { $0.properties.contains(.write) })
        notifyCharacteristic = characteristics.first(where: { $0.properties.contains(.notify) || $0.properties.contains(.indicate) })
        guard writeCharacteristic != nil, let notify = notifyCharacteristic else {
            fail("缺少可用的读写或通知特征"); centralManager?.cancelPeripheralConnection(peripheral); return
        }
        connectionMessage = "正在订阅实时数据通知"
        peripheral.setNotifyValue(true, for: notify)
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral == activePeripheral, characteristic === notifyCharacteristic else { return }
        if let error { fail(error.localizedDescription); centralManager?.cancelPeripheralConnection(peripheral); return }
        guard characteristic.isNotifying else { fail("设备未启用通知，无法接收实时数据"); return }
        beginHandshake()
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral == activePeripheral, characteristic === notifyCharacteristic else { return }
        if let error { fail(error.localizedDescription); return }
        guard let value = characteristic.value else { return }
        for frame in assembler.append(value) { receive(frame) }
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral == activePeripheral else { return }
        awaitingWriteResponse = false
        if let error { abortWrites("蓝牙写入失败：\(error.localizedDescription)") }
        else { pumpTransport() }
    }

    public func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        guard peripheral == activePeripheral else { return }; pumpTransport()
    }
}
