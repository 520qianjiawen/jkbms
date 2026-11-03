import SwiftUI
import CoreBluetooth
#if SWIFT_PACKAGE
import JKBMSCore
#endif

public struct DeviceListView: View {
    @ObservedObject private var bt = JKBluetoothManager.shared
    @State private var showingCatalog = false
    @State private var showingLog = false
    @State private var showingManagement = false
    @State private var showingOriginalFields = false
    @State private var showingSystemLogs = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                card("连接方式", icon: "antenna.radiowaves.left.and.right") {
                    Toggle("演示模式", isOn: Binding(
                        get: { bt.isSimulatorMode },
                        set: { bt.setDemoMode($0) }
                    ))
                    Text(bt.isSimulatorMode ? "演示数据不会发送到真实保护板。关闭后可扫描并连接附近设备。" : "使用手机蓝牙连接已通电的保护板。首次使用请允许蓝牙访问。")
                        .font(.caption).foregroundColor(.secondary)
                    if !bt.isSimulatorMode {
                        LabeledContent("手机蓝牙", value: bluetoothDescription)
                        Picker("通信协议", selection: $bt.protocolVariant) {
                            ForEach(JKProtocolVariant.allCases) { variant in
                                Text(variant.displayName).tag(variant)
                            }
                        }
                        .disabled(bt.isConnected || bt.isConnecting)
                        Text("优先使用自动识别；连接成功却没有数据时，可断开后按硬件版本选择协议。")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }

                card("当前连接", icon: "link") {
                    HStack(spacing: 10) {
                        if bt.isConnecting { ProgressView() }
                        Text(bt.connectionMessage)
                            .font(.subheadline)
                            .foregroundColor(bt.isConnected ? JKTheme.successGreen : .secondary)
                        Spacer()
                        if bt.isConnected || bt.isConnecting {
                            Button("断开", role: .destructive) { bt.disconnect() }
                                .buttonStyle(.bordered)
                        }
                    }
                    if let device = bt.connectedDevice {
                        Text(device.name).font(.headline)
                        if !device.isSimulator {
                            Text(device.id.uuidString).font(.caption2.monospaced()).foregroundColor(.secondary)
                        }
                    }
                    DeviceConnectionPasswordView()
                    Button("设备管理、密码与详细历史") { showingManagement = true }
                        .buttonStyle(.bordered).disabled(bt.originalSchemaName.isEmpty || bt.requiresDevicePassword)
                    Button("查看完整参数与设备数据") { showingOriginalFields = true }
                        .buttonStyle(.bordered).disabled(bt.originalSchemaName.isEmpty || bt.requiresDevicePassword)
                    if bt.hasTelemetry {
                        LabeledContent("设备型号", value: bt.status.deviceModel)
                        LabeledContent("硬件版本", value: bt.status.hardwareVersion)
                        LabeledContent("固件版本", value: bt.status.firmwareVersion)
                        LabeledContent("序列号", value: bt.status.deviceSN)
                        LabeledContent("运行时间", value: "\(bt.status.uptimeSeconds / 3600) 小时")
                    }
                    if let date = bt.lastUpdate {
                        HStack {
                            Text("最后数据").foregroundColor(.secondary)
                            Spacer()
                            Text(date, style: .time).monospacedDigit()
                        }.font(.caption)
                    }
                }

                if !bt.isSimulatorMode {
                    card("附近保护板", icon: "wave.3.right") {
                        NearbyBoardsView()
                    }
                }

                card("诊断与型号参考", icon: "stethoscope") {
                    if !bt.commandMessage.isEmpty {
                        Text(bt.commandMessage).font(.subheadline)
                    }
                    Button("保护板事件日志（最近 50 条）") { showingSystemLogs = true }
                        .disabled(!bt.isConnected || bt.isSimulatorMode)
                    Button("查看通信诊断日志") { showingLog = true }
                    Button("查看型号目录") { showingCatalog = true }
                    Text("型号目录用于识别设备；实际可用功能取决于保护板协议、固件和设备回传。")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .padding(16)
        }
        .background(Color.appSystemGroupedBackground)
        .sheet(isPresented: $showingManagement) { DeviceManagementView() }
        .sheet(isPresented: $showingOriginalFields) { OriginalFieldsView() }
        .sheet(isPresented: $showingSystemLogs) { JKSystemLogsView() }
        .sheet(isPresented: $showingCatalog) { SupportedModelsSheet() }
        .sheet(isPresented: $showingLog) {
            NavigationView {
                ScrollView {
                    Text(bt.diagnosticLog.isEmpty ? "暂无通信日志" : bt.diagnosticLog)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .navigationTitle("通信日志")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("完成") { showingLog = false } }
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: bt.diagnosticLog) { Label("导出", systemImage: "square.and.arrow.up") }
                    }
                }
            }
        }
    }

    private var bluetoothDescription: String {
        switch bt.bluetoothState {
        case .poweredOn: return "已开启"
        case .poweredOff: return "已关闭，请在系统设置中开启"
        case .unauthorized: return "未授权，请在系统设置中允许蓝牙访问"
        case .unsupported: return "当前设备不支持蓝牙低功耗"
        case .resetting: return "蓝牙正在重置"
        case .unknown: return "正在检查"
        @unknown default: return "未知状态"
        }
    }

    private func card<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.headline)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSecondarySystemGroupedBackground)
        .cornerRadius(12)
    }
}

public struct SupportedModelsSheet: View {
    @Environment(\.dismiss) private var dismiss
    public init() {}
    public var body: some View {
        NavigationView {
            List {
                Section {
                    Text("以下是型号参考目录，连接及控制能力由实际协议和固件决定。")
                        .font(.caption).foregroundColor(.secondary)
                }
                Section("型号参考") {
                    ForEach(DeviceCatalog.defaultModels) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name).font(.headline)
                            Text("\(item.series) · \(item.count) 串")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("保护板型号目录")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
            }
        }
    }
}
