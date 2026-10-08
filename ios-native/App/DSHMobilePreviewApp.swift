import SwiftUI

@main
struct DSHMobilePreviewApp: App {
    var body: some Scene {
        WindowGroup {
            MobileRootView()
                .tint(PreviewStyle.blue)
        }
    }
}
