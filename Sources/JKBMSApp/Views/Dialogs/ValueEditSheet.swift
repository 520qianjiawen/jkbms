import SwiftUI
#if SWIFT_PACKAGE
import JKBMSCore
#endif

public struct ValueEditSheet: View {
    public let field: SettingsView.EditingField
    @Environment(\.dismiss) private var dismiss
    @State private var value: Double

    public init(field: SettingsView.EditingField) {
        self.field = field
        self._value = State(initialValue: field.currentValue)
    }

    private var isValid: Bool { value.isFinite && field.range.contains(value) }

    public var body: some View {
        NavigationView {
            Form {
                Section(field.title) {
                    LabeledContent("设备当前值", value: formatted(field.currentValue))
                    HStack {
                        Text("新数值")
                        Spacer()
                        TextField("数值", value: $value, format: .number.precision(.fractionLength(0...3)))
                            .multilineTextAlignment(.trailing)
                            .frame(minWidth: 80, maxWidth: 160)
                        Text(field.unit).foregroundColor(.secondary)
                    }
                    Stepper("每次调整 \(formatted(field.step))", value: $value, in: field.range, step: field.step)
                    Text("允许范围 \(formatted(field.range.lowerBound)) ～ \(formatted(field.range.upperBound))")
                        .font(.caption).foregroundColor(.secondary)
                }
                Section {
                    Text("发送后将回读保护板参数。只有回传值一致时才显示写入成功。")
                        .font(.caption).foregroundColor(.secondary)
                    Button("确认并发送到保护板") {
                        field.onSave(value)
                        dismiss()
                    }.disabled(!isValid)
                }
            }
            .navigationTitle("修改参数")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
        }
    }

    private func formatted(_ number: Double) -> String {
        String(format: field.unit == "V" ? "%.3f %@" : "%.1f %@", number, field.unit)
    }
}
