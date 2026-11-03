import SwiftUI
import SwiftData

@Observable
final class HomeModel {
    var indices: [Quote] = []
    var quotes: [String: Quote] = [:]
    var sparklines: [String: [PricePoint]] = [:]
    var news: [NewsArticle] = []
    var isLoadingNews = false
    var error: String?

    func load(symbols: [String], provider: any MarketDataProvider, market: Market) async {
        error = nil
        isLoadingNews = news.isEmpty && !symbols.isEmpty
        async let indexQuotes = provider.quotes(market.benchmarkIndices)
        async let starQuotes = provider.quotes(symbols)
        async let feed = provider.news(for: symbols, limit: 40)

        do {
            indices = try await indexQuotes
        } catch {
            self.error = error.localizedDescription
        }
        if let quotes = try? await starQuotes {
            self.quotes = Dictionary(quotes.map { ($0.symbol, $0) }, uniquingKeysWith: { a, _ in a })
        }
        do {
            news = try await feed
        } catch {
            if symbols.isEmpty { news = [] } else { self.error = self.error ?? error.localizedDescription }
        }
        isLoadingNews = false

        await withTaskGroup(of: (String, [PricePoint]?).self) { group in
            for symbol in symbols where sparklines[symbol] == nil {
                group.addTask { (symbol, try? await provider.history(symbol, range: .month)) }
            }
            for await (symbol, points) in group {
                if let points { sparklines[symbol] = points }
            }
        }
    }
}

struct HomeView: View {
    @Binding var market: Market
    @Environment(MarketData.self) private var marketData
    @Environment(AppRouter.self) private var router: AppRouter?
    @Query(sort: \StarredSymbol.starredAt) private var allStars: [StarredSymbol]
    @State private var model = HomeModel()

    private var stars: [StarredSymbol] { allStars.filter { $0.market == market } }
    private var starKey: String { stars.map(\.symbol).joined(separator: ",") + market.rawValue }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let error = model.error {
                    ErrorBanner(message: error) { Task { await reload() } }
                }
                indicesStrip
                watchlist
                newsSection
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .background { AppBackground() }
        .navigationTitle("Markets")
        .navigationSubtitle(Date.now.formatted(.dateTime.weekday(.wide).month().day()))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Settings", systemImage: "gearshape") { router?.isSettingsPresented = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Market", selection: $market) {
                        ForEach(marketData.availableMarkets) { market in
                            Text("\(market.flag) \(market.displayName)").tag(market)
                        }
                    }
                } label: {
                    Text(market.flag)
                        .font(.title3)
                }
                .accessibilityLabel("Market: \(market.displayName)")
            }
        }
        .task(id: starKey) { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        await model.load(symbols: stars.map(\.symbol), provider: marketData.provider(for: market), market: market)
    }

    // MARK: Sections

    @ViewBuilder
    private var indicesStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    if model.indices.isEmpty {
                        ForEach(market.benchmarkIndices, id: \.self) { symbol in
                            IndexChip(symbol: symbol, quote: nil)
                        }
                    } else {
                        ForEach(model.indices, id: \.symbol) { quote in
                            NavigationLink(value: SecurityRef(symbol: quote.symbol, name: quote.name ?? quote.symbol, kind: .index, market: market)) {
                                IndexChip(symbol: quote.symbol, quote: quote)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .scrollClipDisabled()
    }

    @ViewBuilder
    private var watchlist: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Starred", systemImage: "star.fill", trailing: stars.isEmpty ? nil : "\(stars.count)")
            if stars.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("No stars yet", systemImage: "star")
                            .font(.headline)
                        Text("Star stocks and ETFs from the lists or search to follow their prices and news here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(stars) { star in
                        NavigationLink(value: star.ref) {
                            WatchCard(star: star, quote: model.quotes[star.symbol], points: model.sparklines[star.symbol])
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            StarButton(ref: star.ref)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var newsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "News for Your Stars", systemImage: "newspaper.fill")
            if model.isLoadingNews {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if model.news.isEmpty && !stars.isEmpty && model.error == nil {
                GlassCard {
                    Text("No recent news for your starred symbols.")
                        .foregroundStyle(.secondary)
                }
            } else {
                NewsFeed(articles: model.news)
            }
        }
    }
}

private struct IndexChip: View {
    var symbol: String
    var quote: Quote?

    private static let names = ["^GSPC": "S&P 500", "^IXIC": "Nasdaq", "^DJI": "Dow Jones", "^RUT": "Russell 2000", "^VIX": "VIX"]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Self.names[symbol] ?? quote?.name ?? symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(quote.map { Fmt.number($0.price) } ?? "—")
                .font(.headline)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(Fmt.percent(quote?.changePercentage))
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.trend(quote?.changePercentage))
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minWidth: 118, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
        .redacted(reason: quote == nil ? .placeholder : [])
    }
}

private struct WatchCard: View {
    var star: StarredSymbol
    var quote: Quote?
    var points: [PricePoint]?
    @Environment(MarketData.self) private var marketData

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                LogoView(symbol: star.symbol, url: marketData.provider(for: star.market).logoURL(for: star.symbol), size: 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text(star.symbol)
                        .font(.headline)
                    Text(star.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            Group {
                if let points, points.count > 1 {
                    SparklineView(points: points, baseline: points.first?.price)
                } else {
                    Capsule().fill(.quaternary).frame(height: 2)
                }
            }
            .frame(height: 44)
            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.price(quote?.price))
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                ChangeBadge(percent: quote?.changePercentage, compact: true)
            }
            .redacted(reason: quote == nil ? .placeholder : [])
        }
        .padding(14)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 26))
        .contentShape(.rect(cornerRadius: 26))
    }
}
