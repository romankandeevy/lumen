import LumenUI
import SwiftUI

@main
struct LumenApp: App {
    @State private var app: AppModel? = try? AppModel()

    init() {
        // окно — всегда при запуске: иначе macOS восстанавливает «окон не было» и Lumen висит без окна
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
    }

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
