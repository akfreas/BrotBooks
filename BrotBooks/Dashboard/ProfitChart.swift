import Charts
import SwiftUI
import BrotBooksKit

/// Cumulative profit (income net − expenses net) through the year, as a soft area + line chart.
struct ProfitChart: View {
    let year: Int
    let points: [DashboardMath.ProfitPoint]
    let total: Decimal

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(Text("Profit · \(String(year))"))
                    AmountText(value: total, size: 28)
                        .accessibilityIdentifier("dashboard.profitTotal")
                }
                Spacer()
                Text("Cumulative, net of expenses").font(.callout).foregroundStyle(.secondary)
            }
            if points.count > 1 {
                chart.frame(height: 180).accessibilityIdentifier("dashboard.chart")
            } else {
                Text("Not enough data for a chart yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard.profitCard")
    }

    private var chart: some View {
        Chart {
            ForEach(points) { point in
                let value = NSDecimalNumber(decimal: point.cumulative).doubleValue
                AreaMark(x: .value("Month", point.month), y: .value("Profit", value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.22), Theme.accent.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Month", point.month), y: .value("Profit", value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Theme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .accessibilityLabel(Text(verbatim: Dates.month(point.date)))
                    .accessibilityValue(Text(verbatim: Money.format(point.cumulative)))
            }
            if points.contains(where: { $0.cumulative < 0 }) {
                RuleMark(y: .value("Zero", 0)).foregroundStyle(Theme.hairline)
            }
        }
        .chartXScale(domain: 0.75...(Double(max(points.count, 2)) + 0.25))
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: points.map(\.month)) { value in
                AxisValueLabel {
                    if let m = value.as(Int.self) { Text(verbatim: Dates.month(ISODate.make(year, m, 1))) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3])).foregroundStyle(Theme.hairline)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(verbatim: Self.compact(v)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Zero plus the data range with a little headroom, so a small dip below zero doesn't add a whole negative tick.
    private var yDomain: ClosedRange<Double> {
        let values = points.map { NSDecimalNumber(decimal: $0.cumulative).doubleValue }
        let low = min(0, values.min() ?? 0), high = max(0, values.max() ?? 0)
        let pad = max((high - low) * 0.08, 1)
        return (low < 0 ? low - pad : 0)...(high + pad)
    }

    static func compact(_ value: Double) -> String {
        let magnitude = abs(value)
        let sign = value < 0 ? "−" : ""
        if magnitude >= 1_000_000 { return "\(sign)€\((magnitude / 1_000_000).formatted(.number.precision(.fractionLength(0...1))))M" }
        if magnitude >= 1_000 { return "\(sign)€\(Int((magnitude / 1_000).rounded()))k" }
        return "\(sign)€\(Int(magnitude))"
    }
}
