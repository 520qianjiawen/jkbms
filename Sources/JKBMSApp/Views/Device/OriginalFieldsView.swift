import SwiftUI
#if SWIFT_PACKAGE
import JKBMSCore
#endif

struct OriginalFieldsView: View {
    @ObservedObject private var bt = JKBluetoothManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selection = 0
    @State private var editing: SettingsView.EditingField?
    private var values: [JKOriginalValue] {
        switch selection { case 1: return bt.originalSettings; case 2: return bt.originalDeviceInfo; default: return bt.originalRealtime }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(bt.originalSchemaName.isEmpty ? "等待自动读取设备型号与协议" : "设备协议：\(bt.originalSchemaName)")
                        .font(.subheadline)
                    Text("字段依据原版 App 协议定义读取。未回传或被设备禁用的字段不作为可修改参数。")
                        .font(.caption).foregroundColor(.secondary)
                    Picker("数据类型", selection: $selection) {
                        Text("实时").tag(0); Text("全部参数").tag(1); Text("设备信息").tag(2)
                    }.pickerStyle(.segmented)
                }
                if values.isEmpty {
                    Text("尚未收到此类设备数据").foregroundColor(.secondary)
                } else {
                    ForEach(values) { value in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(value.field.title).font(.subheadline)
                                Spacer()
                                if selection == 1, let number = value.number, number.isFinite,
                                   let field = JKOriginalSchema.writableField(key: value.id, family: bt.originalSchemaName) {
                                    Button("修改") {
                                        editing = SettingsView.EditingField(id: field.key, title: field.title,
                                            currentValue: number, unit: field.unit,
                                            step: pow(10, -Double(min(field.decimals, 3))),
                                            range: (field.minimum ?? 0)...(field.key == "cellCount" ? Double(bt.maximumCellCount) : (field.maximum ?? 0))) {
                                                bt.setOriginalParameter(key: field.key, value: $0)
                                            }
                                    }.buttonStyle(.bordered)
                                        .disabled(!bt.canWrite || !bt.originalCanEdit(value.id))
                                }
                            }
                            if selection == 1, value.field.kind == "bm", let options = value.field.options {
                                ForEach(options.keys.compactMap(Int.init).sorted(), id: \.self) { bit in
                                    let label = (options[String(bit)] ?? "开关 \(bit)").components(separatedBy: ":").first ?? "开关"
                                    Toggle(label, isOn: Binding(get: {
                                        guard let number = value.number, number.isFinite, number >= 0, number <= Double(UInt32.max) else { return false }
                                        return UInt32(number) & (1 << bit) != 0
                                    }, set: { bt.setOriginalSwitch(key: value.id, bit: bit, enabled: $0) }))
                                    .disabled(!bt.canWrite || !bt.originalSwitchAvailable(key: value.id, bit: bit))
                                }
                            }
                            Text(value.display).font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary).textSelection(.enabled)
                        }.padding(.vertical, 3)
                    }
                }
                if !bt.commandMessage.isEmpty { Section("操作状态") { Text(bt.commandMessage) } }
            }
            .navigationTitle("完整设备数据")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
            .sheet(item: $editing) { ValueEditSheet(field: $0) }
        }
    }
}
