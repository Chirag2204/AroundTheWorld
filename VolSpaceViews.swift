import SwiftUI
import Charts

/// Bottom control panel for the VolSpace room: product picker, one-tap named
/// scenarios, compare-mode toggle, and the button back to CME Horizon.
struct VolSpaceControlsView: View {
    @Bindable var viewModel: VolSpaceViewModel
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("VolSpace")
                        .font(.system(size: 22, weight: .bold))
                    Text("Walkable Implied Volatility Surface")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                RoomSwitchButton(title: "CME Horizon", systemImage: "globe.americas.fill", tint: .cyan, action: onBack)
            }

            Picker("Product", selection: $viewModel.selectedProduct) {
                ForEach(VolProduct.allCases) { product in
                    Text(product.rawValue).tag(product)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                ForEach(VolScenario.allCases) { scenario in
                    Button {
                        withAnimation(.smooth(duration: 0.4)) {
                            viewModel.selectedScenario = scenario
                        }
                    } label: {
                        Text(scenario.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .background(viewModel.selectedScenario == scenario ? Color.orange.opacity(0.28) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(viewModel.selectedScenario == scenario ? Color.orange.opacity(0.8) : Color.white.opacity(0.12), lineWidth: 1))
                }
            }

            HStack {
                Toggle("Compare Mode", isOn: Binding(
                    get: { viewModel.compareMode },
                    set: { _ in viewModel.toggleCompareMode() }
                ))
                .toggleStyle(.switch)
                Spacer()
                Text("Tap the surface to slice a smile at that expiry")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(22)
        .frame(width: 620)
        .glassPanel(border: Color.orange.opacity(0.45))
    }
}

/// 2D smile chart popped up beside the surface when the person taps a
/// particular expiry row -- much faster to build than true mesh-clipping,
/// per the build guide's own advice.
struct VolSpaceSliceChartView: View {
    let expiryDays: Double
    let points: [VolPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Smile — \(Int(expiryDays))D Expiry")
                .font(.system(size: 18, weight: .semibold))

            Chart(points.sorted { $0.strike < $1.strike }) { point in
                LineMark(
                    x: .value("Strike", point.strike),
                    y: .value("Implied Vol", point.impliedVol)
                )
                .foregroundStyle(Color.cyan)
                PointMark(
                    x: .value("Strike", point.strike),
                    y: .value("Implied Vol", point.impliedVol)
                )
                .foregroundStyle(Color.orange)
            }
            .chartXAxisLabel("Moneyness (strike)")
            .chartYAxisLabel("Implied Vol")
            .frame(height: 220)
        }
        .padding(20)
        .frame(width: 420)
        .glassPanel(border: Color.orange.opacity(0.5))
    }
}
