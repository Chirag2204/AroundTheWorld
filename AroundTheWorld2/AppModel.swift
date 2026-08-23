import SwiftUI

@MainActor
@Observable
final class AppModel {
    let launcherWindowID = "LauncherWindow"
    let immersiveSpaceID = "ImmersiveSpace"
    let intelligence = CommodityIntelligenceViewModel()

    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }

    var immersiveSpaceState = ImmersiveSpaceState.closed
}
