import SwiftUI
import RealityKit
import UIKit
import Spatial
import simd

/// The VolSpace "room": a second, separate ImmersiveSpace hosting a walkable
/// 3D implied-volatility terrain. Structurally mirrors HorizonImmersiveView
/// (RealityView + rebuildable dynamic content + Attachment-based SwiftUI
/// panels) so it reuses proven patterns rather than inventing new ones.
struct VolSpaceImmersiveView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Bindable var viewModel: VolSpaceViewModel

    @State private var dragStartRotation = simd_quatf(angle: 0, axis: [0, 1, 0])
    @State private var isDraggingSurface = false
    // Mirrors HorizonImmersiveView's isTransitioningRooms guard: prevents a
    // double-tap on "CME Horizon" from firing two overlapping ImmersiveSpace
    // transitions, which is a reliable way to crash the app.
    @State private var isReturningToHorizon = false

    /// Reference-type render bookkeeping held stably across RealityView updates.
    /// Tracks which content version is currently in the scene so the update
    /// closure only rebuilds meshes when the geometry actually changed.
    @State private var render = RenderState()

    var body: some View {
        RealityView { content, attachments in
            let sceneRoot = Entity()
            sceneRoot.name = EntityNames.root
            content.add(sceneRoot)

            sceneRoot.addChild(Self.makeLightRig())

            let surfaceGroup = Entity()
            surfaceGroup.name = EntityNames.surfaceGroup
            surfaceGroup.position = [0, 0.9, -1.3]
            sceneRoot.addChild(surfaceGroup)

            surfaceGroup.addChild(Self.buildSurfaceContent(viewModel: viewModel))
            render.renderedContentVersion = viewModel.contentVersion
            Self.placeAttachments(in: sceneRoot, attachments: attachments)
        } update: { content, attachments in
            // Mirror HorizonImmersiveView's guard: stop all updates while the
            // space is being dismissed so we don't schedule compositor work into
            // a scene being torn down (reduces IOSurface contention on reopen).
            guard !isReturningToHorizon else { return }
            guard let sceneRoot = content.entities.first(where: { $0.name == EntityNames.root }),
                  let surfaceGroup = sceneRoot.findEntity(named: EntityNames.surfaceGroup) else { return }

            // Rotation is a cheap transform update -- never rebuild meshes for it.
            surfaceGroup.transform.rotation = viewModel.surfaceRotation

            // Only tear down and regenerate the (asset-race-prone) procedural
            // meshes when the underlying geometry actually changed.
            if render.renderedContentVersion != viewModel.contentVersion {
                render.renderedContentVersion = viewModel.contentVersion
                if let oldContent = surfaceGroup.findEntity(named: EntityNames.surfaceContent) {
                    oldContent.removeFromParent()
                }
                surfaceGroup.addChild(Self.buildSurfaceContent(viewModel: viewModel))
            }

            Self.placeAttachments(in: sceneRoot, attachments: attachments)
        } attachments: {
            Attachment(id: AttachmentID.controls) {
                VolSpaceControlsView(viewModel: viewModel) {
                    guard !isReturningToHorizon else { return }
                    isReturningToHorizon = true
                    Task {
                        await returnToHorizon()
                        isReturningToHorizon = false
                    }
                }
            }
            Attachment(id: AttachmentID.slice) {
                if let expiry = viewModel.activeSliceExpiry {
                    VolSpaceSliceChartView(expiryDays: expiry, points: viewModel.sliceSmilePoints)
                }
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged { value in
                    guard value.entity.name == EntityNames.surfaceHitTarget else { return }
                    if !isDraggingSurface {
                        isDraggingSurface = true
                        dragStartRotation = viewModel.surfaceRotation
                    }
                    viewModel.rotateSurface(from: dragStartRotation, translation: value.translation)
                }
                .onEnded { _ in
                    isDraggingSurface = false
                    dragStartRotation = viewModel.surfaceRotation
                }
        )
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    guard value.entity.name == EntityNames.surfaceHitTarget else { return }
                    let tapped = value.convert(value.location3D, from: .local, to: value.entity)
                    // Hit target is offset from root origin; add its parent-space Z to
                    // convert from the hit target's local space back to surface space.
                    let surfaceZ = Double(tapped.z) + Double(value.entity.position.z)
                    let index = viewModel.nearestExpiryIndex(forLocalZ: surfaceZ)
                    withAnimation(.smooth(duration: 0.3)) {
                        viewModel.selectedSliceExpiryIndex = index
                        viewModel.isSliceVisible = true
                    }
                }
        )
        .onAppear { appModel.volSpaceImmersiveSpaceState = .open }
        .onDisappear { appModel.volSpaceImmersiveSpaceState = .closed }
    }

    private func returnToHorizon() async {
        appModel.volSpaceImmersiveSpaceState = .inTransition
        await dismissImmersiveSpace()
        // Same IOSurface drain delay as enterVolSpace() in HorizonImmersiveView:
        // VolSpaceImmersiveView has fewer surfaces than Horizon, but the same
        // compositor serialization requirement applies in both directions.
        try? await Task.sleep(for: .milliseconds(800))
        appModel.immersiveSpaceState = .inTransition
        switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
        case .opened:
            appModel.immersiveSpaceState = .open
        case .userCancelled, .error:
            fallthrough
        @unknown default:
            appModel.immersiveSpaceState = .closed
            appModel.volSpaceImmersiveSpaceState = .inTransition
            try? await Task.sleep(for: .milliseconds(600))
            switch await openImmersiveSpace(id: appModel.volSpaceImmersiveSpaceID) {
            case .opened:
                appModel.volSpaceImmersiveSpaceState = .open
            case .userCancelled, .error:
                fallthrough
            @unknown default:
                appModel.volSpaceImmersiveSpaceState = .closed
            }
        }
    }

    private static func buildSurfaceContent(viewModel: VolSpaceViewModel) -> Entity {
        let container = Entity()
        container.name = EntityNames.surfaceContent

        let mainSurface = VolSpaceMesh.buildBandedSurfaceEntity(
            points: viewModel.points,
            strikeCount: viewModel.strikes.count,
            expiryCount: viewModel.expiries.count,
            name: EntityNames.surfaceHitTarget
        )
        container.addChild(mainSurface)

        if viewModel.compareMode,
           let overlayMesh = VolSpaceMesh.buildOverlayMesh(
                points: viewModel.comparePoints,
                strikeCount: viewModel.strikes.count,
                expiryCount: viewModel.expiries.count
           ) {
            let overlay = ModelEntity(mesh: overlayMesh, materials: [VolSpaceMesh.overlayMaterial()])
            overlay.position.y += 0.002
            container.addChild(overlay)
        }

        return container
    }

    private static func makeLightRig() -> Entity {
        let root = Entity()
        let sun = DirectionalLight()
        sun.name = "VolSpace Sun"
        sun.light.intensity = 2800
        sun.light.color = .white
        sun.orientation = simd_quatf(angle: -.pi / 4, axis: [1, 0, 0]) * simd_quatf(angle: .pi / 5, axis: [0, 1, 0])
        root.addChild(sun)

        let accent = PointLight()
        accent.name = "VolSpace Accent Light"
        accent.light.intensity = 1200
        accent.light.color = UIColor(red: 0.55, green: 0.35, blue: 1.0, alpha: 1)
        accent.position = [0.4, 1.2, -0.6]
        root.addChild(accent)
        return root
    }

    private static func placeAttachments(in root: Entity, attachments: RealityViewAttachments) {
        attach(AttachmentID.controls, from: attachments, to: root, position: [0, 1.55, -1.05])
        attach(AttachmentID.slice, from: attachments, to: root, position: [0.85, 1.0, -1.05])
    }

    private static func attach(_ id: String, from attachments: RealityViewAttachments, to root: Entity, position: SIMD3<Float>) {
        guard let entity = attachments.entity(for: id) else { return }
        if entity.parent == nil {
            root.addChild(entity)
        }
        entity.position = position
        entity.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
    }
}

/// Mutable render bookkeeping stored in @State so it survives view struct
/// re-creation. Mutating its properties does not invalidate the view, which is
/// exactly what we want inside the RealityView update closure.
@MainActor
private final class RenderState {
    var renderedContentVersion = -1
}

private enum EntityNames {
    static let root = "VolSpace Root"
    static let surfaceGroup = "VolSpace Surface Group"
    static let surfaceContent = "VolSpace Surface Content"
    static let surfaceHitTarget = "VolSpace Surface Hit Target"
}

private enum AttachmentID {
    static let controls = "volspace-controls"
    static let slice = "volspace-slice"
}
