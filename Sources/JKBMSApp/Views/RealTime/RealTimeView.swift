import SwiftUI
#if SWIFT_PACKAGE
import JKBMSCore
#endif

public struct RealTimeView: View {
    @ObservedObject private var bt = JKBluetoothManager.shared
    @State private var showingAlarmDetails = false

    private let onShowDevices: () -> Void

    public init(onShowDevices: @escaping () -> Void = {}) { self.onShowDevices = onShowDevices }

    public var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                connectionCard
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
                } else if bt.isConnected && !bt.requiresDevicePassword {
                    VStack(spacing: 16) {
                        Image(systemName: bt.isConnected ? "wave.3.right" : "antenna.radiowaves.left.and.right.slash")
                            .font(.system(size: 48)).foregroundColor(JKTheme.primaryBlue)
                        Text(bt.isConnected ? "等待保护板数据" : "尚未连接保护板").font(.title3.bold())
                        Text(bt.connectionMessage).font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
                        Text("连接后会自动读取状态。若持续没有数据，请在设备页检查协议和通信日志。")
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

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(bt.isConnected ? "保护板连接" : "搜索保护板", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.headline)
                Spacer()
                Button("设备列表", action: onShowDevices).font(.subheadline)
            }
            if let device = bt.connectedDevice {
                HStack {
                    Text(device.name).font(.subheadline.bold())
                    Spacer()
                    if bt.isConnecting { ProgressView().controlSize(.small) }
                    Button("断开", role: .destructive) { bt.disconnect() }.buttonStyle(.bordered)
                }
            }
            Text(bt.connectionMessage).font(.caption).foregroundColor(.secondary)
            if bt.isSimulatorMode {
                Button("搜索真实保护板") { bt.setDemoMode(false) }.buttonStyle(.borderedProminent)
            } else {
                if !bt.isConnected && !bt.isConnecting { NearbyBoardsView(showsFilters: false) }
                DeviceConnectionPasswordView()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSecondarySystemGroupedBackground)
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }

}
