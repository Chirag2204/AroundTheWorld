import SwiftUI

struct MarketChartView: View {
    @Bindable var viewModel: CommodityIntelligenceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Reactive Market Analytics")
                        .font(.system(size: 22, weight: .semibold))
                    Text("\(viewModel.selectedCommodity.title) \(viewModel.selectedCommodity.rawValue)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TicketButton(commodity: viewModel.selectedCommodity)
            }

            CandlestickCanvas(
                candles: viewModel.currentCandles,
                scenarioSeverity: viewModel.scenarioSeverity,
                selectedEvent: viewModel.selectedEvent,
                scrubbedCandle: $viewModel.scrubbedCandle
            )
            .frame(height: 260)

            HStack(spacing: 14) {
                MetricTile(title: "Delta P", value: signedCurrency(viewModel.projection.priceDelta))
                MetricTile(title: "Delta Sigma", value: "+\(viewModel.projection.volatilityDelta.formatted(.number.precision(.fractionLength(1))))%")
                MetricTile(title: "Route Flow", value: "\(Int(viewModel.projection.routeCompression * 100))%")
            }
        }
        .padding(22)
        .glassPanel(border: Color.cyan.opacity(0.42))
    }

    private func signedCurrency(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return sign + value.formatted(.currency(code: "USD"))
    }
}

private struct CandlestickCanvas: View {
    let candles: [CandleData]
    let scenarioSeverity: Double
    let selectedEvent: CommodityEvent?
    @Binding var scrubbedCandle: CandleData?

    var body: some View {
        GeometryReader { proxy in
            let plot = proxy.size
            let domain = chartDomain
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    drawGrid(context: context, size: size)
                    drawBands(context: context, size: size, domain: domain)
                    drawCone(context: context, size: size, domain: domain)
                    drawCandles(context: context, size: size, domain: domain)
                    drawSelectedEventMarker(context: context, size: size, domain: domain)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            scrubbedCandle = candle(at: value.location.x, width: plot.width)
                        }
                        .onEnded { _ in scrubbedCandle = nil }
                )

                if let scrubbedCandle {
                    CrosshairTooltip(candle: scrubbedCandle)
                        .position(x: xPosition(for: scrubbedCandle, width: plot.width), y: 48)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
    }

    private var chartDomain: ClosedRange<Double> {
        let lows = candles.map(\.low) + candles.map(\.projectedLowerBand)
        let highs = candles.map(\.high) + candles.map(\.projectedUpperBand)
        let low = lows.min() ?? 0
        let high = highs.max() ?? 1
        let stress = abs(scenarioSeverity) / 100
        let padding = max((high - low) * (0.14 + stress * 0.25), 1)
        return (low - padding)...(high + padding)
    }

    private func y(_ price: Double, height: Double, domain: ClosedRange<Double>) -> Double {
        let span = max(domain.upperBound - domain.lowerBound, 1)
        return height - ((price - domain.lowerBound) / span * height)
    }

    private func xPosition(for candle: CandleData, width: Double) -> Double {
        guard let index = candles.firstIndex(of: candle), candles.count > 1 else { return 0 }
        return Double(index) / Double(candles.count - 1) * width
    }

    private func candle(at x: Double, width: Double) -> CandleData? {
        guard !candles.isEmpty else { return nil }
        let ratio = min(max(x / max(width, 1), 0), 1)
        let index = Int((ratio * Double(candles.count - 1)).rounded())
        return candles[index]
    }

    private func drawGrid(context: GraphicsContext, size: CGSize) {
        var path = Path()
        for row in 0...4 {
            let y = size.height * Double(row) / 4
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.stroke(path, with: .color(.white.opacity(0.08)), lineWidth: 1)
    }

    private func drawBands(context: GraphicsContext, size: CGSize, domain: ClosedRange<Double>) {
        guard candles.count > 1 else { return }
        var upper = Path()
        var lower = Path()
        for candle in candles {
            let x = xPosition(for: candle, width: size.width)
            let upperPoint = CGPoint(x: x, y: y(candle.projectedUpperBand, height: size.height, domain: domain))
            let lowerPoint = CGPoint(x: x, y: y(candle.projectedLowerBand, height: size.height, domain: domain))
            if candle == candles.first {
                upper.move(to: upperPoint)
                lower.move(to: lowerPoint)
            } else {
                upper.addLine(to: upperPoint)
                lower.addLine(to: lowerPoint)
            }
        }
        context.stroke(upper, with: .color(.cyan.opacity(0.52)), lineWidth: 1.5)
        context.stroke(lower, with: .color(.cyan.opacity(0.32)), lineWidth: 1.2)
    }

    private func drawCone(context: GraphicsContext, size: CGSize, domain: ClosedRange<Double>) {
        guard let last = candles.last else { return }
        let stress = scenarioSeverity / 100
        let baseX = xPosition(for: last, width: size.width) * 0.84
        let direction = stress >= 0 ? -1.0 : 1.0
        let spread = abs(stress) * size.height * 0.32 + 8
        let anchorY = y(last.close, height: size.height, domain: domain)
        var cone = Path()
        cone.move(to: CGPoint(x: baseX, y: anchorY))
        cone.addLine(to: CGPoint(x: size.width, y: anchorY + direction * spread))
        cone.addLine(to: CGPoint(x: size.width, y: anchorY - direction * spread * 0.34))
        cone.closeSubpath()
        let color = stress >= 0 ? Color.red : Color.green
        context.fill(cone, with: .color(color.opacity(0.20)))
        context.stroke(cone, with: .color(color.opacity(0.65)), lineWidth: 1.2)
    }

    private func drawCandles(context: GraphicsContext, size: CGSize, domain: ClosedRange<Double>) {
        guard candles.count > 1 else { return }
        let step = size.width / Double(candles.count)
        let bodyWidth = max(step * 0.46, 3)

        for candle in candles {
            let x = xPosition(for: candle, width: size.width)
            let isUp = candle.close >= candle.open
            let color = isUp ? Color(red: 0, green: 0.90, blue: 0.46) : Color(red: 1, green: 0.09, blue: 0.27)
            var wick = Path()
            wick.move(to: CGPoint(x: x, y: y(candle.high, height: size.height, domain: domain)))
            wick.addLine(to: CGPoint(x: x, y: y(candle.low, height: size.height, domain: domain)))
            context.stroke(wick, with: .color(color.opacity(0.86)), lineWidth: 1.2)

            let openY = y(candle.open, height: size.height, domain: domain)
            let closeY = y(candle.close, height: size.height, domain: domain)
            let rect = CGRect(x: x - bodyWidth / 2, y: min(openY, closeY), width: bodyWidth, height: max(abs(openY - closeY), 2))
            context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color.opacity(0.80)))
        }
    }

    private func drawSelectedEventMarker(context: GraphicsContext, size: CGSize, domain: ClosedRange<Double>) {
        guard selectedEvent != nil, let marker = candles.dropFirst(candles.count / 2).first else { return }
        let x = xPosition(for: marker, width: size.width)
        let top = y(marker.high, height: size.height, domain: domain) - 12
        var path = Path()
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: size.height))
        context.stroke(path, with: .color(.red.opacity(0.46)), style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
        context.fill(Path(ellipseIn: CGRect(x: x - 5, y: top - 5, width: 10, height: 10)), with: .color(.red))
    }
}

private struct CrosshairTooltip: View {
    let candle: CandleData

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(candle.timestamp, style: .time)
                .font(.caption.bold())
            Text("O \(format(candle.open))  H \(format(candle.high))")
            Text("L \(format(candle.low))  C \(format(candle.close))")
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .padding(8)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.cyan.opacity(0.45), lineWidth: 1))
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }
}

private struct TicketButton: View {
    let commodity: Commodity

    var body: some View {
        Button {
        } label: {
            VStack(spacing: 2) {
                Text("Simulate")
                    .font(.system(size: 12, weight: .semibold))
                Text("CME Hedge")
                    .font(.system(size: 12, weight: .medium))
            }
            .frame(width: 94, height: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color(red: 0, green: 0.68, blue: 0.78))
        .accessibilityLabel("Simulate CME hedge for \(commodity.title)")
    }
}

private struct MetricTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }
}
