import SwiftUI
#if SWIFT_PACKAGE
import JKBMSCore
#endif

struct DeviceManagementView: View {
    @ObservedObject private var bt = JKBluetoothManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var kind: JKDeviceTextKind = .name
    @State private var value = ""
    @State private var oldPassword = ""
    @State private var confirmation = ""
    @State private var confirmSend = false
    @State private var confirmClock = false
    @State private var showHistory = false
    @State private var confirmErase = false
    @State private var calibrateVoltage = true
    @State private var reference = ""
    @State private var confirmCalibration = false
    var body: some View {
        NavigationStack {
            Form {
                Section("设备信息修改") {
                    Picker("项目", selection: $kind) {
                        ForEach(JKDeviceTextKind.allCases) { Text($0.title).tag($0) }
                    }
                    .onChange(of: kind) { _, _ in value = ""; oldPassword = ""; confirmation = "" }
                    if kind == .bluetoothPassword { PasswordEntryField(title: "当前蓝牙连接密码", text: $oldPassword) }
                    if kind.isPassword {
                        PasswordEntryField(title: "新密码", text: $value)
                        PasswordEntryField(title: "再次输入新密码", text: $confirmation)
                    } else { TextField("新\(kind.title)", text: $value) }
                    Text("使用1至12位英文字母、数字或ASCII符号。修改后等待保护板回传确认。")
                        .font(.caption).foregroundColor(.secondary)
                    if !bt.originalCommandSupported(kind.register) {
                        Text("设备未开放此指令").foregroundColor(.secondary)
                    }
                    Button("确认修改\(kind.title)") { confirmSend = true }
                        .disabled(!bt.canWrite || !bt.originalCommandSupported(kind.register) || value.isEmpty || (kind.isPassword && value != confirmation))
                }
                Section("测量校准") {
                    Picker("校准对象", selection: $calibrateVoltage) {
                        Text("电池总电压").tag(true); Text("电池电流").tag(false)
                    }
                    TextField(calibrateVoltage ? "万用表实测总电压（V）" : "电流表实测电流绝对值（A）", text: $reference)
                    Text("保持测量条件稳定，并输入独立仪表的实测数值。校准会改变保护板测量参数。")
                        .font(.caption).foregroundColor(.secondary)
                    Button("校准测量值") { confirmCalibration = true }
                        .disabled(!bt.canWrite || !bt.originalCommandSupported(calibrateVoltage ? 0x64 : 0x67) || Double(reference) == nil)
                }
                Section("时间与历史") {
                    Button("校准设备时间") { confirmClock = true }
                        .disabled(!bt.canWrite || !bt.originalCommandSupported(0x6C))
                    Button("读取详细历史记录") { showHistory = true }
                        .disabled(!bt.supportsDetailedLogs)
                    Button("清除保护板全部数据", role: .destructive) { confirmErase = true }
                        .disabled(!bt.canWrite || !bt.originalCommandSupported(0xA3))
                    Text("时间校准采用保护板的2020年起算RTC；详细历史来自设备存储，不使用本地模拟数据。")
                        .font(.caption).foregroundColor(.secondary)
                }
                Section("操作状态") {
                    Text(bt.canWrite ? "本应用修改已解锁" : "请先连接并在参数页确认设置密码")
                    if !bt.commandMessage.isEmpty { Text(bt.commandMessage) }
                }
            }
            .navigationTitle("设备管理")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
            .confirmationDialog("修改\(kind.title)？", isPresented: $confirmSend, titleVisibility: .visible) {
                Button("发送修改请求") {
                    bt.changeDeviceText(kind: kind, value: value, oldPassword: oldPassword)
                    value = ""; confirmation = ""; oldPassword = ""
                }
                Button("取消", role: .cancel) {}
            }
            .confirmationDialog("将保护板时间校准为手机当前时间？", isPresented: $confirmClock, titleVisibility: .visible) {
                Button("校准时间") { bt.calibrateDeviceTime() }
                Button("取消", role: .cancel) {}
            }
            .confirmationDialog("使用独立仪表的实测数值执行校准？", isPresented: $confirmCalibration, titleVisibility: .visible) {
                Button("执行校准") { if let value = Double(reference) { bt.calibrateSensor(voltage: calibrateVoltage, reference: value) } }
                Button("取消", role: .cancel) {}
            }
            .confirmationDialog("清除保护板全部数据？此操作不可撤销，请先导出需要保留的历史记录。", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("清除全部数据", role: .destructive) { bt.eraseAllDeviceData() }
                Button("取消", role: .cancel) {}
            }
            .sheet(isPresented: $showHistory) { DetailedLogsView() }
        }
    }
}

struct DetailedLogsView: View {
    @ObservedObject private var bt = JKBluetoothManager.shared
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(bt.detailedLogMessage)
                    HStack {
                        Button(bt.isDownloadingDetailedLogs ? "停止下载" : "读取设备历史") {
                            if bt.isDownloadingDetailedLogs { bt.cancelDetailedLogs() } else { bt.requestDetailedLogs() }
                        }.disabled(!bt.supportsDetailedLogs)
                        Spacer()
                        ShareLink(item: bt.detailedLogsCSV) { Label("导出CSV文本", systemImage: "square.and.arrow.up") }
                            .disabled(bt.detailedLogs.isEmpty)
                    }
                }
                ForEach(bt.detailedLogs) { record in
                    DisclosureGroup {
                        ForEach(record.values) { value in
                            LabeledContent(value.field.title, value: value.display).font(.caption)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("#\(record.index) · \(record.event)")
                            if let date = record.date { Text(date, format: .dateTime).font(.caption).foregroundColor(.secondary) }
                        }
                    }
                }
            }
            .navigationTitle("保护板详细历史")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
        }
    }
}
