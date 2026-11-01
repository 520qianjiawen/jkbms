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
        self._value = State(initialValue: field.currentValue.isFinite ? min(max(field.currentValue, field.range.lowerBound), field.range.upperBound) : field.range.lowerBound)
    }

    private var isValid: Bool {
        guard value.isFinite, field.range.contains(value), field.step > 0 else { return false }
        let ticks = value / field.step
        return abs(ticks - ticks.rounded()) < 0.00001 && field.validate(value)
    }

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
                    if let hint = field.hint { Text(hint).font(.caption).foregroundColor(.secondary) }
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
        String(format: field.step >= 1 ? "%.0f %@" : (field.step >= 0.1 ? "%.1f %@" : (field.step >= 0.01 ? "%.2f %@" : "%.3f %@")), number, field.unit)
    }
}
