import SwiftUI
import CoreBluetooth
#if SWIFT_PACKAGE
import JKBMSCore
#endif

/// Both entry points share one Bluetooth session and the same connection actions.
struct NearbyBoardsView: View {
    @ObservedObject private var bt: JKBluetoothManager
    var showsFilters: Bool
    var showsSearchButton: Bool
    @State private var deviceFilter = ""
    @State private var sortBySignal = true

    init(manager: JKBluetoothManager = .shared, showsFilters: Bool = true, showsSearchButton: Bool = true) {
        bt = manager; self.showsFilters = showsFilters; self.showsSearchButton = showsSearchButton
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if bt.isScanning { ProgressView().controlSize(.small) }
                Text(bt.isScanning ? "正在搜索附近设备…" : "显示 \(filteredDevices.count) 台设备")
                    .font(.subheadline).foregroundColor(.secondary)
                Spacer()
                if showsSearchButton {
                    Button(bt.isScanning ? "停止搜索" : "搜索保护板") {
                        if bt.isScanning { bt.stopScan() } else { bt.startScan() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(bt.bluetoothState != .poweredOn || bt.isConnecting || bt.isConnected)
                }
            }
            if showsFilters {
                TextField("筛选名称或设备 UUID", text: $deviceFilter).textFieldStyle(.roundedBorder)
                Toggle("按信号强度排序", isOn: $sortBySignal).font(.caption)
            }
            ForEach(filteredDevices) { device in
                Divider()
                HStack(spacing: 12) {
                    Image(systemName: "batteryblock.fill")
                        .font(.system(size: 20)).foregroundColor(JKTheme.primaryBlue)
                        .frame(width: 42, height: 42)
                        .background(JKTheme.primaryBlue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.name).font(.subheadline.bold())
                        Text("信号 \(device.rssi) dBm").font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    if bt.connectedDevice?.id == device.id && bt.isConnected {
                        Text("已连接").font(.caption.bold()).foregroundColor(JKTheme.successGreen)
                    } else {
                        Button("连接") { bt.connect(to: device) }
                            .buttonStyle(.bordered).disabled(bt.isConnecting || bt.isConnected)
                    }
                }.padding(.vertical, 4)
            }
            if filteredDevices.isEmpty {
                Text("请确认保护板已通电，并断开官方 App 或其他手机的蓝牙连接，再点击“搜索保护板”。")
                    .font(.caption).foregroundColor(.secondary).padding(.vertical, 4)
            }
        }
    }

    private var filteredDevices: [JKDevice] {
        let query = deviceFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let devices = bt.discoveredDevices.filter {
            !$0.isSimulator && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.id.uuidString.localizedCaseInsensitiveContains(query))
        }
        return sortBySignal ? devices.sorted { $0.rssi > $1.rssi } : devices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

struct DeviceConnectionPasswordView: View {
    @ObservedObject private var bt: JKBluetoothManager
    @State private var password = ""
    @State private var rememberPassword = true

    init(manager: JKBluetoothManager = .shared) { bt = manager }

    var body: some View {
        Group {
            if bt.requiresDevicePassword {
                PasswordEntryField(title: "保护板蓝牙连接密码", text: $password, onSubmit: confirmPassword)
                Button("确认连接密码", action: confirmPassword)
                    .buttonStyle(.borderedProminent).disabled(password.isEmpty)
                Toggle("记住此设备密码，下次自动验证", isOn: $rememberPassword).font(.subheadline)
                Text("蓝牙连接密码与参数设置密码分别保存在本机钥匙串。")
                    .font(.caption).foregroundColor(.secondary)
            } else if bt.hasRememberedConnectionPassword || bt.hasRememberedSettingsPassword {
                Label("已记住此设备密码", systemImage: "checkmark.shield.fill")
                    .font(.caption).foregroundColor(JKTheme.successGreen)
                Button("清除记住的密码") { bt.forgetRememberedPasswords() }.font(.caption)
            }
            if !bt.credentialMessage.isEmpty {
                Text(bt.credentialMessage).font(.caption).foregroundColor(.orange)
            }
        }
        .onChange(of: bt.connectedDevice?.id) { _, _ in password = "" }
        .onChange(of: bt.requiresDevicePassword) { _, required in if !required { password = "" } }
        .onDisappear { password = "" }
    }

    private func confirmPassword() {
        if bt.unlockDevice(password: password, remember: rememberPassword) { password = "" }
    }
}
