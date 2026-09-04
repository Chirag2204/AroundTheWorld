import SwiftUI

struct CommodityRibbonView: View {
    @Bindable var viewModel: CommodityIntelligenceViewModel

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Commodity.allCases) { commodity in
                Button {
                    withAnimation(.smooth(duration: 0.45)) {
                        viewModel.selectCommodity(commodity)
                    }
                } label: {
                    VStack(spacing: 2) {
                        Text(commodity.symbol)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                        Text(commodity.assetClass.rawValue)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.plain)
                .background(selectedBackground(for: commodity), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(commodity == viewModel.selectedCommodity ? Color.cyan.opacity(0.85) : Color.white.opacity(0.12), lineWidth: 1))
            }
        }
        .padding(12)
        .glassPanel(border: Color.cyan.opacity(0.45))
    }

    private func selectedBackground(for commodity: Commodity) -> Color {
        commodity == viewModel.selectedCommodity ? Color.cyan.opacity(0.22) : Color.white.opacity(0.055)
    }
}

struct NewsStreamView: View {
    @Bindable var viewModel: CommodityIntelligenceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Event & Intelligence Stream")
                    .font(.system(size: 22, weight: .semibold))
                Text("Gaze and tap an event to focus the globe")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(viewModel.currentEvents) { event in
                        EventCard(event: event, isSelected: event == viewModel.selectedEvent) {
                            withAnimation(.smooth(duration: 0.4)) {
                                viewModel.focus(on: event)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 390)
            .scrollIndicators(.hidden)
        }
        .padding(22)
        .glassPanel(border: Color.cyan.opacity(0.38))
    }
}

private struct EventCard: View {
    let event: CommodityEvent
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    CategoryBadge(category: event.category, severity: event.severity)
                    Spacer()
                    Text(event.timestamp, style: .time)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text(event.headline)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("\(event.coordinate.latitude.formatted(.number.precision(.fractionLength(1))))°, \(event.coordinate.longitude.formatted(.number.precision(.fractionLength(1))))°")
                    Spacer()
                    Text(event.volumeImpact)
                        .foregroundStyle(event.severity >= 0 ? Color(red: 1, green: 0.09, blue: 0.27) : Color(red: 0, green: 0.90, blue: 0.46))
                }
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.cyan.opacity(0.16) : Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? Color.cyan.opacity(0.78) : Color.white.opacity(0.10), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct CategoryBadge: View {
    let category: IntelligenceCategory
    let severity: Double

    var body: some View {
        Text(category.rawValue.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(color, in: Capsule())
    }

    private var color: Color {
        switch category {
        case .geopolitical, .macro: Color(red: 0, green: 0.90, blue: 1)
        case .weather: Color(red: 1, green: 0.70, blue: 0)
        case .supplyChain: severity >= 0 ? Color(red: 1, green: 0.09, blue: 0.27) : Color(red: 0, green: 0.90, blue: 0.46)
        }
    }
}

struct PredictiveScenarioSlider: View {
    @Bindable var viewModel: CommodityIntelligenceViewModel

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("What-If Matrix")
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
                Text("\(Int(viewModel.scenarioSeverity))%")
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(readoutColor)
            }

            Slider(value: $viewModel.scenarioSeverity, in: -100...100, step: 1)
                .tint(readoutColor)

            HStack {
                Text("Surplus / Resolution")
                Spacer()
                Text("Escalation / Choke")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)

            Text(viewModel.liveReadout)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .glassPanel(border: readoutColor.opacity(0.42))
    }

    private var readoutColor: Color {
        viewModel.scenarioSeverity >= 0 ? Color(red: 1, green: 0.09, blue: 0.27) : Color(red: 0, green: 0.90, blue: 0.46)
    }
}

struct PortfolioTileView: View {
    @Bindable var viewModel: CommodityIntelligenceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Portfolio")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Live positions")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(viewModel.totalPortfolioMarketValue.formatted(.currency(code: "USD").precision(.fractionLength(0))))
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(signedCurrency(viewModel.totalPortfolioProfitLoss))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(changeColor(for: viewModel.totalPortfolioProfitLoss))
                }
            }

            VStack(spacing: 7) {
                ForEach(viewModel.portfolioPositions) { position in
                    PortfolioPositionRow(position: position, viewModel: viewModel)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
        .glassPanel(border: changeColor(for: viewModel.totalPortfolioProfitLoss).opacity(0.45))
    }

    private func signedCurrency(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return sign + value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    private func changeColor(for value: Double) -> Color {
        value >= 0 ? Color(red: 0, green: 0.90, blue: 0.46) : Color(red: 1, green: 0.09, blue: 0.27)
    }
}

private struct PortfolioPositionRow: View {
    let position: PortfolioPosition
    let viewModel: CommodityIntelligenceViewModel

    var body: some View {
        let currentPrice = viewModel.currentPrice(for: position.commodity)
        let profitLoss = viewModel.profitLoss(for: position)
        let profitLossPercent = viewModel.profitLossPercent(for: position)

        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(position.commodity.symbol)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                    Text(position.direction.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(directionColor.opacity(0.95), in: Capsule())
                }
                Text("\(position.absoluteQuantity.formatted(.number.precision(.fractionLength(0)))) x \(position.contractMultiplier.formatted(.number.precision(.fractionLength(0))))")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 84, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                Text(currentPrice.formatted(.currency(code: "USD").precision(.fractionLength(2))))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                Text("avg \(position.averageEntryPrice.formatted(.number.precision(.fractionLength(2))))")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            VStack(alignment: .trailing, spacing: 2) {
                Text(signedCurrency(profitLoss))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(changeColor)
                Text("\(signedNumber(profitLossPercent))%")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(changeColor.opacity(0.9))
            }
            .frame(width: 92, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(changeColor.opacity(0.26), lineWidth: 1))
    }

    private var directionColor: Color {
        position.quantity >= 0 ? Color(red: 0, green: 0.90, blue: 0.46) : Color(red: 1, green: 0.70, blue: 0)
    }

    private var changeColor: Color {
        viewModel.profitLoss(for: position) >= 0 ? Color(red: 0, green: 0.90, blue: 0.46) : Color(red: 1, green: 0.09, blue: 0.27)
    }

    private func signedCurrency(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return sign + value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    private func signedNumber(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return sign + value.formatted(.number.precision(.fractionLength(2)))
    }
}

struct EventCalloutView: View {
    let event: CommodityEvent?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(event?.commodity.symbol ?? "CL")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(red: 0, green: 0.90, blue: 1))
                Spacer()
                Text(event?.volumeImpact ?? "Live")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(impactColor)
            }

            Text(event?.headline ?? "Spatial Pulse")
                .font(.system(size: 26, weight: .semibold))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                Text(event?.blogBody ?? "Live risk vector initializing. Select an event to read the complete market context, affected route, and projected pricing impact.")
                    .font(.system(size: 19, weight: .medium))
                    .lineSpacing(6)
                    .foregroundStyle(.primary.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 252)
            .scrollIndicators(.hidden)

            Text(event?.metricImpact ?? "Live risk vector initializing")
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(24)
        .frame(width: 840, alignment: .leading)
        .glassPanel(border: Color.cyan.opacity(0.52))
    }

    private var impactColor: Color {
        (event?.severity ?? 0) >= 0 ? Color(red: 1, green: 0.20, blue: 0.32) : Color(red: 0, green: 0.95, blue: 0.52)
    }
}

struct StartupLauncherView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var didRequestImmersiveSpace = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.001)
            ProgressView()
                .controlSize(.small)
        }
        .frame(width: 10, height: 10)
        .task {
            guard !didRequestImmersiveSpace else { return }
            didRequestImmersiveSpace = true
            appModel.immersiveSpaceState = .inTransition
            switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
            case .opened:
                dismissWindow(id: appModel.launcherWindowID)
            case .userCancelled, .error:
                appModel.immersiveSpaceState = .closed
            @unknown default:
                appModel.immersiveSpaceState = .closed
            }
        }
    }
}

/// A small floating button used to jump between immersive "rooms" (e.g.
/// CME Horizon <-> VolSpace). Reused on both sides of the trip so the
/// affordance looks and behaves identically in both rooms.
struct RoomSwitchButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .bold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .frame(width: 108, height: 72)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1.0)
    }
}

extension View {
    func glassPanel(border: Color) -> some View {
        self
            .background(.ultraThinMaterial.opacity(0.92), in: RoundedRectangle(cornerRadius: 8))
            .background(Color(red: 0.05, green: 0.11, blue: 0.17).opacity(0.70), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(border, lineWidth: 1))
            .shadow(color: .cyan.opacity(0.14), radius: 18, x: 0, y: 0)
    }
}
