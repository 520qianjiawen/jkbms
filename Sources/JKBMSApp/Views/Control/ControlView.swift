import SwiftUI
#if SWIFT_PACKAGE
import JKBMSCore
#endif

public struct ControlView: View {
    @ObservedObject private var bt = JKBluetoothManager.shared
    @State private var showingPasswordDialog = false
    @State private var pendingAction: BoardAction?

    private enum BoardAction: String, Identifiable {
        case restart = "重启保护板"
        case shutdown = "关闭保护板"
        case restore = "恢复出厂参数"
        var id: String { rawValue }
        var command: JKCommand {
            switch self {
            case .restart: return .restartBoard
            case .shutdown: return .shutdownBoard
            case .restore: return .factoryRestore
            }
        }
        var message: String {
            switch self {
            case .restart: return "保护板将重启，蓝牙连接会中断。请确认当前供电可以中断。"
            case .shutdown: return "保护板将关机，可能中断充放电；重新启动可能需要外部激活。"
            case .restore: return "保护参数将恢复出厂值。请确认已记录现有配置，并在恢复后重新核对电池参数。"
            }
        }
    }

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                section("修改权限") {
                    HStack {
                        Label(bt.isAuthenticated || bt.isSimulatorMode ? "本应用修改已解锁" : "本应用修改已锁定", systemImage: bt.isAuthenticated || bt.isSimulatorMode ? "lock.open.fill" : "lock.fill")
                            .font(.subheadline)
                        Spacer()
                        if !bt.isSimulatorMode {
                            Button(bt.isAuthenticated ? "设置密码" : "解锁修改") { showingPasswordDialog = true }
                                .buttonStyle(.bordered).disabled(!bt.isConnected)
                        }
                    }
                    Text(bt.connectionMessage).font(.caption).foregroundColor(.secondary)
                    if !bt.commandMessage.isEmpty {
                        Text(bt.commandMessage).font(.subheadline).foregroundColor(JKTheme.primaryBlue)
                    }
                    Text("开关状态以设备回传为准。操作后请等待确认。")
                        .font(.caption).foregroundColor(.secondary)
                }

                section("充放电与均衡") {
                    switchRow("充电开关", icon: "bolt.fill", value: bt.settings.isChargeEnabled, command: { .setCharge(enabled: $0) })
                    Divider()
                    switchRow("放电开关", icon: "arrow.up.circle.fill", value: bt.settings.isDischargeEnabled, command: { .setDischarge(enabled: $0) })
                    Divider()
                    switchRow("主动均衡", icon: "arrow.left.arrow.right.circle.fill", value: bt.settings.isBalanceEnabled, command: { .setBalance(enabled: $0) })
                    Divider()
                    switchRow("加热开关", icon: "flame.fill", value: bt.settings.isHeatingEnabled, command: { .setHeating(enabled: $0) })
                    Divider()
                    switchRow("应急启动", icon: "bolt.shield.fill", value: bt.status.isEmergencyEnabled, command: { .setEmergency(enabled: $0) })
                }

                if !advancedSwitches.isEmpty {
                    section("扩展功能开关") {
                        ForEach(advancedSwitches) { definition in
                            switchRow(definition.title, icon: "switch.2", value: (bt.settings.extendedValues[definition.id] ?? 0) != 0) {
                                .setParameter(id: definition.id, value: $0 ? 1 : 0)
                            }
                        }
                    }
                }

                section("系统操作") {
                    ForEach([BoardAction.restart, .shutdown, .restore]) { action in
                        HStack {
                            Button(action.rawValue, role: .destructive) { pendingAction = action }
                                .disabled(!bt.canWrite || !bt.supportsSystemCommands || !bt.supports(command: action.command))
                            Spacer()
                            if !bt.supportsSystemCommands || !bt.supports(command: action.command) {
                                Text("当前协议不支持").font(.caption).foregroundColor(.secondary)
                            }
                        }.padding(.vertical, 6)
                    }
                }
            }.padding(16)
        }
        .background(Color.appSystemGroupedBackground)
        .sheet(isPresented: $showingPasswordDialog) {
            PasswordVerifyDialog(currentPassword: "", isVerified: Binding(get: { bt.isAuthenticated }, set: { _ in }))
        }
        .alert(item: $pendingAction) { action in
            Alert(title: Text("确认\(action.rawValue)？"), message: Text(action.message), primaryButton: .destructive(Text("确认执行")) { bt.send(command: action.command) }, secondaryButton: .cancel(Text("取消")))
        }
    }

    private var advancedSwitches: [JKParameterDefinition] {
        JKParameterCatalog.definitions.filter { $0.isSwitch && bt.settings.extendedValues[$0.id]?.isFinite == true }
    }

    private func switchRow(_ title: String, icon: String, value: Bool, command: @escaping (Bool) -> JKCommand) -> some View {
        let supported = bt.supports(command: command(!value))
        return HStack(spacing: 12) {
            Image(systemName: icon).foregroundColor(JKTheme.primaryBlue).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.bold())
                if !supported {
                    Text("当前协议不支持").font(.caption).foregroundColor(.secondary)
                } else if !bt.hasTelemetry {
                    Text("等待设备数据").font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer()
            if bt.detectedProtocol == .jk04 && !supported && !bt.isSimulatorMode {
                Text("—").foregroundColor(.secondary)
            } else {
            Toggle(title, isOn: Binding(get: { value && bt.hasTelemetry }, set: { bt.send(command: command($0)) }))
                .labelsHidden().tint(JKTheme.successGreen)
                .disabled(!bt.canWrite || !bt.hasTelemetry || !supported)
            }
        }.padding(.vertical, 7)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }.padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appSecondarySystemGroupedBackground)
            .cornerRadius(12)
    }
}
