import LumenUI
import SwiftUI

@main
struct LumenApp: App {
    @State private var app: AppModel? = try? AppModel()

    var body: some Scene {
        WindowGroup {
            if let app {
                RootView(app: app)
            } else {
                Text("Не открылась база Lumen в ~/Library/Application Support/Lumen")
                    .padding(40)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 760)
    }
}
