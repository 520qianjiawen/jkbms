import SwiftUI
import UniformTypeIdentifiers
#if SWIFT_PACKAGE
import JKBMSCore
#endif

private struct JKLogCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let text = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
        self.text = text
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

struct JKSystemLogsView: View {
    @ObservedObject private var bt = JKBluetoothManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingExporter = false
    @State private var exportDocument = JKLogCSVDocument(text: "")
    @State private var exportError = ""

    var body: some View {
        NavigationView {
            List {
                Section {
                    Text("保护板保存的最近 50 条设备事件。以下时间为保护板累计运行时间，并非日历日期。")
                        .font(.caption).foregroundColor(.secondary)
                    Text(bt.logbookMessage).font(.subheadline)
                    if !exportError.isEmpty { Text(exportError).font(.caption).foregroundColor(.red) }
                }
                if bt.systemLogs.isEmpty {
                    Section {
                        Text("尚未读取到设备事件日志。连接保护板后点击刷新。")
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                } else {
                    Section("设备回传记录（\(bt.systemLogs.count) 条）") {
                        ForEach(bt.systemLogs) { entry in
                            HStack(alignment: .top, spacing: 12) {
                                Text(String(format: "%02d", entry.index))
                                    .font(.caption.monospaced()).foregroundColor(.secondary).frame(width: 25)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(entry.event).font(.subheadline.bold())
                                    Text("运行时间：\(entry.uptimeDescription)")
                                        .font(.caption.monospaced()).foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(String(format: "0x%02X", entry.code))
                                    .font(.caption2.monospaced()).foregroundColor(.secondary)
                            }.padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("保护板事件日志")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { bt.requestSystemLogs() } label: { Label("刷新", systemImage: "arrow.clockwise") }
                        .disabled(!bt.isConnected || bt.isSimulatorMode)
                    Button {
                        exportDocument = JKLogCSVDocument(text: bt.systemLogsCSV)
                        showingExporter = true
                    } label: { Label("导出 CSV", systemImage: "square.and.arrow.up") }
                    .disabled(bt.systemLogs.isEmpty)
                }
            }
            .fileExporter(isPresented: $showingExporter, document: exportDocument, contentType: .commaSeparatedText, defaultFilename: "JKBMS-设备事件日志.csv") { result in
                if case .failure(let error) = result { exportError = error.localizedDescription }
            }
        }
    }
}
