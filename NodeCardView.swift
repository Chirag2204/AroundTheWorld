import SwiftUI

/// A polished, semi-transparent spatial card anchored to a physical commodity
/// hub on the globe (e.g. WTI Crude at Cushing, Natural Gas at Henry Hub,
/// Brent Crude at Rotterdam). Reads its live values straight from the shared
/// view model by node id, so it refreshes automatically as the simulated
/// real-time market feed ticks -- no manual re-creation needed.
struct NodeCardView: View {
    let viewModel: CommodityIntelligenceViewModel
    let nodeID: UUID
    let onSelect: (CommodityNode) -> Void

    private var node: CommodityNode? {
        viewModel.commodityNodes.first { $0.id == nodeID }
    }

    var body: some View {
        if let node {
            content(for: node)
        }
    }

    private func content(for node: CommodityNode) -> some View {
        let isPositive = node.percentChange >= 0
        let accentColor: Color = isPositive
            ? Color(red: 0, green: 0.90, blue: 0.46)
            : Color(red: 1, green: 0.09, blue: 0.27)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(node.symbol)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                Spacer()
                Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(accentColor)

            Text(node.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(node.currentPrice.formatted(.currency(code: "USD")))
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .contentTransition(.numericText())

            HStack {
                Text("\(isPositive ? "+" : "")\(node.percentChange.formatted(.number.precision(.fractionLength(2))))%")
                Spacer()
                Text("Vol \(Int(node.volume).formatted(.number.notation(.compactName)))")
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)

            Button {
                onSelect(node)
            } label: {
                Text("Trade / Inspect")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(accentColor.opacity(0.85))
        }
        .padding(14)
        .frame(width: 200)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .background(Color.black.opacity(0.30), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(accentColor.opacity(0.65), lineWidth: 1))
        .shadow(color: accentColor.opacity(0.28), radius: 12)
        .hoverEffect()
        .animation(.easeInOut(duration: 0.35), value: node.currentPrice)
    }
}
