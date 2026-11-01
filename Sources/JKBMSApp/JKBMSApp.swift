import SwiftUI
#if SWIFT_PACKAGE
import JKBMSCore
#endif

@main
struct JKBMSApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .preferredColorScheme(.dark)
        }
    }
}
