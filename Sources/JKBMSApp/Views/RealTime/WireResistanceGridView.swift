import SwiftUI
#if SWIFT_PACKAGE
import JKBMSCore
#endif

public struct WireResistanceGridView: View {
    public let resistances: [Double]

    public init(resistances: [Double]) {
        self.resistances = resistances
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("采集线电阻 (Wire Resistances)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)

                Spacer()

                Text("单位: mΩ")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible(), spacing: 6)
            ], spacing: 6) {
                ForEach(0..<resistances.count, id: \.self) { idx in
                    let resVal = resistances[idx]
                    let isAbnormal = resVal > 3.0 // greater than 3mΩ is high resistance

                    HStack(spacing: 6) {
                        Text(String(format: "%02d", idx + 1))
                            .font(JKTheme.monoFont(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.gray.opacity(0.6)))

                        Text(JKDisplayValue.number(resVal, format: "%.2f"))
                            .font(JKTheme.monoFont(size: 12, weight: .semibold))
                            .foregroundColor(isAbnormal ? JKTheme.warningYellow : .primary)

                        Text("mΩ")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)

                        Spacer()
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 6)
                    .background(Color.appSystemBackground)
                    .cornerRadius(4)
                }
            }
        }
        .padding(14)
        .background(Color.appSecondarySystemGroupedBackground)
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }
}
