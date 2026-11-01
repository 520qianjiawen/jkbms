import SwiftUI
#if SWIFT_PACKAGE
import JKBMSCore
#endif

public struct CellVoltageGridView: View {
    public let status: JKBMSStatus

    public init(status: JKBMSStatus) {
        self.status = status
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with Delta V and Avg V
            HStack {
                Text("单体电芯电压 (Cell Voltages)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)

                Spacer()

                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        Circle().fill(Color.red).frame(width: 6, height: 6)
                        Text("最低")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 3) {
                        Circle().fill(JKTheme.secondaryBlue).frame(width: 6, height: 6)
                        Text("最高")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    if !status.balancingCellIndices.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.yellow)
                            Text("均衡")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Cell list in 2 or 3 columns
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible(), spacing: 6)
            ], spacing: 6) {
                ForEach(0..<status.cellVoltages.count, id: \.self) { idx in
                    cellPill(index: idx, voltage: status.cellVoltages[idx])
                }
            }
        }
        .padding(14)
        .background(Color.appSecondarySystemGroupedBackground)
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }

    private func cellPill(index: Int, voltage: Double) -> some View {
        let isMin = index == status.minCellIndex
        let isMax = index == status.maxCellIndex
        let isBalancing = status.balancingCellIndices.contains(index)

        return HStack(spacing: 6) {
            // Cell number badge
            Text(String(format: "%02d", index + 1))
                .font(JKTheme.monoFont(size: 11, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(isMax ? JKTheme.secondaryBlue : (isMin ? Color.red : JKTheme.primaryBlue.opacity(0.8)))
                )

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 2) {
                    Text(JKDisplayValue.number(voltage, format: "%.3f"))
                        .font(JKTheme.monoFont(size: 13, weight: .semibold))
                        .foregroundColor(valueColor(isMin: isMin, isMax: isMax))

                    Text("V")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }

                if isBalancing {
                    HStack(spacing: 2) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.yellow)
                        Text("均衡中")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.yellow)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.appSystemBackground)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isBalancing ? Color.yellow : (isMax ? JKTheme.secondaryBlue.opacity(0.5) : (isMin ? Color.red.opacity(0.5) : Color.clear)), lineWidth: 1)
        )
    }

    private func valueColor(isMin: Bool, isMax: Bool) -> Color {
        if isMin {
            return Color.red
        } else if isMax {
            return JKTheme.secondaryBlue
        } else {
            return .primary
        }
    }
}
