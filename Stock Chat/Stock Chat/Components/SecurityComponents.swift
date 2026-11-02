import SwiftUI
import SwiftData
import Charts

/// In-memory logo cache so list rows don't refetch images as they are recycled.
enum LogoCache {
    private static let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 400
        return cache
    }()

    static func cached(_ url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    static func load(_ url: URL) async -> UIImage? {
        if let image = cached(url) { return image }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = await UIImage(data: data)?.byPreparingForDisplay()
        else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

struct LogoView: View {
    var symbol: String
    var url: URL?
    var size: CGFloat = 40

    @State private var loaded: UIImage?

    var body: some View {
        let image = loaded ?? url.flatMap { LogoCache.cached($0) }
        ZStack {
            monogram
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.14)
                    .background(.white)
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.28))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.28)
                .strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
        }
        .task(id: url) {
            guard let url, LogoCache.cached(url) == nil else { return }
            let image = await LogoCache.load(url)
            withAnimation(.easeOut(duration: 0.2)) { loaded = image }
        }
    }

    private var monogram: some View {
        let letters = String(symbol.replacingOccurrences(of: "^", with: "").prefix(symbol.count > 4 ? 2 : 1))
        return LinearGradient(
            colors: [Self.color(for: symbol), Self.color(for: symbol).opacity(0.6)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Text(letters)
                .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private static func color(for symbol: String) -> Color {
        let palette: [Color] = [.blue, .indigo, .purple, .teal, .cyan, .mint, .orange, .pink]
        let hash = symbol.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[hash % palette.count]
    }
}

struct ChangeBadge: View {
    var percent: Double?
    var compact = false

    var body: some View {
        HStack(spacing: 3) {
            if !compact, let percent {
                Image(systemName: percent >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(.system(size: 8, weight: .bold))
            }
            Text(Fmt.percent(percent))
                .monospacedDigit()
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.trend(percent).gradient, in: .capsule)
    }
}

struct SparklineView: View {
    var points: [PricePoint]
    var baseline: Double?

    var body: some View {
        let prices = points.map(\.price)
        let lower = min(prices.min() ?? 0, baseline ?? .infinity)
        let upper = max(prices.max() ?? 1, baseline ?? -.infinity)
        let color = Color.trend((points.last?.price ?? 0) - (baseline ?? points.first?.price ?? 0))
        Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    yStart: .value("Low", lower),
                    yEnd: .value("Price", point.price)
                )
                .foregroundStyle(
                    LinearGradient(colors: [color.opacity(0.35), color.opacity(0)], startPoint: .top, endPoint: .bottom)
                )
                .interpolationMethod(.catmullRom)
                LineMark(x: .value("Date", point.date), y: .value("Price", point.price))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.catmullRom)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartYScale(domain: lower...max(upper, lower + 0.0001))
        .accessibilityHidden(true)
    }
}

/// Toggles the star for a security; stars drive the home watchlist and news feed.
struct StarButton: View {
    var ref: SecurityRef
    @Environment(\.modelContext) private var context
    @Query private var stars: [StarredSymbol]

    var body: some View {
        let starred = Stars.isStarred(ref, in: stars)
        Button {
            withAnimation(.bouncy) { Stars.toggle(ref, in: context) }
        } label: {
            Label(starred ? "Unstar" : "Star", systemImage: starred ? "star.fill" : "star")
                .foregroundStyle(starred ? .yellow : .primary)
                .contentTransition(.symbolEffect(.replace))
        }
        .tint(starred ? .yellow : .primary)
        .sensoryFeedback(.selection, trigger: starred)
    }
}

struct SecurityRow: View {
    var item: SecuritySummary
    var starred = false
    var showsKind = false
    @Environment(MarketData.self) private var marketData

    var body: some View {
        HStack(spacing: 12) {
            LogoView(symbol: item.symbol, url: marketData.provider(for: item.market).logoURL(for: item.symbol), size: 42)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.symbol)
                        .font(.headline)
                    if starred {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                    if showsKind {
                        Text(item.kind.title)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.tint.opacity(0.15), in: .capsule)
                            .foregroundStyle(.tint)
                    }
                }
                Text(item.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                if let price = item.price {
                    Text(Fmt.price(price))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
                if let cap = item.marketCap, cap > 0 {
                    Text(Fmt.compactCurrency(cap))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let exchange = item.exchange {
                    Text(exchange)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(.rect)
    }
}
