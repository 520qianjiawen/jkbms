import SwiftUI
import CoreBluetooth
#if SWIFT_PACKAGE
import JKBMSCore
#endif

public struct RealTimeView: View {
    @ObservedObject private var bt: JKBluetoothManager
    @State private var showingAlarmDetails = false
    @State private var hasRequestedSearch = false
    private let onShowDevices: () -> Void

    public init(manager: JKBluetoothManager = .shared, onShowDevices: @escaping () -> Void = {}) {
        self.bt = manager; self.onShowDevices = onShowDevices
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                pageHeading
                connectionCard
                if !bt.isSimulatorMode && !bt.isConnected && !bt.isConnecting {
                    if bt.isScanning || hasRequestedSearch || !bt.discoveredDevices.isEmpty {
                        nearbyDevices
                    } else {
                        connectionGuide
                    }
                }
                if bt.hasTelemetry {
                    HStack {
                        Text(bt.isSimulatorMode ? "演示数据" : "实时概览").font(.headline)
                        Spacer()
                        if let lastUpdate = bt.lastUpdate {
                            HStack(spacing: 5) {
                                Circle().fill(JKTheme.successGreen).frame(width: 5, height: 5)
                                Text(lastUpdate, style: .time).monospacedDigit()
                            }.font(.caption).foregroundColor(.secondary)
                        }
                    }.padding(.horizontal, 20)
                    AlarmBannerView(alarms: bt.status.alarms) { showingAlarmDetails = true }
                    BatterySummaryCard(status: bt.status, protocolVariant: bt.detectedProtocol)
                    CellVoltageGridView(status: bt.status)
                    if !bt.status.cellWireResistances.isEmpty {
                        WireResistanceGridView(resistances: bt.status.cellWireResistances)
                    }
                } else if bt.isConnected && !bt.requiresDevicePassword {
                    HStack(spacing: 14) {
                        ProgressView()
                        VStack(alignment: .leading, spacing: 5) {
                            Text("正在读取电池数据").font(.subheadline.weight(.semibold))
                            Text("稍候将显示电压、电量和电芯状态。")
                                .font(.caption).foregroundColor(.secondary)
                            Button("查看协议与通信诊断", action: onShowDevices).font(.caption)
                        }
                        Spacer(minLength: 0)
                    }.padding(20).homeSurface().padding(.horizontal, 16)
                }
            }.padding(.top, 22).padding(.bottom, 28)
        }
        .background(Color.appSystemGroupedBackground)
        .refreshable { if bt.isConnected { bt.send(command: .requestTelemetry) } }
        .onChange(of: bt.isScanning) { _, scanning in if scanning { hasRequestedSearch = true } }
        .sheet(isPresented: $showingAlarmDetails) { AlarmListDialog(alarms: bt.status.alarms) }
    }

    private var pageHeading: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("极空 BMS").font(.system(size: 27, weight: .bold, design: .rounded))
                Text(bt.hasTelemetry ? "电池状态，尽在掌握" : "从连接一块保护板开始")
                    .font(.subheadline).foregroundColor(.secondary)
            }
            Spacer(minLength: 8)
            Label(bluetoothLabel, systemImage: "antenna.radiowaves.left.and.right")
                .font(.caption.weight(.medium))
                .foregroundColor(bt.bluetoothState == .poweredOn ? JKTheme.secondaryBlue : .secondary)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(JKTheme.primaryBlue.opacity(0.09), in: Capsule())
                .fixedSize(horizontal: true, vertical: false)
        }.padding(.horizontal, 20)
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Label(connectionLabel, systemImage: bt.isConnected ? "link" : "circle.dotted")
                        .font(.caption.weight(.semibold)).foregroundColor(accent)
                    Text(heroTitle)
                        .font(.system(size: bt.isConnected ? 22 : 28, weight: .bold, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(heroSubtitle).font(.subheadline).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
                ZStack {
                    Circle().stroke(accent.opacity(0.1), lineWidth: 1).frame(width: 90, height: 90)
                    Circle().fill(accent.opacity(0.08)).frame(width: 68, height: 68)
                    Image(systemName: bt.isConnected ? "battery.100percent" : "antenna.radiowaves.left.and.right")
                        .font(.system(size: 28, weight: .medium)).foregroundColor(accent)
                }.accessibilityHidden(true)
            }
            if bt.isConnected || bt.isConnecting {
                if bt.hasTelemetry { connectionStates }
                if bt.isConnecting {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(bt.connectionMessage).font(.caption).foregroundColor(.secondary)
                    }
                }
                DeviceConnectionPasswordView(manager: bt)
                HStack(spacing: 12) {
                    Button(action: onShowDevices) {
                        Label("设备详情", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered).controlSize(.large)
                    Button("断开连接", role: .destructive) { bt.disconnect() }
                        .buttonStyle(.bordered).controlSize(.large)
                }
            } else {
                Button(action: searchAction) {
                    HStack(spacing: 10) {
                        if bt.isScanning { ProgressView().tint(.white) }
                        Image(systemName: bt.isScanning ? "stop.fill" : "magnifyingglass")
                        Text(bt.isScanning ? "停止搜索" : "搜索保护板").fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "arrow.right").font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 18).padding(.vertical, 17)
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.white)
                    .background(LinearGradient(colors: [JKTheme.secondaryBlue, JKTheme.primaryBlue], startPoint: .leading, endPoint: .trailing),
                                in: RoundedRectangle(cornerRadius: 15))
                }
                .buttonStyle(.plain)
                .opacity(bt.bluetoothState == .poweredOn ? 1 : 0.45)
                .disabled(bt.bluetoothState != .poweredOn)
                HStack {
                    Label("点击搜索后才会查找设备", systemImage: "hand.tap")
                        .font(.caption2).foregroundColor(.secondary)
                    Spacer()
                    Button("设备列表", action: onShowDevices).font(.caption.weight(.medium))
                }
            }
            if bt.isSimulatorMode {
                Button("退出演示，搜索真实保护板") {
                    bt.setDemoMode(false)
                    hasRequestedSearch = true
                    bt.startScan()
                }.font(.subheadline.weight(.medium))
                .disabled(bt.bluetoothState != .poweredOn)
            }
        }
        .padding(22)
        .background {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.appSecondarySystemGroupedBackground)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(accent.opacity(0.1)).frame(width: 230, height: 230)
                        .blur(radius: 50).offset(x: 95, y: -100)
                }
                .clipShape(RoundedRectangle(cornerRadius: 24))
        }
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(accent.opacity(0.13), lineWidth: 1))
        .padding(.horizontal, 16)
    }

    private var nearbyDevices: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("附近保护板").font(.headline)
                Spacer()
                Text("按信号排序").font(.caption).foregroundColor(.secondary)
            }
            NearbyBoardsView(manager: bt, showsFilters: false, showsSearchButton: false)
        }.padding(20).homeSurface().padding(.horizontal, 16)
    }

    private var connectionGuide: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("连接前准备").font(.headline)
            guideRow("1", title: "保护板已通电", detail: "将手机靠近保护板，保持蓝牙开启。")
            guideRow("2", title: "释放设备连接", detail: "断开官方 App 或其他手机的连接。")
            guideRow("3", title: "搜索并选择设备", detail: "连接后将自动读取电池的实时状态。")
        }.padding(20).homeSurface().padding(.horizontal, 16)
    }

    private func guideRow(_ number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Text(number).font(.caption.weight(.bold)).foregroundColor(JKTheme.secondaryBlue)
                .frame(width: 27, height: 27).background(JKTheme.primaryBlue.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private var connectionStates: some View {
        HStack(spacing: 8) {
            stateBadge("充电", enabled: bt.status.isChargeEnabled, available: bt.detectedProtocol != .jk04 || bt.isSimulatorMode)
            stateBadge("放电", enabled: bt.status.isDischargeEnabled, available: bt.detectedProtocol != .jk04 || bt.isSimulatorMode)
            stateBadge("均衡", enabled: bt.status.isBalanceEnabled, available: true)
        }
    }

    private func stateBadge(_ title: String, enabled: Bool, available: Bool) -> some View {
        HStack(spacing: 5) {
            Circle().fill(available && enabled ? JKTheme.successGreen : .secondary.opacity(0.4)).frame(width: 5, height: 5)
            Text(title + " " + (available ? (enabled ? "开启" : "关闭") : "—"))
                .font(.caption.weight(.medium)).foregroundColor(.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }

    private var accent: Color { bt.isConnected ? JKTheme.successGreen : JKTheme.secondaryBlue }
    private var connectionLabel: String {
        if bt.isSimulatorMode { return "演示模式" }
        if bt.requiresDevicePassword { return "等待验证" }
        if bt.isConnected { return "已连接" }
        if bt.isConnecting { return "连接中" }
        return bt.isScanning ? "正在搜索" : "等待连接"
    }
    private var heroTitle: String {
        if bt.isConnected || bt.isConnecting { return bt.connectedDevice?.name ?? "极空保护板" }
        return bt.isScanning ? "正在寻找\n附近的保护板" : "连接保护板\n查看电池状态"
    }
    private var heroSubtitle: String {
        if bt.isSimulatorMode { return "当前显示本地演示数据" }
        if bt.isConnected || bt.isConnecting { return bt.connectionMessage }
        if bt.bluetoothState != .poweredOn { return bt.connectionMessage }
        return bt.isScanning ? "请保持保护板通电，并靠近手机。" : "开始搜索，选择你的极空 BMS。"
    }
    private var bluetoothLabel: String {
        switch bt.bluetoothState {
        case .poweredOn: return "蓝牙已开启"
        case .poweredOff: return "蓝牙已关闭"
        case .unauthorized: return "蓝牙未授权"
        default: return "检查蓝牙中"
        }
    }
    private func searchAction() {
        hasRequestedSearch = true
        if bt.isScanning { bt.stopScan() } else { bt.startScan() }
    }
}

private extension View {
    func homeSurface() -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appSecondarySystemGroupedBackground, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.primary.opacity(0.04), lineWidth: 1))
    }
}
