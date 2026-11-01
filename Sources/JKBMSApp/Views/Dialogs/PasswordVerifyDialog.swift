import SwiftUI
#if SWIFT_PACKAGE
import JKBMSCore
#endif

public struct PasswordVerifyDialog: View {
    public let currentPassword: String
    @Binding public var isVerified: Bool
    @ObservedObject private var bt = JKBluetoothManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var inputPassword = ""
    @State private var rememberSettingsPassword = true
    @State private var newPassword = ""
    @State private var confirmNewPassword = ""
    @State private var errorMessage = ""

    public init(currentPassword: String, isVerified: Binding<Bool>) {
        self.currentPassword = currentPassword
        self._isVerified = isVerified
    }

    public var body: some View {
        NavigationView {
            Form {
                if !bt.isAuthenticated && !bt.isSimulatorMode {
                    Section {
                        PasswordEntryField(title: "请输入保护板设置密码", text: $inputPassword, onSubmit: verifyPassword)
                        Button("确认密码并解锁修改", action: verifyPassword)
                            .buttonStyle(.borderedProminent)
                            .disabled(inputPassword.isEmpty || !bt.isConnected)
                        Toggle("记住此设备的设置密码", isOn: $rememberSettingsPassword)
                        Text("下次连接时自动核对，无需重复输入。").font(.caption).foregroundColor(.secondary)
                    } header: {
                        Text("解锁本应用修改")
                    } footer: {
                        Text("设置密码与蓝牙连接密码相互独立；勾选后保存到本机钥匙串。")
                    }
                } else {
                    Section("修改保护板密码") {
                        if bt.supportsPasswordChange {
                            PasswordEntryField(title: "新密码", text: $newPassword)
                            PasswordEntryField(title: "再次输入新密码", text: $confirmNewPassword)
                            Button("发送密码修改请求") {
                                guard !newPassword.isEmpty, newPassword == confirmNewPassword else {
                                    errorMessage = "两次输入的密码不一致或为空。"
                                    return
                                }
                                bt.send(command: .setPassword(newPass: newPassword))
                            }.disabled(!bt.canWrite)
                            Text(bt.commandMessage).font(.caption).foregroundColor(.secondary)
                        } else {
                            Text("当前协议尚未核实密码修改指令，暂不支持从本应用修改保护板密码。")
                                .font(.subheadline).foregroundColor(.secondary)
                        }
                    }
                }
                if !bt.credentialMessage.isEmpty {
                    Section { Text(bt.credentialMessage).font(.caption).foregroundColor(.orange) }
                }
                if !errorMessage.isEmpty {
                    Section { Text(errorMessage).font(.subheadline).foregroundColor(.red) }
                }
            }
            .navigationTitle(bt.isAuthenticated || bt.isSimulatorMode ? "设置密码" : "确认设置密码")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
            }
        }
    }

    private func verifyPassword() {
        if bt.authenticate(password: inputPassword, remember: rememberSettingsPassword) {
            inputPassword = ""
            isVerified = bt.isAuthenticated
            dismiss()
        } else { errorMessage = bt.lastErrorMessage ?? "密码验证未通过，请重新输入。" }
    }
}
