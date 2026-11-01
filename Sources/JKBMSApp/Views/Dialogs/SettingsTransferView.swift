import SwiftUI
import UniformTypeIdentifiers
#if SWIFT_PACKAGE
import JKBMSCore
#endif

struct JKSettingsJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let value = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
        text = value
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

struct JKSettingsImportPreview: Identifiable {
    let id = UUID()
    let root: [String: Any]
    let settings: [String: Double]
    let sourceName: String
    var protocolName: String { root["protocol"] as? String ?? "" }
    var deviceModel: String { root["deviceModel"] as? String ?? "未知型号" }
    var cellCount: Int { root["cellCount"] as? Int ?? 0 }
    var chemistry: String { root["batteryChemistry"] as? String ?? "未指定" }

    init(url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let attributes = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard attributes.isRegularFile == true, (attributes.fileSize ?? 0) <= 131_072 else {
            throw JKSettingsImportError.invalid("请选择不超过 128 KB 的 JSON 参数文件。")
        }
        let data = try Data(contentsOf: url)
        let object: Any
        if url.pathExtension.lowercased() == "jkcfg" { object = try JKOriginalBackup(data: data).previewObject }
        else { object = try JSONSerialization.jsonObject(with: data) }
        guard let root = object as? [String: Any],
              root["schemaVersion"] as? Int == 1,
              let protocolName = root["protocol"] as? String,
              JKProtocolVariant(rawValue: protocolName) != nil,
              let values = root["settings"] as? [String: Any], !values.isEmpty,
              let count = root["cellCount"] as? Int, (4...32).contains(count) else {
            throw JKSettingsImportError.invalid("文件不是兼容的保护板参数备份。需要版本、协议、串数和参数列表。")
        }
        var numbers: [String: Double] = [:]
        for (key, value) in values {
            guard let number = value as? NSNumber, String(cString: number.objCType) != "c", number.doubleValue.isFinite else {
                throw JKSettingsImportError.invalid("参数 \(key) 不是有效数值。")
            }
            let isOriginal = key.hasPrefix("original.") && JKOriginalSchema.families.contains(where: {
                JKOriginalSchema.writableField(key: String(key.dropFirst(9)), family: $0) != nil
            })
            let known = isOriginal || JKSettingsLabels.basic[key] != nil || JKParameterCatalog.definitions.contains { $0.id == key }
            guard known else { throw JKSettingsImportError.invalid("文件包含无法识别的参数：\(key)。") }
            numbers[key] = number.doubleValue
        }
        if let parameterCount = numbers["cellCount"], parameterCount != Double(count) {
            throw JKSettingsImportError.invalid("文件中的电芯串数与备份信息不一致，未导入。")
        }
        self.root = root
        self.settings = numbers
        self.sourceName = url.lastPathComponent
    }

    func json(chemistry: String) throws -> String {
        var updated = root
        updated["batteryChemistry"] = chemistry
        let data = try JSONSerialization.data(withJSONObject: updated, options: [.prettyPrinted, .sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        return text
    }
}

enum JKSettingsImportError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { switch self { case .invalid(let text): return text } }
}

enum JKSettingsLabels {
    static let basic: [String: (title: String, unit: String)] = [
        "cellCount": ("电芯串数", "S"), "batteryCapacity": ("额定容量", "Ah"),
        "balanceTriggerVoltage": ("均衡触发压差", "V"), "balanceMaxCurrent": ("最大均衡电流", "A"),
        "cellOvervoltageProtection": ("单体过压保护", "V"), "cellOvervoltageRecovery": ("单体过压恢复", "V"),
        "cellUndervoltageProtection": ("单体欠压保护", "V"), "cellUndervoltageRecovery": ("单体欠压恢复", "V"),
        "continuousChargeCurrent": ("持续充电电流限制", "A"), "continuousDischargeCurrent": ("持续放电电流限制", "A"),
        "mosOverTempProtection": ("MOS 过温保护", "°C"), "batteryChargeOverTempProtection": ("充电过温保护", "°C"),
        "batteryDischargeOverTempProtection": ("放电过温保护", "°C"), "batteryChargeUnderTempProtection": ("充电低温保护", "°C"),
        "batteryDischargeUnderTempProtection": ("放电低温保护", "°C")
    ]
    static func label(_ id: String) -> (title: String, unit: String) {
        if let label = basic[id] { return label }
        if let definition = JKParameterCatalog.definitions.first(where: { $0.id == id }) { return (definition.title, definition.unit) }
        if id.hasPrefix("original.") {
            for family in JKOriginalSchema.families {
                if let field = JKOriginalSchema.writableField(key: String(id.dropFirst(9)), family: family) { return (field.title, field.unit) }
            }
        }
        return (id, "")
    }
}

struct JKSettingsImportPreviewView: View {
    let preview: JKSettingsImportPreview
    @ObservedObject private var bt = JKBluetoothManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var chemistry = ""
    @State private var customChemistry = ""
    @State private var confirmed = false
    @State private var showingConfirmation = false
    @State private var errorText = ""
    private let chemistries = ["磷酸铁锂 LiFePO4", "三元锂电 Li-ion", "钛酸锂电 LTO", "其他"]

    private var confirmedChemistry: String {
        chemistry == "其他" ? customChemistry.trimmingCharacters(in: .whitespacesAndNewlines) : chemistry
    }
    private var compatible: Bool {
        let originalVersionMatches = (preview.root["sourceFirmware"] as? String).map {
            $0 == bt.status.firmwareVersion && preview.deviceModel == bt.status.deviceModel
        } ?? true
        return originalVersionMatches && preview.protocolName == bt.detectedProtocol.rawValue && preview.cellCount == bt.settings.cellCount
    }

    private func previewValue(_ key: String, unit: String) -> String {
        let value = preview.settings[key] ?? .nan
        if let definition = JKParameterCatalog.definitions.first(where: { $0.id == key }) {
            if definition.isSwitch { return value == 0 ? "关闭" : "开启" }
            if let index = Int(exactly: value.rounded()), let label = definition.options?[index] { return label }
        }
        return JKDisplayValue.number(value, format: unit == "V" ? "%.3f" : "%.2f") + (unit.isEmpty ? "" : " " + unit)
    }

    var body: some View {
        NavigationView {
            Form {
                Section("备份内容") {
                    LabeledContent("文件", value: preview.sourceName)
                    LabeledContent("来源设备", value: preview.deviceModel)
                    LabeledContent("来源协议", value: JKProtocolVariant(rawValue: preview.protocolName)?.displayName ?? preview.protocolName)
                    LabeledContent("来源串数", value: "\(preview.cellCount) S")
                    LabeledContent("记录的电芯类型", value: preview.chemistry)
                    LabeledContent("当前设备", value: bt.status.deviceModel)
                    LabeledContent("当前串数", value: "\(bt.settings.cellCount) S")
                    if !compatible {
                        Text("备份协议或电芯串数与当前设备不一致，不能导入。")
                            .font(.subheadline).foregroundColor(.red)
                    }
                }
                Section("将写入的参数（\(preview.settings.count) 项）") {
                    ForEach(preview.settings.keys.sorted(), id: \.self) { key in
                        let label = JKSettingsLabels.label(key)
                        LabeledContent(label.title, value: previewValue(key, unit: label.unit))
                            .font(.subheadline)
                    }
                }
                Section("确认当前电池") {
                    Picker("当前电芯类型", selection: $chemistry) {
                        Text("请选择").tag("")
                        ForEach(chemistries, id: \.self) { Text($0).tag($0) }
                    }
                    if chemistry == "其他" { TextField("填写电芯类型", text: $customChemistry) }
                    Toggle("我已核对电芯类型与上述参数", isOn: $confirmed)
                    Text("确认后逐项写入，并通过设备回读核实；失败会停止后续写入。")
                        .font(.caption).foregroundColor(.secondary)
                }
                Section {
                    Button("确认导入并写入保护板") { showingConfirmation = true }
                        .disabled(!bt.canWrite || !compatible || !confirmed || confirmedChemistry.isEmpty)
                    if !errorText.isEmpty { Text(errorText).foregroundColor(.red).font(.caption) }
                }
            }
            .navigationTitle("导入参数预览")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
            .alert("写入这份参数备份？", isPresented: $showingConfirmation) {
                Button("写入 \(preview.settings.count) 项参数", role: .destructive) {
                    do {
                        let text = try preview.json(chemistry: confirmedChemistry)
                        bt.importSettingsJSON(text)
                        dismiss()
                    } catch { errorText = error.localizedDescription }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("当前电芯：\(confirmedChemistry)。请保持保护板连接，等待所有参数回读确认。")
            }
        }
    }
}

struct JKOriginalBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [UTType(filenameExtension: "jkcfg") ?? .data] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
