import Foundation
import Observation
import RealityKit
import simd

struct GeoCoordinate: Hashable, Sendable {
    let latitude: Double
    let longitude: Double
}

enum CommodityCategory: String, CaseIterable, Identifiable, Sendable {
    case energy = "Energy"
    case agriculture = "Agriculture"
    case metals = "Metals"

    var id: String { rawValue }
}

enum Commodity: String, CaseIterable, Identifiable, Sendable {
    case crude = "CL_F"
    case corn = "ZC_F"
    case gold = "GC_F"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .crude: "WTI Crude"
        case .corn: "Corn"
        case .gold: "Gold"
        }
    }

    var symbol: String { rawValue.replacingOccurrences(of: "_F", with: "") }

    var assetClass: CommodityCategory {
        switch self {
        case .crude: .energy
        case .corn: .agriculture
        case .gold: .metals
        }
    }

    var focusCoordinate: GeoCoordinate {
        switch self {
        case .crude: GeoCoordinate(latitude: 26.6, longitude: 52.8)
        case .corn: GeoCoordinate(latitude: 41.5, longitude: -93.5)
        case .gold: GeoCoordinate(latitude: -26.2, longitude: 28.0)
        }
    }

    var baselinePrice: Double {
        switch self {
        case .crude: 82.4
        case .corn: 478.0
        case .gold: 2415.0
        }
    }

    var priceUnit: String {
        switch self {
        case .crude: "bbl"
        case .corn: "bu"
        case .gold: "oz"
        }
    }
}

enum IntelligenceCategory: String, CaseIterable, Identifiable, Sendable {
    case geopolitical = "Geopolitical"
    case weather = "Weather"
    case supplyChain = "Supply Chain"
    case macro = "Macro"

    var id: String { rawValue }
}

struct CommodityEvent: Identifiable, Hashable, Sendable {
    let id: UUID
    let commodity: Commodity
    let assetClass: CommodityCategory
    let headline: String
    let category: IntelligenceCategory
    let coordinate: GeoCoordinate
    let severity: Double
    let volumeImpact: String
    let timestamp: Date
    let metricImpact: String
}

struct CandleData: Identifiable, Hashable, Sendable {
    let id = UUID()
    let timestamp: Date
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Double
    let projectedUpperBand: Double
    let projectedLowerBand: Double
}

struct SupplyRoute: Identifiable, Hashable, Sendable {
    let id = UUID()
    let commodity: Commodity
    let originCoordinate: GeoCoordinate
    let destinationCoordinate: GeoCoordinate
    let volumeCapacity: Double
    let isChoked: Bool
}

struct ProjectionMetrics: Sendable {
    let priceDelta: Double
    let volatilityDelta: Double
    let marginShift: Double
    let routeCompression: Double
}

@MainActor
@Observable
final class CommodityIntelligenceViewModel {
    var selectedCommodity: Commodity = .crude {
        didSet {
            selectedEvent = events.first { $0.commodity == selectedCommodity }
            focusedCoordinate = selectedEvent?.coordinate ?? selectedCommodity.focusCoordinate
        }
    }

    var selectedEvent: CommodityEvent? {
        didSet {
            if let selectedEvent {
                focusedCoordinate = selectedEvent.coordinate
            }
        }
    }

    var scenarioSeverity: Double = 0
    var scrubbedCandle: CandleData?
    var focusedCoordinate: GeoCoordinate = Commodity.crude.focusCoordinate

    let events: [CommodityEvent]
    let candlesByCommodity: [Commodity: [CandleData]]
    let routes: [SupplyRoute]

    init() {
        events = MockCommodityData.events
        candlesByCommodity = MockCommodityData.candlesByCommodity
        routes = MockCommodityData.routes
        selectedEvent = MockCommodityData.events.first { $0.commodity == .crude }
        focusedCoordinate = selectedEvent?.coordinate ?? Commodity.crude.focusCoordinate
    }

    var currentEvents: [CommodityEvent] {
        events.filter { $0.commodity == selectedCommodity }
    }

    var currentCandles: [CandleData] {
        candlesByCommodity[selectedCommodity, default: []]
    }

    var currentRoutes: [SupplyRoute] {
        routes.filter { $0.commodity == selectedCommodity }
    }

    var projection: ProjectionMetrics {
        let stress = scenarioSeverity / 100
        let sensitivity: Double
        switch selectedCommodity {
        case .crude: sensitivity = 14.2
        case .corn: sensitivity = 62.0
        case .gold: sensitivity = 118.0
        }
        return ProjectionMetrics(
            priceDelta: sensitivity * stress,
            volatilityDelta: 18 * abs(stress),
            marginShift: 12 * abs(stress),
            routeCompression: max(0.35, 1 - abs(stress) * 0.45)
        )
    }

    var liveReadout: String {
        let sign = projection.priceDelta >= 0 ? "+" : ""
        return "Projected \(selectedCommodity.title) Impact: \(sign)\(projection.priceDelta.formatted(.currency(code: "USD")))/\(selectedCommodity.priceUnit) | CME Initial Margin Shift: +\(Int(projection.marginShift))%"
    }

    func selectCommodity(_ commodity: Commodity) {
        selectedCommodity = commodity
    }

    func focus(on event: CommodityEvent) {
        selectedEvent = event
    }

    func rotationToFocusedCoordinate() -> simd_quatf {
        GlobeMath.rotationToFace(latitude: focusedCoordinate.latitude, longitude: focusedCoordinate.longitude)
    }
}

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
        let target = SIMD3<Float>(0, 0, 1)
        return simd_quatf(from: point, to: target)
    }

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

private enum MockCommodityData {
    static let baseDate = Date(timeIntervalSince1970: 1_787_356_800)

    static let events: [CommodityEvent] = [
        CommodityEvent(id: UUID(), commodity: .crude, assetClass: .energy, headline: "Strait of Hormuz naval tension raises tanker insurance", category: .geopolitical, coordinate: GeoCoordinate(latitude: 26.6, longitude: 56.25), severity: 0.86, volumeImpact: "-2.4M bpd", timestamp: baseDate.addingTimeInterval(-1_800), metricImpact: "-2.4M bpd | Freight +18%"),
        CommodityEvent(id: UUID(), commodity: .crude, assetClass: .energy, headline: "Red Sea rerouting extends crude transit into Europe", category: .supplyChain, coordinate: GeoCoordinate(latitude: 15.6, longitude: 42.2), severity: 0.64, volumeImpact: "+14 days", timestamp: baseDate.addingTimeInterval(-3_600), metricImpact: "+14 Days | VLCC spread +9%"),
        CommodityEvent(id: UUID(), commodity: .crude, assetClass: .energy, headline: "Gulf of Mexico hurricane warning threatens offshore output", category: .weather, coordinate: GeoCoordinate(latitude: 27.5, longitude: -90.0), severity: 0.72, volumeImpact: "-1.1M bpd", timestamp: baseDate.addingTimeInterval(-5_400), metricImpact: "-1.1M bpd | Shut-in risk 34%"),
        CommodityEvent(id: UUID(), commodity: .corn, assetClass: .agriculture, headline: "US Midwest drought heat dome cuts yield estimates", category: .weather, coordinate: GeoCoordinate(latitude: 41.9, longitude: -93.3), severity: 0.81, volumeImpact: "-8.7 bu/acre", timestamp: baseDate.addingTimeInterval(-2_400), metricImpact: "Yield -8.7 bu/ac | Basis +11c"),
        CommodityEvent(id: UUID(), commodity: .corn, assetClass: .agriculture, headline: "Black Sea grain corridor blockade slows inspections", category: .geopolitical, coordinate: GeoCoordinate(latitude: 46.5, longitude: 30.7), severity: 0.76, volumeImpact: "-420k mt/week", timestamp: baseDate.addingTimeInterval(-4_200), metricImpact: "-420k mt/week | FOB +6%"),
        CommodityEvent(id: UUID(), commodity: .corn, assetClass: .agriculture, headline: "Brazilian port strike delays Santos loading windows", category: .supplyChain, coordinate: GeoCoordinate(latitude: -23.96, longitude: -46.33), severity: 0.58, volumeImpact: "+9 days", timestamp: baseDate.addingTimeInterval(-7_200), metricImpact: "+9 Days | Queue +31 vessels"),
        CommodityEvent(id: UUID(), commodity: .gold, assetClass: .metals, headline: "Central bank reserve accumulation lifts physical demand", category: .macro, coordinate: GeoCoordinate(latitude: 39.9, longitude: 116.4), severity: -0.42, volumeImpact: "+38 tonnes", timestamp: baseDate.addingTimeInterval(-2_100), metricImpact: "+38 tonnes | Lease rates firm"),
        CommodityEvent(id: UUID(), commodity: .gold, assetClass: .metals, headline: "South African mine power grid failure disrupts refining", category: .supplyChain, coordinate: GeoCoordinate(latitude: -26.2, longitude: 28.0), severity: 0.68, volumeImpact: "-185k oz", timestamp: baseDate.addingTimeInterval(-4_800), metricImpact: "-185k oz | Refining -12%"),
        CommodityEvent(id: UUID(), commodity: .gold, assetClass: .metals, headline: "Global currency hedge surge boosts haven bid", category: .geopolitical, coordinate: GeoCoordinate(latitude: 51.5, longitude: -0.1), severity: 0.51, volumeImpact: "+22% ETF flow", timestamp: baseDate.addingTimeInterval(-6_000), metricImpact: "+22% ETF Flow | Vol +5 pts")
    ]

    static let routes: [SupplyRoute] = [
        SupplyRoute(commodity: .crude, originCoordinate: GeoCoordinate(latitude: 26.6, longitude: 52.8), destinationCoordinate: GeoCoordinate(latitude: 29.7, longitude: -95.1), volumeCapacity: 2.2, isChoked: true),
        SupplyRoute(commodity: .crude, originCoordinate: GeoCoordinate(latitude: 27.5, longitude: -90.0), destinationCoordinate: GeoCoordinate(latitude: 40.7, longitude: -74.0), volumeCapacity: 1.4, isChoked: false),
        SupplyRoute(commodity: .corn, originCoordinate: GeoCoordinate(latitude: 41.9, longitude: -93.3), destinationCoordinate: GeoCoordinate(latitude: 29.9, longitude: -90.1), volumeCapacity: 0.9, isChoked: false),
        SupplyRoute(commodity: .corn, originCoordinate: GeoCoordinate(latitude: -23.96, longitude: -46.33), destinationCoordinate: GeoCoordinate(latitude: 31.2, longitude: 121.5), volumeCapacity: 1.1, isChoked: true),
        SupplyRoute(commodity: .gold, originCoordinate: GeoCoordinate(latitude: -26.2, longitude: 28.0), destinationCoordinate: GeoCoordinate(latitude: 25.2, longitude: 55.3), volumeCapacity: 0.35, isChoked: true),
        SupplyRoute(commodity: .gold, originCoordinate: GeoCoordinate(latitude: -31.9, longitude: 115.9), destinationCoordinate: GeoCoordinate(latitude: 47.4, longitude: 8.5), volumeCapacity: 0.42, isChoked: false)
    ]

    static let candlesByCommodity: [Commodity: [CandleData]] = [
        .crude: makeCandles(base: 82.4, volatility: 1.8, drift: 0.28),
        .corn: makeCandles(base: 478.0, volatility: 8.2, drift: -0.7),
        .gold: makeCandles(base: 2415.0, volatility: 18.0, drift: 2.6)
    ]

    static func makeCandles(base: Double, volatility: Double, drift: Double) -> [CandleData] {
        (0..<36).map { index in
            let wave = sin(Double(index) * 0.62) * volatility
            let momentum = Double(index) * drift
            let open = base + momentum + wave
            let close = open + cos(Double(index) * 0.47) * volatility * 0.7
            let high = max(open, close) + volatility * (0.7 + Double(index % 4) * 0.12)
            let low = min(open, close) - volatility * (0.62 + Double(index % 3) * 0.14)
            let center = (open + close) / 2
            return CandleData(
                timestamp: baseDate.addingTimeInterval(Double(index - 35) * 900),
                open: open,
                high: high,
                low: low,
                close: close,
                volume: 80_000 + Double(index * 4_700),
                projectedUpperBand: center + volatility * 2.4,
                projectedLowerBand: center - volatility * 2.1
            )
        }
    }
}
