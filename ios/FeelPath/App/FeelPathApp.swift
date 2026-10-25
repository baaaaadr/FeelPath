import SwiftUI

@main
struct FeelPathApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
        .onChange(of: scenePhase) { _, phase in
            // ARKit and the camera stop in the background anyway; stop cleanly so the
            // user is never left trusting a cane that went silent.
            if phase == .background { model.stop() }
        }
    }
}
