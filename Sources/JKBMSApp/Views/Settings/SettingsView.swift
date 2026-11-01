import SwiftUI
import UniformTypeIdentifiers
#if SWIFT_PACKAGE
import JKBMSCore
#endif

public struct SettingsView: View {
    @ObservedObject private var bt = JKBluetoothManager.shared
    @State private var showingPasswordDialog = false
    @State private var editingField: EditingField?
    @State private var pendingPreset: PresetSelection?
    @State private var showingOriginalExporter = false
    @State private var originalDocument = JKOriginalBackupDocument(data: Data())
    @State private var showingOriginalExportConfirmation = false
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var importPreview: JKSettingsImportPreview?
    @State private var transferError = ""
    @State private var exportDocument = JKSettingsJSONDocument(text: "{}")

    public struct EditingField: Identifiable {
        public let id: String
        public let title: String
        public let currentValue: Double
        public let unit: String
        public let step: Double
        public let range: ClosedRange<Double>
        public let hint: String?
        public let validate: (Double) -> Bool
        public let onSave: (Double) -> Void
        public init(id: String, title: String, currentValue: Double, unit: String, step: Double, range: ClosedRange<Double> = 0...100000, hint: String? = nil, validate: @escaping (Double) -> Bool = { _ in true }, onSave: @escaping (Double) -> Void) {
            self.id = id; self.title = title; self.currentValue = currentValue
            self.unit = unit; self.step = step; self.range = range; self.hint = hint; self.validate = validate; self.onSave = onSave
        }
    }

    private struct PresetSelection: Identifiable {
        let id: String
        let settings: JKBMSSettings
    }

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                section("参数状态") {
                    Text(bt.connectionMessage).font(.subheadline).foregroundColor(.secondary)
                    if !bt.hasSettings {
                        Text("尚未收到设备参数。连接保护板并等待读取完成后，才可查看或修改。")
                            .font(.subheadline)
                    } else {
                        HStack {
                            Label(bt.isAuthenticated || bt.isSimulatorMode ? "本应用修改已解锁" : "修改已锁定", systemImage: bt.isAuthenticated || bt.isSimulatorMode ? "lock.open" : "lock")
                                .font(.subheadline)
                            Spacer()
                            if !bt.isSimulatorMode && !bt.isAuthenticated {
                                Button("确认设置密码") { showingPasswordDialog = true }
                                    .buttonStyle(.bordered)
                            }
                        }
                        Text("数值以保护板回传为准。发送后等待回读确认，不会立即将新数值当作成功。")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    if !bt.commandMessage.isEmpty {
                        Text(bt.commandMessage).font(.subheadline).foregroundColor(JKTheme.primaryBlue)
                    }
                }
                if bt.hasSettings && !bt.requiresDevicePassword {
                    section("原版参数文件") {
                        Button("导出原版 .jkcfg 备份") { showingOriginalExportConfirmation = true }
                            .disabled(bt.originalBackupData == nil)
                        Text("兼容原版的备份包含设备信息和连接凭据，请妥善保存。JSON导出不含密码。导入时需核对型号、固件和参数。")
                            .font(.caption).foregroundColor(.secondary)
                    }

                    section("参数备份") {
                        HStack {
                            Button("导出 JSON 文件") {
                                exportDocument = JKSettingsJSONDocument(text: bt.exportSettingsJSON)
                                showingExporter = true
                            }.buttonStyle(.bordered)
                            Button("导入 JSON 文件") { showingImporter = true }
                                .buttonStyle(.bordered).disabled(!bt.canWrite)
                        }
                        Text("导入前会显示所有数值，并要求确认电芯类型。备份不包含密码。")
                            .font(.caption).foregroundColor(.secondary)
                        if !transferError.isEmpty { Text(transferError).font(.caption).foregroundColor(.red) }
                    }
                    section("电芯类型预设") {
                        HStack(spacing: 8) {
                            presetButton("磷酸铁锂", preset: .lifepo4Preset(cellCount: bt.settings.cellCount, capacity: bt.settings.batteryCapacity))
                            presetButton("三元锂电", preset: .liIonPreset(cellCount: bt.settings.cellCount, capacity: bt.settings.batteryCapacity))
                            presetButton("钛酸锂电", preset: .ltoPreset(cellCount: bt.settings.cellCount, capacity: bt.settings.batteryCapacity))
                        }
                        Text("支持原版一键的设备会载入整组厂家预设，其余设备逐项写入电压阈值。执行前请核对电芯类型。")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    section("基础配置") {
                        parameter("电芯串数", value: Double(bt.settings.cellCount), unit: "S", step: 1, range: 4...32) { .setCellCount(count: Int($0)) }
                        parameter("额定容量", value: bt.settings.batteryCapacity, unit: "Ah", step: 1, range: 1...10000) { .setCapacity(ah: $0) }
                        parameter("均衡触发压差", value: bt.settings.balanceTriggerVoltage, unit: "V", step: 0.001, range: 0.001...1) { .setBalanceTriggerVoltage(volts: $0) }
                        parameter("最大均衡电流", value: bt.settings.balanceMaxCurrent, unit: "A", step: 0.1, range: 0.1...10) { .setBalanceMaxCurrent(amps: $0) }
                        parameter("持续充电电流限制", value: bt.settings.continuousChargeCurrent, unit: "A", step: 1, range: 1...1000) { .setContinuousChargeCurrent(amps: $0) }
                        parameter("持续放电电流限制", value: bt.settings.continuousDischargeCurrent, unit: "A", step: 1, range: 1...1000) { .setContinuousDischargeCurrent(amps: $0) }
                    }
                    section("单体电压保护") {
                        parameter("过压保护", value: bt.settings.cellOvervoltageProtection, unit: "V", step: 0.01, range: 1...5) { .setCellOvervoltageProtection(volts: $0) }
                        parameter("过压恢复", value: bt.settings.cellOvervoltageRecovery, unit: "V", step: 0.01, range: 1...5) { .setCellOvervoltageRecovery(volts: $0) }
                        parameter("欠压保护", value: bt.settings.cellUndervoltageProtection, unit: "V", step: 0.01, range: 1...5) { .setCellUndervoltageProtection(volts: $0) }
                        parameter("欠压恢复", value: bt.settings.cellUndervoltageRecovery, unit: "V", step: 0.01, range: 1...5) { .setCellUndervoltageRecovery(volts: $0) }
                    }
                    section("温度保护") {
                        parameter("MOS 过温保护", value: bt.settings.mosOverTempProtection, unit: "°C", step: 1, range: 30...150) { .setMosOverTemperature(celsius: $0) }
                        parameter("充电过温保护", value: bt.settings.batteryChargeOverTempProtection, unit: "°C", step: 1, range: 0...100) { .setChargeOverTemperature(celsius: $0) }
                        parameter("放电过温保护", value: bt.settings.batteryDischargeOverTempProtection, unit: "°C", step: 1, range: 0...100) { .setDischargeOverTemperature(celsius: $0) }
                        parameter("充电低温保护", value: bt.settings.batteryChargeUnderTempProtection, unit: "°C", step: 1, range: -40...30) { .setChargeUnderTemperature(celsius: $0) }
                        parameter("放电低温保护", value: bt.settings.batteryDischargeUnderTempProtection, unit: "°C", step: 1, range: -40...30) { .setDischargeUnderTemperature(celsius: $0) }
                    }
                    advancedParameters
                }
            }.padding(16)
        }
        .background(Color.appSystemGroupedBackground)
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json, UTType(filenameExtension: "jkcfg") ?? .data]) { result in
            do { importPreview = try JKSettingsImportPreview(url: result.get()); transferError = "" }
            catch { transferError = error.localizedDescription }
        }
        .confirmationDialog("导出包含设备凭据的原版备份？", isPresented: $showingOriginalExportConfirmation, titleVisibility: .visible) {
            Button("保存原版备份") {
                if let data = bt.originalBackupData { originalDocument = JKOriginalBackupDocument(data: data); showingOriginalExporter = true }
            }
            Button("取消", role: .cancel) {}
        }
        .fileExporter(isPresented: $showingOriginalExporter, document: originalDocument,
                      contentType: UTType(filenameExtension: "jkcfg") ?? .data, defaultFilename: "JKBMS-原版参数.jkcfg") { result in
            if case .failure(let error) = result { transferError = error.localizedDescription }
        }
        .fileExporter(isPresented: $showingExporter, document: exportDocument, contentType: .json, defaultFilename: "JKBMS-参数备份.json") { result in
            if case .failure(let error) = result { transferError = error.localizedDescription }
        }
        .sheet(item: $importPreview) { preview in JKSettingsImportPreviewView(preview: preview) }
        .sheet(item: $editingField) { field in ValueEditSheet(field: field) }
        .sheet(isPresented: $showingPasswordDialog) {
            PasswordVerifyDialog(currentPassword: "", isVerified: Binding(get: { bt.isAuthenticated }, set: { _ in }))
        }
        .alert(item: $pendingPreset) { preset in
            Alert(
                title: Text("应用\(preset.id)预设？"),
                message: Text(presetMessage(preset.settings)),
                primaryButton: .default(Text("确认写入")) { bt.applyPreset(preset.settings) },
                secondaryButton: .cancel(Text("取消"))
            )
        }
    }

    private func presetMessage(_ settings: JKBMSSettings) -> String {
        let register: UInt8 = settings.cellOvervoltageProtection < 3 ? 0x6A : (settings.cellOvervoltageProtection < 4 ? 0x69 : 0x68)
        if bt.originalCommandSupported(register) {
            return "保护板会载入该电芯类型的整组厂家预设，包括保护阈值等参数。执行后将重新读取完整参数和电池类型，请先核对电芯类型与现有配置。"
        }
        return String(format: "过压保护 %.3f V，过压恢复 %.3f V，欠压保护 %.3f V，欠压恢复 %.3f V，均衡压差 %.3f V。\n这五项参数会逐项发送并回读确认。", settings.cellOvervoltageProtection, settings.cellOvervoltageRecovery, settings.cellUndervoltageProtection, settings.cellUndervoltageRecovery, settings.balanceTriggerVoltage)
    }

    private var advancedDefinitions: [JKParameterDefinition] {
        JKParameterCatalog.definitions(settings: bt.settings).filter {
            !$0.isSwitch && bt.settings.extendedValues[$0.id]?.isFinite == true &&
            (JKAlarmThresholds.channel(for: $0.id) == nil || bt.alarmFieldVisible($0.id))
        }
    }

    @ViewBuilder private var advancedParameters: some View {
        if !advancedDefinitions.isEmpty {
            section("高级参数") {
                ForEach(Array(Set(advancedDefinitions.map { $0.group })).sorted(), id: \.self) { group in
                    DisclosureGroup(group) {
                        ForEach(advancedDefinitions.filter { $0.group == group }) { definition in
                            if definition.options != nil {
                                choiceParameter(definition)
                            } else if JKAlarmThresholds.isThreshold(definition.id) {
                                alarmParameter(definition)
                            } else {
                                parameter(definition.title, value: bt.settings.extendedValues[definition.id] ?? .nan, unit: definition.unit, step: definition.step, range: definition.range) {
                                    .setParameter(id: definition.id, value: $0)
                                }
                            }
                        }
                    }.padding(.vertical, 5)
                }
            }
        }
    }

    private func choiceParameter(_ definition: JKParameterDefinition) -> some View {
        let value = bt.settings.extendedValues[definition.id] ?? .nan
        let current = Int(exactly: value.rounded()) ?? -1
        let options = JKParameterCatalog.availableOptions(id: definition.id, settings: bt.settings)
        let supported = JKAlarmThresholds.channel(for: definition.id) != nil
            ? bt.supports(command: .setParameter(id: definition.id, value: value))
            : JKParameterCatalog.supports(id: definition.id, variant: bt.detectedProtocol)
        return VStack(alignment: .leading, spacing: 4) {
            Picker(definition.title, selection: Binding(get: { current }, set: { selected in
                bt.send(command: .setParameter(id: definition.id, value: Double(selected)))
            })) {
                if options[current] == nil {
                    Text((definition.options?[current] ?? "未知选项 \(current)") + "（当前值）").tag(current)
                }
                ForEach(options.keys.sorted(), id: \.self) { key in
                    Text(options[key] ?? "\(key)").tag(key)
                }
            }
            .disabled(!bt.canWrite || options.isEmpty || !supported)
            if options.isEmpty {
                Text("设备未提供可写选项列表").font(.caption).foregroundColor(.secondary)
            }
            if let channel = JKAlarmThresholds.channel(for: definition.id), channel.id == definition.id {
                if let rule = JKAlarmThresholds.rule(source: current) {
                    Text("阈值单位：\(rule.unit)，范围：\(Int(rule.range.lowerBound)) ～ \(Int(rule.range.upperBound))；\(rule.relationship)")
                        .font(.caption).foregroundColor(.secondary)
                    if !bt.alarmFieldVisible(channel.triggerID) || !bt.alarmFieldVisible(channel.releaseID) {
                        Text("此设备未开放完整的触发值/恢复值设置").font(.caption).foregroundColor(.secondary)
                    }
                } else {
                    Text([0, 10, 12, 14].contains(current) ? "此触发源无需数值阈值" : "此触发源的阈值规则尚未确认，暂不开放数值修改")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        }.padding(.vertical, 6)
    }

    private func alarmParameter(_ definition: JKParameterDefinition) -> some View {
        let value = bt.settings.extendedValues[definition.id] ?? .nan
        let rule = JKAlarmThresholds.rule(id: definition.id, settings: bt.settings)
        return Button {
            guard let source = JKAlarmThresholds.source(for: definition.id, settings: bt.settings), let rule else { return }
            let snapshot = bt.settings
            let deviceID = bt.connectedDevice?.id
            editingField = EditingField(id: definition.id, title: definition.title, currentValue: value,
                unit: definition.unit, step: definition.step, range: definition.range, hint: rule.relationship,
                validate: { JKAlarmThresholds.isValueAvailable(id: definition.id, value: $0, settings: snapshot) }) {
                    bt.setAlarmThreshold(id: definition.id, value: $0, expectedSource: source, expectedDevice: deviceID)
                }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(definition.title).foregroundColor(.primary)
                    if rule?.contains(value) == false { Text("当前值超出此触发源范围，请修改").font(.caption).foregroundColor(.orange) }
                    else if !bt.supports(command: .setParameter(id: definition.id, value: value)) {
                        Text("设备未开放写入").font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
                Text(JKDisplayValue.number(value, format: "%.0f") + " " + definition.unit)
                    .font(.subheadline.monospaced()).foregroundColor(JKTheme.primaryBlue)
                Image(systemName: bt.canWrite ? "pencil" : "lock").font(.caption).foregroundColor(.secondary)
            }.padding(.vertical, 8)
        }.buttonStyle(.plain)
            .disabled(!bt.canWrite || !bt.supports(command: .setParameter(id: definition.id, value: value)))
    }

    private func parameter(_ title: String, value: Double, unit: String, step: Double, range: ClosedRange<Double>, command: @escaping (Double) -> JKCommand) -> some View {
        let supported = bt.supports(command: command(value))
        return Button {
            editingField = EditingField(id: title, title: title, currentValue: value, unit: unit, step: step, range: range) { newValue in
                bt.send(command: command(newValue))
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).foregroundColor(.primary)
                    if !supported { Text("当前协议不支持").font(.caption).foregroundColor(.secondary) }
                }
                Spacer()
                Text(JKDisplayValue.number(value, format: unit == "V" ? "%.3f" : "%.1f") + " " + unit)
                    .font(.subheadline.monospaced()).foregroundColor(JKTheme.primaryBlue)
                Image(systemName: bt.canWrite ? "pencil" : "lock").font(.caption).foregroundColor(.secondary)
            }.padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .disabled(!bt.canWrite || !supported)
    }

    private func presetButton(_ title: String, preset: JKBMSSettings) -> some View {
        Button(title) { pendingPreset = PresetSelection(id: title, settings: preset) }
            .font(.caption.bold()).buttonStyle(.bordered)
            .frame(maxWidth: .infinity).disabled(!bt.canWrite || !bt.supports(command: .setCellOvervoltageProtection(volts: preset.cellOvervoltageProtection)) || !bt.supports(command: .setCellUndervoltageProtection(volts: preset.cellUndervoltageProtection)))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }.padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appSecondarySystemGroupedBackground)
            .cornerRadius(12)
    }
}
