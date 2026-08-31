import Foundation
import Observation
import RealityKit
import SwiftUI
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
    case silver = "SI_F"
    case naturalGas = "NG_F"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .crude: "WTI Crude"
        case .corn: "Corn"
        case .gold: "Gold"
        case .silver: "Silver"
        case .naturalGas: "Natural Gas"
        }
    }

    var symbol: String { rawValue.replacingOccurrences(of: "_F", with: "") }

    var assetClass: CommodityCategory {
        switch self {
        case .crude: .energy
        case .corn: .agriculture
        case .gold: .metals
        case .silver: .metals
        case .naturalGas: .energy
        }
    }

    var focusCoordinate: GeoCoordinate {
        switch self {
        case .crude: GeoCoordinate(latitude: 26.6, longitude: 52.8)
        case .corn: GeoCoordinate(latitude: 41.5, longitude: -93.5)
        case .gold: GeoCoordinate(latitude: -26.2, longitude: 28.0)
        case .silver: GeoCoordinate(latitude: 22.8, longitude: -102.6)
        case .naturalGas: GeoCoordinate(latitude: 29.96, longitude: -92.04)
        }
    }

    var baselinePrice: Double {
        switch self {
        case .crude: 82.4
        case .corn: 478.0
        case .gold: 2415.0
        case .silver: 29.5
        case .naturalGas: 2.45
        }
    }

    var priceUnit: String {
        switch self {
        case .crude: "bbl"
        case .corn: "bu"
        case .gold: "oz"
        case .silver: "oz"
        case .naturalGas: "mmBtu"
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

    var events: [CommodityEvent]
    var candlesByCommodity: [Commodity: [CandleData]]
    let routes: [SupplyRoute]
    @ObservationIgnored private var simulationTask: Task<Void, Never>?
    @ObservationIgnored private var simulationTick = 0

    init() {
        events = MockCommodityData.events
        candlesByCommodity = MockCommodityData.candlesByCommodity
        routes = MockCommodityData.routes
        selectedEvent = MockCommodityData.events.first { $0.commodity == .crude }
        focusedCoordinate = selectedEvent?.coordinate ?? Commodity.crude.focusCoordinate
        startLiveSimulation()
    }

    deinit {
        simulationTask?.cancel()
    }

    var currentEvents: [CommodityEvent] {
        events.filter { $0.commodity == selectedCommodity }
    }

    var currentCandles: [CandleData] {
        candlesByCommodity[selectedCommodity, default: []]
    }

    var latestCandle: CandleData? {
        currentCandles.last
    }

    var previousCandle: CandleData? {
        guard currentCandles.count > 1 else { return nil }
        return currentCandles[currentCandles.count - 2]
    }

    var livePriceChange: Double {
        guard let latestCandle, let previousCandle else { return 0 }
        return latestCandle.close - previousCandle.close
    }

    var livePriceChangePercent: Double {
        guard let previousCandle, previousCandle.close != 0 else { return 0 }
        return livePriceChange / previousCandle.close * 100
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
        case .silver: sensitivity = 1.9
        case .naturalGas: sensitivity = 0.72
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

    private func startLiveSimulation() {
        simulationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                withAnimation(.smooth(duration: 0.6)) {
                    self?.advanceLiveSimulation()
                }
            }
        }
    }

    private func advanceLiveSimulation() {
        simulationTick += 1
        let generatedAt = Date()
        for commodity in Commodity.allCases {
            guard let lastCandle = candlesByCommodity[commodity]?.last else { continue }
            let nextCandle = MockCommodityData.makeLiveCandle(
                commodity: commodity,
                previous: lastCandle,
                timestamp: generatedAt,
                tick: simulationTick
            )
            candlesByCommodity[commodity, default: []].append(nextCandle)
            trimCandleHistory(for: commodity)
        }

        guard simulationTick % 12 == 0 else { return }
        let event = MockCommodityData.makeLiveEvent(at: generatedAt, tick: simulationTick)
        events.insert(event, at: 0)

        if events.count > 28 {
            events.removeLast(events.count - 28)
        }

        if event.commodity == selectedCommodity {
            selectedEvent = event
        }
    }

    private func trimCandleHistory(for commodity: Commodity) {
        let maximumVisibleCandles = 90
        guard var candles = candlesByCommodity[commodity], candles.count > maximumVisibleCandles else { return }
        candles.removeFirst(candles.count - maximumVisibleCandles)
        candlesByCommodity[commodity] = candles
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
        let target = SIMD3<Float>(0, 0, -1)
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
        CommodityEvent(id: UUID(), commodity: .gold, assetClass: .metals, headline: "Global currency hedge surge boosts haven bid", category: .geopolitical, coordinate: GeoCoordinate(latitude: 51.5, longitude: -0.1), severity: 0.51, volumeImpact: "+22% ETF flow", timestamp: baseDate.addingTimeInterval(-6_000), metricImpact: "+22% ETF Flow | Vol +5 pts"),
        CommodityEvent(id: UUID(), commodity: .silver, assetClass: .metals, headline: "Mexican mine labor action tightens refined silver supply", category: .supplyChain, coordinate: GeoCoordinate(latitude: 22.8, longitude: -102.6), severity: 0.63, volumeImpact: "-9.4M oz", timestamp: baseDate.addingTimeInterval(-2_700), metricImpact: "-9.4M oz | Lease +42 bps"),
        CommodityEvent(id: UUID(), commodity: .silver, assetClass: .metals, headline: "Solar manufacturing restock lifts industrial silver demand", category: .macro, coordinate: GeoCoordinate(latitude: 31.2, longitude: 121.5), severity: 0.48, volumeImpact: "+6% demand", timestamp: baseDate.addingTimeInterval(-5_100), metricImpact: "+6% Demand | Spreads firm"),
        CommodityEvent(id: UUID(), commodity: .naturalGas, assetClass: .energy, headline: "Gulf LNG maintenance narrows export feedgas demand", category: .supplyChain, coordinate: GeoCoordinate(latitude: 29.96, longitude: -92.04), severity: -0.36, volumeImpact: "-1.6 bcf/d", timestamp: baseDate.addingTimeInterval(-2_900), metricImpact: "-1.6 bcf/d | Basis -7c"),
        CommodityEvent(id: UUID(), commodity: .naturalGas, assetClass: .energy, headline: "Early winter storage draw raises Henry Hub risk premium", category: .weather, coordinate: GeoCoordinate(latitude: 40.4, longitude: -80.0), severity: 0.71, volumeImpact: "-88 bcf", timestamp: baseDate.addingTimeInterval(-5_700), metricImpact: "-88 bcf | Vol +8 pts")
    ]

    static let routes: [SupplyRoute] = [
        SupplyRoute(commodity: .crude, originCoordinate: GeoCoordinate(latitude: 26.6, longitude: 52.8), destinationCoordinate: GeoCoordinate(latitude: 29.7, longitude: -95.1), volumeCapacity: 2.2, isChoked: true),
        SupplyRoute(commodity: .crude, originCoordinate: GeoCoordinate(latitude: 27.5, longitude: -90.0), destinationCoordinate: GeoCoordinate(latitude: 40.7, longitude: -74.0), volumeCapacity: 1.4, isChoked: false),
        SupplyRoute(commodity: .corn, originCoordinate: GeoCoordinate(latitude: 41.9, longitude: -93.3), destinationCoordinate: GeoCoordinate(latitude: 29.9, longitude: -90.1), volumeCapacity: 0.9, isChoked: false),
        SupplyRoute(commodity: .corn, originCoordinate: GeoCoordinate(latitude: -23.96, longitude: -46.33), destinationCoordinate: GeoCoordinate(latitude: 31.2, longitude: 121.5), volumeCapacity: 1.1, isChoked: true),
        SupplyRoute(commodity: .gold, originCoordinate: GeoCoordinate(latitude: -26.2, longitude: 28.0), destinationCoordinate: GeoCoordinate(latitude: 25.2, longitude: 55.3), volumeCapacity: 0.35, isChoked: true),
        SupplyRoute(commodity: .gold, originCoordinate: GeoCoordinate(latitude: -31.9, longitude: 115.9), destinationCoordinate: GeoCoordinate(latitude: 47.4, longitude: 8.5), volumeCapacity: 0.42, isChoked: false),
        SupplyRoute(commodity: .silver, originCoordinate: GeoCoordinate(latitude: 22.8, longitude: -102.6), destinationCoordinate: GeoCoordinate(latitude: 34.7, longitude: 135.5), volumeCapacity: 0.28, isChoked: true),
        SupplyRoute(commodity: .silver, originCoordinate: GeoCoordinate(latitude: -23.5, longitude: -46.6), destinationCoordinate: GeoCoordinate(latitude: 31.2, longitude: 121.5), volumeCapacity: 0.21, isChoked: false),
        SupplyRoute(commodity: .naturalGas, originCoordinate: GeoCoordinate(latitude: 29.96, longitude: -92.04), destinationCoordinate: GeoCoordinate(latitude: 51.9, longitude: 4.5), volumeCapacity: 1.8, isChoked: false),
        SupplyRoute(commodity: .naturalGas, originCoordinate: GeoCoordinate(latitude: 25.2, longitude: 51.6), destinationCoordinate: GeoCoordinate(latitude: 35.7, longitude: 139.7), volumeCapacity: 2.1, isChoked: true)
    ]

    static let candlesByCommodity: [Commodity: [CandleData]] = [
        .crude: makeCandles(base: 82.4, volatility: 1.8, drift: 0.28),
        .corn: makeCandles(base: 478.0, volatility: 8.2, drift: -0.7),
        .gold: makeCandles(base: 2415.0, volatility: 18.0, drift: 2.6),
        .silver: makeCandles(base: 29.5, volatility: 0.55, drift: 0.035),
        .naturalGas: makeCandles(base: 2.45, volatility: 0.16, drift: -0.004)
    ]

    static func makeCandles(base: Double, volatility: Double, drift: Double) -> [CandleData] {
        (0..<200).map { index in
            let cycle = sin(Double(index) * 0.11) * volatility * 2.1
            let shorterWave = sin(Double(index) * 0.43) * volatility * 0.54
            let trendBend = sin(Double(index) * 0.024) * volatility * 3.0
            let momentum = Double(index) * drift
            let open = max(base * 0.15, base + momentum + cycle + shorterWave + trendBend)
            let close = max(base * 0.15, open + cos(Double(index) * 0.37) * volatility * 0.62 + sin(Double(index) * 0.19) * volatility * 0.24)
            let high = max(open, close) + volatility * (0.58 + Double(index % 5) * 0.10)
            let low = max(base * 0.10, min(open, close) - volatility * (0.52 + Double(index % 4) * 0.11))
            let center = (open + close) / 2
            return CandleData(
                timestamp: baseDate.addingTimeInterval(Double(index - 199) * 900),
                open: open,
                high: high,
                low: low,
                close: close,
                volume: 80_000 + Double(index * 1_150) + abs(shorterWave) * 2_200,
                projectedUpperBand: center + volatility * 2.4,
                projectedLowerBand: center - volatility * 2.1
            )
        }
    }

    static func makeLiveCandle(commodity: Commodity, previous: CandleData, timestamp: Date, tick: Int) -> CandleData {
        let profile = simulationProfile(for: commodity)
        let drift = profile.drift * 0.28 + sin(Double(tick) * profile.cycle) * profile.volatility * 0.035
        let shock = Double.random(in: -profile.volatility...profile.volatility) * 0.18
        let close = max(commodity.baselinePrice * 0.08, previous.close + drift + shock)
        let open = previous.close
        let range = max(abs(close - open), profile.volatility * Double.random(in: 0.18...0.46))
        let high = max(open, close) + range * Double.random(in: 0.12...0.38)
        let low = max(commodity.baselinePrice * 0.05, min(open, close) - range * Double.random(in: 0.12...0.38))
        let center = (open + close) / 2
        return CandleData(
            timestamp: timestamp,
            open: open,
            high: high,
            low: low,
            close: close,
            volume: max(10_000, previous.volume * Double.random(in: 0.94...1.07)),
            projectedUpperBand: center + profile.volatility * 2.4,
            projectedLowerBand: center - profile.volatility * 2.1
        )
    }

    static func makeLiveEvent(at timestamp: Date, tick: Int) -> CommodityEvent {
        let commodity = Commodity.allCases.randomElement() ?? .crude
        let template = eventTemplates[commodity, default: []].randomElement() ?? EventTemplate(
            headline: "\(commodity.title) volatility pulse crosses trader alert threshold",
            category: .macro,
            coordinate: commodity.focusCoordinate,
            volumeImpact: "+2.1% flow",
            metricImpact: "Vol +3 pts"
        )
        let direction = Double.random(in: 0...1) > 0.22 ? 1.0 : -1.0
        let severity = direction * Double.random(in: 0.34...0.88)
        return CommodityEvent(
            id: UUID(),
            commodity: commodity,
            assetClass: commodity.assetClass,
            headline: template.headline,
            category: template.category,
            coordinate: template.coordinate,
            severity: severity,
            volumeImpact: template.volumeImpact,
            timestamp: timestamp.addingTimeInterval(Double(tick % 5)),
            metricImpact: template.metricImpact
        )
    }

    private static func simulationProfile(for commodity: Commodity) -> (volatility: Double, drift: Double, cycle: Double) {
        switch commodity {
        case .crude: (1.8, 0.10, 0.31)
        case .corn: (8.2, -0.18, 0.27)
        case .gold: (18.0, 0.92, 0.23)
        case .silver: (0.55, 0.025, 0.29)
        case .naturalGas: (0.16, -0.002, 0.35)
        }
    }

    private struct EventTemplate {
        let headline: String
        let category: IntelligenceCategory
        let coordinate: GeoCoordinate
        let volumeImpact: String
        let metricImpact: String
    }

    private static let eventTemplates: [Commodity: [EventTemplate]] = [
        .crude: [
            EventTemplate(headline: "Tanker queues lengthen after Gulf loading delays", category: .supplyChain, coordinate: GeoCoordinate(latitude: 29.7, longitude: -95.1), volumeImpact: "+11 vessels", metricImpact: "Queue +11 | Freight +6%"),
            EventTemplate(headline: "OPEC compliance chatter lifts prompt crude spreads", category: .geopolitical, coordinate: GeoCoordinate(latitude: 24.7, longitude: 46.7), volumeImpact: "-650k bpd", metricImpact: "-650k bpd | Spread +41c"),
            EventTemplate(headline: "Refinery outage trims regional crude pull", category: .supplyChain, coordinate: GeoCoordinate(latitude: 30.0, longitude: -93.8), volumeImpact: "-310k bpd", metricImpact: "Runs -310k | Crack +4%")
        ],
        .corn: [
            EventTemplate(headline: "Late-season rain shifts Midwest yield models", category: .weather, coordinate: GeoCoordinate(latitude: 41.9, longitude: -93.3), volumeImpact: "+3.2 bu/acre", metricImpact: "Yield +3.2 bu/ac | Basis -5c"),
            EventTemplate(headline: "River draft restrictions slow export elevator turns", category: .supplyChain, coordinate: GeoCoordinate(latitude: 35.1, longitude: -90.1), volumeImpact: "-18% barge flow", metricImpact: "Barge -18% | FOB +4%"),
            EventTemplate(headline: "Feed demand revision pulls corn balance tighter", category: .macro, coordinate: GeoCoordinate(latitude: 38.6, longitude: -90.2), volumeImpact: "+120M bu", metricImpact: "Use +120M bu | Stocks/use -0.8")
        ],
        .gold: [
            EventTemplate(headline: "Real-yield repricing drives renewed gold hedge demand", category: .macro, coordinate: GeoCoordinate(latitude: 40.7, longitude: -74.0), volumeImpact: "+14% ETF flow", metricImpact: "ETF +14% | Vol +4 pts"),
            EventTemplate(headline: "Refinery backlog tightens kilobar premiums", category: .supplyChain, coordinate: GeoCoordinate(latitude: 47.4, longitude: 8.5), volumeImpact: "+28 bps", metricImpact: "Premium +28 bps | Lease firm"),
            EventTemplate(headline: "Reserve diversification headlines support bullion bids", category: .geopolitical, coordinate: GeoCoordinate(latitude: 39.9, longitude: 116.4), volumeImpact: "+19 tonnes", metricImpact: "+19 tonnes | Futures OI +7%")
        ],
        .silver: [
            EventTemplate(headline: "Photovoltaic procurement wave boosts silver offtake", category: .macro, coordinate: GeoCoordinate(latitude: 31.2, longitude: 121.5), volumeImpact: "+7% demand", metricImpact: "Demand +7% | Lease +18 bps"),
            EventTemplate(headline: "Andean concentrate shipments face rail disruption", category: .supplyChain, coordinate: GeoCoordinate(latitude: -16.5, longitude: -68.1), volumeImpact: "-4.8M oz", metricImpact: "-4.8M oz | TC/RC -6%"),
            EventTemplate(headline: "Mexican permitting delay extends mine restart window", category: .geopolitical, coordinate: GeoCoordinate(latitude: 22.8, longitude: -102.6), volumeImpact: "-3.1M oz", metricImpact: "Restart +21 days | Spread +9c")
        ],
        .naturalGas: [
            EventTemplate(headline: "Cold forecast revision lifts Northeast gas burn", category: .weather, coordinate: GeoCoordinate(latitude: 40.4, longitude: -80.0), volumeImpact: "+2.4 bcf/d", metricImpact: "Burn +2.4 bcf/d | Basis +11c"),
            EventTemplate(headline: "LNG feedgas nominations rebound after maintenance", category: .supplyChain, coordinate: GeoCoordinate(latitude: 29.96, longitude: -92.04), volumeImpact: "+1.2 bcf/d", metricImpact: "Feedgas +1.2 bcf/d | JKM link firm"),
            EventTemplate(headline: "Storage report surprise resets Henry Hub prompt risk", category: .macro, coordinate: GeoCoordinate(latitude: 38.9, longitude: -77.0), volumeImpact: "-42 bcf", metricImpact: "Storage -42 bcf | Vol +5 pts")
        ]
    ]
}
