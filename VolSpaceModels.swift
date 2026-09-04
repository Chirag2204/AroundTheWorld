import Foundation

/// A single point on the implied-volatility surface: one (strike, expiry) node.
/// `strike` is moneyness, normalized roughly -3...+3 with 0 = at-the-money.
/// `expiryDays` is days to expiry, `impliedVol` is a decimal (0.25 = 25%).
struct VolPoint: Identifiable, Hashable, Sendable {
    let id: UUID
    let strike: Double
    let expiryDays: Double
    let impliedVol: Double

    init(id: UUID = UUID(), strike: Double, expiryDays: Double, impliedVol: Double) {
        self.id = id
        self.strike = strike
        self.expiryDays = expiryDays
        self.impliedVol = impliedVol
    }
}

/// The futures/options products VolSpace can show a surface for. Everything
/// downstream (mesh, charts, UI) only depends on `baseIV`/`skewSteepness`, so
/// adding a real product later is a one-case addition here.
enum VolProduct: String, CaseIterable, Identifiable, Hashable, Sendable {
    case esEquityIndex = "ES"
    case crudeOil = "CL"
    case naturalGas = "NG"
    case tenYearNote = "ZN"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .esEquityIndex: "E-mini S&P 500"
        case .crudeOil: "WTI Crude Oil"
        case .naturalGas: "Henry Hub Natural Gas"
        case .tenYearNote: "10-Year T-Note"
        }
    }

    var baseIV: Double {
        switch self {
        case .esEquityIndex: 0.16
        case .crudeOil: 0.32
        case .naturalGas: 0.55
        case .tenYearNote: 0.09
        }
    }

    var skewSteepness: Double {
        switch self {
        case .esEquityIndex: 0.05
        case .crudeOil: 0.02
        case .naturalGas: 0.01
        case .tenYearNote: 0.015
        }
    }
}

/// Pre-baked, named "historical" moments for one-tap demo scenarios -- judges
/// remember a named, dramatic moment better than a generic live feed.
enum VolScenario: String, CaseIterable, Identifiable, Hashable, Sendable {
    case liveMarket = "Live Market"
    case marchVolSpike = "Mar 2020 Vol Spike"
    case calmTuesday = "A Calm Tuesday"
    case postFedSkew = "Post-Fed Skew"

    var id: String { rawValue }

    var levelMultiplier: Double {
        switch self {
        case .liveMarket: 1.0
        case .marchVolSpike: 2.6
        case .calmTuesday: 0.55
        case .postFedSkew: 1.15
        }
    }

    var skewMultiplier: Double {
        switch self {
        case .liveMarket: 1.0
        case .marchVolSpike: 1.8
        case .calmTuesday: 0.6
        case .postFedSkew: 2.1
        }
    }
}

/// Procedural surface generator that stands in for a real CME Datamine feed.
/// Structured so swapping in a real feed later only means replacing the body
/// of `generate(product:scenario:strikes:expiries:jitterSeed:)` -- everything
/// else (mesh, view model, UI) only ever consumes the resulting [VolPoint].
enum VolSurfaceGenerator {
    /// Row-major: all strikes for expiry[0], then all strikes for expiry[1],
    /// etc. -- VolSpaceMesh's index buffer depends on this exact ordering.
    static func generate(product: VolProduct, scenario: VolScenario, strikes: [Double], expiries: [Double], jitterSeed: Double = 0) -> [VolPoint] {
        var points: [VolPoint] = []
        points.reserveCapacity(strikes.count * expiries.count)
        for expiry in expiries {
            for strike in strikes {
                let smile = product.baseIV + product.skewSteepness * scenario.skewMultiplier * pow(strike, 2) - (product.skewSteepness * 0.6) * strike
                let termDecay = 1.0 / sqrt(max(expiry, 1) / 30.0)
                let jitter = sin((strike + expiry + jitterSeed) * 0.37) * 0.004
                let iv = max(0.03, smile * termDecay * scenario.levelMultiplier + jitter)
                points.append(VolPoint(strike: strike, expiryDays: expiry, impliedVol: iv))
            }
        }
        return points
    }
}
