import SwiftUI
#if SWIFT_PACKAGE
import JKBMSCore
#endif

public struct RealTimeView: View {
    @ObservedObject private var bt = JKBluetoothManager.shared
    @State private var showingAlarmDetails = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if bt.hasTelemetry {
                    HStack {
                        Label(bt.isSimulatorMode ? "演示数据" : "设备实时数据", systemImage: bt.isSimulatorMode ? "play.rectangle" : "wave.3.right")
                        Spacer()
                        if let lastUpdate = bt.lastUpdate {
                            Text(lastUpdate, style: .time).monospacedDigit()
                        }
                    }.font(.caption).foregroundColor(.secondary).padding(.horizontal, 16)
                    AlarmBannerView(alarms: bt.status.alarms) { showingAlarmDetails = true }
                    BatterySummaryCard(status: bt.status, protocolVariant: bt.detectedProtocol)
                    CellVoltageGridView(status: bt.status)
                    if !bt.status.cellWireResistances.isEmpty {
                        WireResistanceGridView(resistances: bt.status.cellWireResistances)
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: bt.isConnected ? "wave.3.right" : "antenna.radiowaves.left.and.right.slash")
                            .font(.system(size: 48)).foregroundColor(JKTheme.primaryBlue)
                        Text(bt.isConnected ? "等待保护板数据" : "尚未连接保护板").font(.title3.bold())
                        Text(bt.connectionMessage).font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
                        Text(bt.isConnected ? "连接后会自动读取状态。若持续没有数据，请在设备页检查协议和通信日志。" : "请打开“设备列表”，扫描并连接附近的极空保护板。")
                            .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
                        if bt.isConnected { ProgressView() }
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity)
                    .background(Color.appSecondarySystemGroupedBackground)
                    .cornerRadius(12).padding(16)
                }
                Spacer(minLength: 20)
            }.padding(.top, 8)
        }
        .background(Color.appSystemGroupedBackground)
        .refreshable { if bt.isConnected { bt.send(command: .requestTelemetry) } }
        .sheet(isPresented: $showingAlarmDetails) { AlarmListDialog(alarms: bt.status.alarms) }
    }
}
