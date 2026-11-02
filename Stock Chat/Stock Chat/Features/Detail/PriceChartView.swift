import SwiftUI
import Charts

struct PriceChartView: View {
    var points: [PricePoint]
    var range: ChartRange
    var baseline: Double?
    @Binding var selection: PricePoint?

    @State private var rawSelection: Date?

    private var color: Color {
        let start = baseline ?? points.first?.price ?? 0
        return Color.trend((points.last?.price ?? start) - start)
    }

    private var domain: ClosedRange<Double> {
        let prices = points.map(\.price) + (baseline.map { [$0] } ?? [])
        let low = prices.min() ?? 0, high = prices.max() ?? 1
        let pad = max((high - low) * 0.08, high * 0.001)
        return (low - pad)...(high + pad)
    }

    var body: some View {
        Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Time", point.date),
                    yStart: .value("Low", domain.lowerBound),
                    yEnd: .value("Price", point.price)
                )
                .foregroundStyle(
                    LinearGradient(colors: [color.opacity(0.32), color.opacity(0.0)], startPoint: .top, endPoint: .bottom)
                )
                .interpolationMethod(.monotone)

                LineMark(x: .value("Time", point.date), y: .value("Price", point.price))
                    .foregroundStyle(color.gradient)
                    .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            if let baseline, range == .day {
                RuleMark(y: .value("Previous close", baseline))
                    .foregroundStyle(.secondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }
            if let selection {
                RuleMark(x: .value("Selected", selection.date))
                    .foregroundStyle(.primary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("Selected", selection.date), y: .value("Price", selection.price))
                    .foregroundStyle(color)
                    .symbolSize(90)
            }
        }
        .chartYScale(domain: domain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel(format: xFormat)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel()
            }
        }
        .chartXSelection(value: $rawSelection)
        .onChange(of: rawSelection) { _, date in
            guard let date else { selection = nil; return }
            selection = points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
        }
        .sensoryFeedback(.selection, trigger: selection?.date)
    }

    private var xFormat: Date.FormatStyle {
        var style: Date.FormatStyle = switch range {
        case .day: .dateTime.hour()
        case .week: .dateTime.weekday(.abbreviated)
        case .month, .sixMonths: .dateTime.month(.abbreviated).day()
        case .year: .dateTime.month(.abbreviated)
        case .fiveYears: .dateTime.year()
        }
        style.timeZone = Market.us.timeZone
        return style
    }
}

struct RangePicker: View {
    @Binding var selection: ChartRange
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ChartRange.allCases) { range in
                Button {
                    withAnimation(.bouncy(duration: 0.35)) { selection = range }
                } label: {
                    Text(range.rawValue)
                        .font(.subheadline.weight(selection == range ? .bold : .medium))
                        .foregroundStyle(selection == range ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if selection == range {
                                Capsule()
                                    .fill(.tint.opacity(0.22))
                                    .matchedGeometryEffect(id: "range", in: namespace)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .glassEffect(.regular.interactive(), in: .capsule)
        .sensoryFeedback(.selection, trigger: selection)
    }
}
