import SwiftUI

@MainActor
@Observable
final class AppModel {
    let launcherWindowID = "LauncherWindow"
    let immersiveSpaceID = "ImmersiveSpace"
    let volSpaceImmersiveSpaceID = "VolSpaceSpace"
    let intelligence = CommodityIntelligenceViewModel()
    let volSpace = VolSpaceViewModel()

    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }

    var immersiveSpaceState = ImmersiveSpaceState.closed
    var volSpaceImmersiveSpaceState = ImmersiveSpaceState.closed
}
