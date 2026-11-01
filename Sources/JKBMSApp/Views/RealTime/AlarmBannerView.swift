import SwiftUI
#if SWIFT_PACKAGE
import JKBMSCore
#endif

public struct AlarmBannerView: View {
    public let alarms: [JKBMSAlarm]
    public let onTap: () -> Void

    public init(alarms: [JKBMSAlarm], onTap: @escaping () -> Void) {
        self.alarms = alarms
        self.onTap = onTap
    }

    public var body: some View {
        if !alarms.isEmpty {
            Button(action: onTap) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 14, weight: .bold))

                    Text("报警提示 (\(alarms.count)): \(alarms.first?.name ?? "")")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Spacer()

                    Text("查看详情")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))

                    Image(systemName: "chevron.right")
                        .foregroundColor(.white.opacity(0.8))
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.red)
                .cornerRadius(8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
    }
}
