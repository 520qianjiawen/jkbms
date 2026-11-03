import SwiftUI
#if SWIFT_PACKAGE
import JKBMSCore
#endif

public struct MainTabView: View {
    @State private var selectedTab: Int = 0
    @ObservedObject private var bt = JKBluetoothManager.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header status bar
            if selectedTab != 0 { HeaderStatusView() }

            // Main Tab View
            TabView(selection: $selectedTab) {
                RealTimeView(onShowDevices: { selectedTab = 3 })
                    .tabItem {
                        Label("首页", systemImage: "gauge.with.needle.fill")
                    }
                    .tag(0)

                ControlView()
                    .tabItem {
                        Label("控制开关", systemImage: "switch.2")
                    }
                    .tag(1)

                SettingsView()
                    .tabItem {
                        Label("参数设置", systemImage: "slider.horizontal.3")
                    }
                    .tag(2)

                DeviceListView()
                    .tabItem {
                        Label("设备列表", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .tag(3)
            }
            .accentColor(JKTheme.primaryBlue)
        }
        .alert("操作提示", isPresented: Binding(get: { bt.lastErrorMessage != nil }, set: { if !$0 { bt.lastErrorMessage = nil } })) {
            Button("知道了") { bt.lastErrorMessage = nil }
        } message: {
            Text(bt.lastErrorMessage ?? "")
        }
    }
}
