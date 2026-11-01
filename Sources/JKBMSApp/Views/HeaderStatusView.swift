import SwiftUI
#if SWIFT_PACKAGE
import JKBMSCore
#endif

public struct HeaderStatusView: View {
    @ObservedObject var bt = JKBluetoothManager.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Top Bar with Device name and BLE status
            HStack(spacing: 8) {
                Image(systemName: bt.isConnected ? "wave.3.forward.circle.fill" : "wave.3.forward.circle")
                    .foregroundColor(bt.isConnected ? .green : .gray)
                    .font(.system(size: 16))

                Text(bt.connectedDevice?.name ?? (bt.isConnected ? bt.status.deviceModel : "未连接设备 (Disconnected)"))
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)

                Spacer()

                if bt.isSimulatorMode {
                    Text("演示模式 (Demo)")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .foregroundColor(.orange)
                        .cornerRadius(4)
                }

                Circle()
                    .fill(bt.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.appSecondarySystemBackground)

            // Three core MOS status switches header
            HStack(spacing: 0) {
                statusBadge(
                    title: "充电 (Charge)",
                    isOn: bt.status.isChargeEnabled,
                    activeColor: JKTheme.successGreen,
                    available: bt.isSimulatorMode || bt.detectedProtocol != .jk04
                )

                Divider()
                    .frame(height: 20)

                statusBadge(
                    title: "放电 (Discharge)",
                    isOn: bt.status.isDischargeEnabled,
                    activeColor: JKTheme.successGreen,
                    available: bt.isSimulatorMode || bt.detectedProtocol != .jk04
                )

                Divider()
                    .frame(height: 20)

                statusBadge(
                    title: "均衡 (Balance)",
                    isOn: bt.status.isBalanceEnabled,
                    activeColor: JKTheme.primaryBlue
                )
            }
            .padding(.vertical, 6)
            .background(Color.appSystemBackground)
            .overlay(
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundColor(Color.gray.opacity(0.2)),
                alignment: .bottom
            )
        }
    }

    private func statusBadge(title: String, isOn: Bool, activeColor: Color, available: Bool = true) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isOn && bt.hasTelemetry && available ? activeColor : Color.gray.opacity(0.4))
                .frame(width: 7, height: 7)

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            Text(bt.hasTelemetry && available ? (isOn ? "开启" : "关闭") : "—")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(isOn && bt.hasTelemetry && available ? activeColor : .secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Missing or non-finite fields are absent readings, never simulated values.
enum JKDisplayValue {
    static func number(_ value: Double, format: String) -> String {
        value.isFinite ? String(format: format, value) : "—"
    }
}
