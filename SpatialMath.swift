import Foundation
import simd

/// Spatial Coordinate Math Engine.
///
/// Converts geographic coordinates (latitude/longitude) into 3D Cartesian
/// coordinates on a sphere of a given radius, and produces great-circle arc
/// paths between two coordinates for drawing commodity trade/supply vectors
/// across the globe.
enum GlobeMath {
    static func latLongTo3D(latitude: Double, longitude: Double, radius: Float) -> SIMD3<Float> {
        let lat = Float(latitude * .pi / 180)
        let lon = Float(longitude * .pi / 180)
        let x = radius * cos(lat) * sin(lon)
        let y = radius * sin(lat)
        let z = radius * cos(lat) * cos(lon)
        return SIMD3<Float>(x, y, z)
    }

    static func rotationToFace(latitude: Double, longitude: Double) -> simd_quatf {
        let point = normalize(latLongTo3D(latitude: latitude, longitude: longitude, radius: 1))
        let target = SIMD3<Float>(0, 0, -1)
        return simd_quatf(from: point, to: target)
    }

    /// Produces sample points along the great-circle (slerp) arc between two
    /// geographic coordinates, lifted above the sphere surface so the path
    /// reads as a curved trade/supply vector rather than a chord through the globe.
    static func sphericalArc(from origin: GeoCoordinate, to destination: GeoCoordinate, radius: Float, samples: Int = 28, lift: Float = 0.25) -> [SIMD3<Float>] {
        let start = normalize(latLongTo3D(latitude: origin.latitude, longitude: origin.longitude, radius: radius))
        let end = normalize(latLongTo3D(latitude: destination.latitude, longitude: destination.longitude, radius: radius))
        let dotProduct = min(max(simd_dot(start, end), -1), 1)
        let omega = acos(dotProduct)
        return (0...samples).map { index in
            let t = Float(index) / Float(samples)
            let direction: SIMD3<Float>
            if omega < 0.0001 {
                direction = normalize(mix(start, end, t: t))
            } else {
                let scaleA = sin((1 - t) * omega) / sin(omega)
                let scaleB = sin(t * omega) / sin(omega)
                direction = normalize(start * scaleA + end * scaleB)
            }
            let arcLift = sin(t * .pi) * lift
            return direction * (radius + arcLift)
        }
    }
}
