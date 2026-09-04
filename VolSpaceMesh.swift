import RealityKit
import UIKit
import simd

/// Mesh + material construction for the VolSpace implied-volatility terrain.
///
/// Deliberately avoids texture-sampled materials -- the build guide itself
/// flags that as "nice-to-have, don't over-invest" and a real risk under time
/// pressure. Instead the surface is split into a handful of flat-shaded
/// height/IV bands, which only uses the same MeshDescriptor + SimpleMaterial
/// primitives already proven elsewhere in this app (see HorizonImmersiveView's
/// earthMesh / landMaterial).
enum VolSpaceMesh {
    static let xScale: Float = 0.15
    static let zScale: Float = 0.012
    static let heightScale: Float = 0.6
    static let bandCount = 6

    static func vertexPosition(strike: Double, expiryDays: Double, impliedVol: Double, maxIV: Double) -> SIMD3<Float> {
        let x = Float(strike) * xScale
        let z = Float(expiryDays) * zScale
        let y = Float(impliedVol / max(maxIV, 0.0001)) * heightScale
        return SIMD3(x, y, z)
    }

    /// Builds the colored terrain as a handful of child ModelEntities (one per
    /// IV band), all sharing `name` so gesture hit-testing works no matter
    /// which band under the finger/pointer was hit.
    static func buildBandedSurfaceEntity(points: [VolPoint], strikeCount: Int, expiryCount: Int, name: String) -> Entity {
        let root = Entity()
        root.name = name
        guard points.count == strikeCount * expiryCount, strikeCount > 1, expiryCount > 1 else { return root }

        let maxIV = points.map(\.impliedVol).max() ?? 1.0
        let minIV = points.map(\.impliedVol).min() ?? 0.0
        let span = max(maxIV - minIV, 0.0001)

        var bandVertices: [[SIMD3<Float>]] = Array(repeating: [], count: bandCount)
        var bandIndices: [[UInt32]] = Array(repeating: [], count: bandCount)

        for row in 0..<(expiryCount - 1) {
            for col in 0..<(strikeCount - 1) {
                let tl = points[row * strikeCount + col]
                let tr = points[row * strikeCount + col + 1]
                let bl = points[(row + 1) * strikeCount + col]
                let br = points[(row + 1) * strikeCount + col + 1]

                let averageIV = (tl.impliedVol + tr.impliedVol + bl.impliedVol + br.impliedVol) / 4
                let t = (averageIV - minIV) / span
                let band = min(bandCount - 1, max(0, Int(t * Double(bandCount))))

                let tlPos = vertexPosition(strike: tl.strike, expiryDays: tl.expiryDays, impliedVol: tl.impliedVol, maxIV: maxIV)
                let trPos = vertexPosition(strike: tr.strike, expiryDays: tr.expiryDays, impliedVol: tr.impliedVol, maxIV: maxIV)
                let blPos = vertexPosition(strike: bl.strike, expiryDays: bl.expiryDays, impliedVol: bl.impliedVol, maxIV: maxIV)
                let brPos = vertexPosition(strike: br.strike, expiryDays: br.expiryDays, impliedVol: br.impliedVol, maxIV: maxIV)

                let baseIndex = UInt32(bandVertices[band].count)
                bandVertices[band].append(contentsOf: [tlPos, blPos, trPos, brPos])
                bandIndices[band].append(contentsOf: [
                    baseIndex, baseIndex + 1, baseIndex + 2,
                    baseIndex + 2, baseIndex + 1, baseIndex + 3
                ])
            }
        }

        for band in 0..<bandCount {
            guard !bandIndices[band].isEmpty else { continue }
            var descriptor = MeshDescriptor(name: "VolSpace Band \(band)")
            descriptor.positions = MeshBuffers.Positions(bandVertices[band])
            descriptor.primitives = .triangles(bandIndices[band])
            guard let mesh = try? MeshResource.generate(from: [descriptor]) else { continue }

            let t = Float(band) / Float(max(bandCount - 1, 1))
            let material = SimpleMaterial(color: heatColor(t), isMetallic: false)
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.name = name
            root.addChild(entity)
        }

        // Use a single invisible box entity for hit testing instead of
        // generateCollisionShapes(recursive:true), which crashes RealityKit when
        // called on entities not yet attached to a scene.
        let xVals = points.map { Float($0.strike) * xScale }
        let zVals = points.map { Float($0.expiryDays) * zScale }
        let minX = xVals.min() ?? 0, maxX = xVals.max() ?? 0
        let minZ = zVals.min() ?? 0, maxZ = zVals.max() ?? 0
        let hitTarget = Entity()
        hitTarget.name = name
        hitTarget.position = [(minX + maxX) / 2, heightScale / 2, (minZ + maxZ) / 2]
        hitTarget.components.set(InputTargetComponent())
        hitTarget.components.set(CollisionComponent(shapes: [
            .generateBox(width: (maxX - minX) + 0.08, height: heightScale + 0.08, depth: (maxZ - minZ) + 0.08)
        ]))
        root.addChild(hitTarget)
        return root
    }

    /// A single, simple (non-banded) translucent mesh for the before/after
    /// compare-mode overlay -- visual only, not a gesture target.
    static func buildOverlayMesh(points: [VolPoint], strikeCount: Int, expiryCount: Int) -> MeshResource? {
        guard points.count == strikeCount * expiryCount, strikeCount > 1, expiryCount > 1 else { return nil }
        let maxIV = points.map(\.impliedVol).max() ?? 1.0

        var vertices: [SIMD3<Float>] = []
        vertices.reserveCapacity(points.count)
        for point in points {
            vertices.append(vertexPosition(strike: point.strike, expiryDays: point.expiryDays, impliedVol: point.impliedVol, maxIV: maxIV))
        }

        var indices: [UInt32] = []
        indices.reserveCapacity((strikeCount - 1) * (expiryCount - 1) * 6)
        for row in 0..<(expiryCount - 1) {
            for col in 0..<(strikeCount - 1) {
                let tl = UInt32(row * strikeCount + col)
                let tr = tl + 1
                let bl = UInt32((row + 1) * strikeCount + col)
                let br = bl + 1
                indices.append(contentsOf: [tl, bl, tr])
                indices.append(contentsOf: [tr, bl, br])
            }
        }

        var descriptor = MeshDescriptor(name: "VolSpace Compare Overlay")
        descriptor.positions = MeshBuffers.Positions(vertices)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    static func overlayMaterial() -> UnlitMaterial {
        var material = UnlitMaterial(color: .white)
        material.blending = .transparent(opacity: 0.35)
        return material
    }

    static func heatColor(_ t: Float) -> UIColor {
        let clamped = min(max(t, 0), 1)
        if clamped < 0.5 {
            return UIColor(red: 0, green: CGFloat(clamped * 2), blue: CGFloat(1 - clamped * 2), alpha: 1)
        }
        let upper = clamped - 0.5
        return UIColor(red: CGFloat(upper * 2), green: CGFloat(1 - upper * 2), blue: 0, alpha: 1)
    }
}
