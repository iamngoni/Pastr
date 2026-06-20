import SwiftUI

@main
struct PastrMobileApp: App {
    @StateObject private var clipStore = MobileClipStore()

    var body: some Scene {
        WindowGroup {
            PastrMobileRootView()
                .environmentObject(clipStore)
                .task {
                    await clipStore.refreshNow()
                }
        }
    }
}
