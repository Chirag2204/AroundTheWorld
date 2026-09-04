import Foundation
import Observation
import SwiftUI
import simd

/// State + live feed for the VolSpace room. Mirrors CommodityIntelligenceViewModel's
/// shape (an @Observable class owned by AppModel, a Task-based "live" loop) so the
/// two rooms feel like the same app rather than two bolted-together demos.
@MainActor
@Observable
final class VolSpaceViewModel {
    var selectedProduct: VolProduct = .crudeOil {
        didSet { regenerateSurface() }
    }
    var selectedScenario: VolScenario = .liveMarket {
        didSet { regenerateSurface() }
    }
    var compareMode = false
    var selectedSliceExpiryIndex = 0
    var isSliceVisible = false
    var surfaceRotation = simd_quatf(angle: 0, axis: [0, 1, 0])

    let strikes: [Double] = stride(from: -3.0, through: 3.0, by: 0.3).map { $0 }
    let expiries: [Double] = stride(from: 7.0, through: 180.0, by: 15.0).map { $0 }

    var points: [VolPoint] = []
    var comparePoints: [VolPoint] = []

    /// Bumped only when the surface *geometry* changes (data regeneration or
    /// compare-mode toggle). The RealityView update closure watches this to
    /// decide whether to rebuild meshes, so cheap changes like rotation don't
    /// trigger a full (and asset-race-prone) mesh teardown/regeneration.
    private(set) var contentVersion = 0

    @ObservationIgnored private var liveFeedTask: Task<Void, Never>?
    @ObservationIgnored private var jitterTick: Double = 0

    init() {
        regenerateSurface()
        startLiveFeed()
    }

    deinit {
        liveFeedTask?.cancel()
    }

    var selectedSliceExpiry: Double {
        guard expiries.indices.contains(selectedSliceExpiryIndex) else { return expiries.first ?? 0 }
        return expiries[selectedSliceExpiryIndex]
    }

    var activeSliceExpiry: Double? {
        isSliceVisible ? selectedSliceExpiry : nil
    }

    var sliceSmilePoints: [VolPoint] {
        points.filter { $0.expiryDays == selectedSliceExpiry }
    }

    /// Inverts VolSpaceMesh's z-scale to map a tap's local Z back to the
    /// nearest expiry index -- used to pick which smile slice to show.
    func nearestExpiryIndex(forLocalZ z: Double) -> Int {
        guard !expiries.isEmpty else { return 0 }
        let target = z / Double(VolSpaceMesh.zScale)
        var bestIndex = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, expiry) in expiries.enumerated() {
            let distance = abs(expiry - target)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    func rotateSurface(from startingRotation: simd_quatf, translation: CGSize) {
        let yaw = Float(translation.width) * 0.005
        surfaceRotation = simd_quatf(angle: yaw, axis: [0, 1, 0]) * startingRotation
    }

    func toggleCompareMode() {
        compareMode.toggle()
        if compareMode {
            comparePoints = points
        }
        contentVersion += 1
    }

    private func regenerateSurface() {
        points = VolSurfaceGenerator.generate(product: selectedProduct, scenario: selectedScenario, strikes: strikes, expiries: expiries, jitterSeed: jitterTick)
        if !expiries.indices.contains(selectedSliceExpiryIndex) {
            selectedSliceExpiryIndex = max(expiries.count - 1, 0)
        }
        contentVersion += 1
    }

    /// Simulates a real-time feed with small randomized jitter every second --
    /// swap this for a real WebSocket later without touching anything else.
    private func startLiveFeed() {
        liveFeedTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                withAnimation(.easeInOut(duration: 0.6)) {
                    self.jitterTick += 1
                    self.regenerateSurface()
                }
            }
        }
    }
}
