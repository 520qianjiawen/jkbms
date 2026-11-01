import SwiftUI
#if SWIFT_PACKAGE
import JKBMSCore
#endif

public struct AlarmListDialog: View {
    public let alarms: [JKBMSAlarm]
    @Environment(\.dismiss) var dismiss

    public init(alarms: [JKBMSAlarm]) {
        self.alarms = alarms
    }

    public var body: some View {
        NavigationView {
            List {
                if alarms.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundColor(JKTheme.successGreen)
                            .font(.system(size: 44))
                            .padding(.top, 20)

                        Text("系统状态正常，无活动报警")
                            .font(.system(size: 15, weight: .bold))

                        Text("保护板各项电压、电流、温度指标均在安全阈值以内。")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                } else {
                    Section(header: Text("检测到的报警与保护 (\(alarms.count))")) {
                        ForEach(alarms) { alarm in
                            HStack(spacing: 12) {
                                Image(systemName: alarm.severity == .critical ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                                    .foregroundColor(alarm.severity == .critical ? .red : .orange)
                                    .font(.system(size: 20))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(alarm.name)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.primary)

                                    Text("位偏移 Bit: \(alarm.bit) • 严重度: \(alarm.severity == .critical ? "高危停机保护" : "警示提示")")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("系统报警详情")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
