import SwiftUI

struct ContentView: View {
    var body: some View {
        StartupLauncherView()
    }
}

#Preview(windowStyle: .plain) {
    ContentView()
        .environment(AppModel())
}
