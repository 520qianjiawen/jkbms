import SwiftUI
#if SWIFT_PACKAGE
import JKBMSCore
#endif

public struct BatterySummaryCard: View {
    public let status: JKBMSStatus
    public let protocolVariant: JKProtocolVariant

    public init(status: JKBMSStatus, protocolVariant: JKProtocolVariant = .automatic) {
        self.status = status
        self.protocolVariant = protocolVariant
    }

    public var body: some View {
        VStack(spacing: 12) {
            // Main Voltage & Current Display
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("总电压 (Voltage)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(JKDisplayValue.number(status.batteryVoltage, format: "%.3f"))
                            .font(JKTheme.monoFont(size: 28, weight: .bold))
                            .foregroundColor(.primary)

                        Text("V")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()
                    .frame(height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text("总电流 (Current)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(JKDisplayValue.number(status.batteryCurrent, format: "%+.2f"))
                            .font(JKTheme.monoFont(size: 28, weight: .bold))
                            .foregroundColor(currentColor)

                        Text("A")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 4)

            // SOC Progress Bar
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: socIcon)
                        .foregroundColor(socColor)
                        .font(.system(size: 13))

                    Text("剩余电量 (SOC): " + JKDisplayValue.number(status.soc, format: "%.0f%%"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)

                    Spacer()

                    Text(JKDisplayValue.number(status.remainingCapacity, format: "%.1f") + " / " + JKDisplayValue.number(status.totalCapacity, format: "%.1f Ah"))
                        .font(JKTheme.monoFont(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(socColor)
                            .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(status.soc.isFinite ? max(0, min(1, status.soc / 100.0)) : 0))), height: 8)
                    }
                }
                .frame(height: 8)
            }

            Divider()

            // 6-Grid Key Parameters
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 10) {
                statItem(title: "实时功率", value: JKDisplayValue.number(status.batteryPower, format: "%.1f W"))
                statItem(title: "最大压差", value: JKDisplayValue.number(status.deltaVoltage, format: "%.3f V"), highlight: status.deltaVoltage > 0.03 ? .orange : nil)
                statItem(title: "单体平均", value: JKDisplayValue.number(status.averageVoltage, format: "%.3f V"))

                statItem(title: "MOS温度", value: JKDisplayValue.number(status.mosTemperature, format: "%.1f °C"))
                statItem(title: "电池T1", value: JKDisplayValue.number(status.batteryT1, format: "%.1f °C"))
                statItem(title: "电池T2", value: JKDisplayValue.number(status.batteryT2, format: "%.1f °C"))

                statItem(title: "循环次数", value: protocolVariant == .jk04 ? "—" : "\(status.cycleCount) 次")
                statItem(title: "累计容量", value: JKDisplayValue.number(status.totalCycleCapacity, format: "%.0f Ah"))
                statItem(title: "运行时间", value: formatUptime(status.uptimeSeconds))
            }
        }
        .padding(14)
        .background(Color.appSecondarySystemGroupedBackground)
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }

    private var currentColor: Color {
        if status.batteryCurrent > 0.05 {
            return JKTheme.successGreen
        } else if status.batteryCurrent < -0.05 {
            return Color.orange
        } else {
            return .primary
        }
    }

    private var socColor: Color {
        guard status.soc.isFinite else { return .secondary }
        if status.soc > 50 {
            return JKTheme.successGreen
        } else if status.soc > 20 {
            return Color.orange
        } else {
            return JKTheme.dangerRed
        }
    }

    private var socIcon: String {
        if status.soc >= 90 { return "battery.100" }
        if status.soc >= 75 { return "battery.75" }
        if status.soc >= 50 { return "battery.50" }
        if status.soc >= 25 { return "battery.25" }
        return "battery.0"
    }

    private func statItem(title: String, value: String, highlight: Color? = nil) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text(value)
                .font(JKTheme.monoFont(size: 13, weight: .semibold))
                .foregroundColor(highlight ?? .primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatUptime(_ seconds: UInt32) -> String {
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        if days > 0 {
            return "\(days)天\(hours)时"
        } else {
            let mins = (seconds % 3600) / 60
            return "\(hours)时\(mins)分"
        }
    }
}
