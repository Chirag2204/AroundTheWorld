import SwiftUI

@main
struct AroundTheWorld2App: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup(id: appModel.launcherWindowID) {
            ContentView()
                .environment(appModel)
        }
        .windowStyle(.plain)
        .defaultSize(width: 0.08, height: 0.08)

        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(appModel)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)

        ImmersiveSpace(id: appModel.volSpaceImmersiveSpaceID) {
            VolSpaceImmersiveView(viewModel: appModel.volSpace)
                .environment(appModel)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
