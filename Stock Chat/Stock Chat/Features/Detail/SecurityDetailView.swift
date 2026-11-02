import SwiftUI
import SwiftData

@Observable
final class SecurityDetailModel {
    var quote: Quote?
    var profile: CompanyProfile?
    var etfInfo: ETFInfo?
    var ratios: RatiosTTM?
    var priceChange: PriceChange?
    var points: [PricePoint] = []
    var news: [NewsArticle] = []
    var isLoadingChart = false
    var chartError: String?
    var error: String?
    var resolvedKind: SecurityKind

    init(kind: SecurityKind) {
        resolvedKind = kind
    }

    func load(_ ref: SecurityRef, provider: any MarketDataProvider) async {
        async let quote = provider.quote(ref.symbol)
        async let change = try? provider.priceChange(ref.symbol)
        async let news = try? provider.news(for: [ref.symbol], limit: 15)

        if ref.kind != .index {
            profile = try? await provider.profile(ref.symbol)
            if profile?.isEtf == true || profile?.isFund == true { resolvedKind = .etf }
            if resolvedKind == .etf {
                etfInfo = try? await provider.etfInfo(ref.symbol)
            } else {
                ratios = try? await provider.ratios(ref.symbol)
            }
        }
        do {
            self.quote = try await quote
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        priceChange = await change
        self.news = await news ?? []
    }

    func loadChart(_ ref: SecurityRef, range: ChartRange, provider: any MarketDataProvider) async {
        isLoadingChart = true
        defer { isLoadingChart = false }
        do {
            points = try await provider.history(ref.symbol, range: range)
            chartError = points.isEmpty ? "No chart data for this range." : nil
        } catch is CancellationError {
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            points = []
            chartError = error.localizedDescription
        }
    }
}

struct SecurityDetailView: View {
    var ref: SecurityRef

    @Environment(MarketData.self) private var marketData
    @State private var model: SecurityDetailModel
    @State private var range: ChartRange = .day
    @State private var selection: PricePoint?
    @State private var expandedAbout = false

    init(ref: SecurityRef) {
        self.ref = ref
        _model = State(initialValue: SecurityDetailModel(kind: ref.kind))
    }

    private var provider: any MarketDataProvider { marketData.provider(for: ref.market) }
    private var currency: String { model.profile?.currency ?? ref.market.currencyCode }
    private var displayName: String { model.profile?.companyName ?? model.etfInfo?.name ?? model.quote?.name ?? ref.name }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if let error = model.error {
                    ErrorBanner(message: error) { Task { await model.load(ref, provider: provider) } }
                }
                chartSection
                if let change = model.priceChange { performance(change) }
                statsSection
                if model.resolvedKind == .etf, let info = model.etfInfo { etfSection(info) }
                aboutSection
                if !model.news.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Latest News", systemImage: "newspaper.fill")
                        NewsFeed(articles: model.news, heroFirst: false)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .background { AppBackground(tint: Color.trend(model.quote?.changePercentage)) }
        .navigationTitle(ref.symbol)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if ref.kind != .index {
                ToolbarItem(placement: .topBarTrailing) {
                    StarButton(ref: SecurityRef(symbol: ref.symbol, name: displayName, kind: model.resolvedKind, market: ref.market))
                }
            }
            if let website = model.profile?.website.flatMap(URL.init(string:)) ?? model.etfInfo?.website.flatMap(URL.init(string:)) {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: website, subject: Text(displayName))
                }
            }
        }
        .task { await model.load(ref, provider: provider) }
        .task(id: range) { await model.loadChart(ref, range: range, provider: provider) }
        .refreshable {
            await model.load(ref, provider: provider)
            await model.loadChart(ref, range: range, provider: provider)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                LogoView(symbol: ref.symbol, url: provider.logoURL(for: ref.symbol), size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName)
                        .font(.title2.weight(.bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    HStack(spacing: 6) {
                        Tag(text: model.resolvedKind.title)
                        if let exchange = model.profile?.exchange ?? model.quote?.exchange {
                            Tag(text: exchange)
                        }
                        Tag(text: "\(ref.market.flag) \(ref.market.rawValue)")
                    }
                }
            }
            let shownPrice = selection?.price ?? model.quote?.price
            Text(Fmt.price(shownPrice, currency: currency))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: shownPrice ?? 0))
                .animation(.snappy, value: shownPrice)
                .redacted(reason: model.quote == nil ? .placeholder : [])
            HStack(spacing: 8) {
                if let selection {
                    let base = range == .day ? (model.quote?.previousClose ?? model.points.first?.price) : model.points.first?.price
                    let diff = base.map { selection.price - $0 }
                    let pct = base.flatMap { $0 == 0 ? nil : (selection.price - $0) / $0 * 100 }
                    Text("\(Fmt.signed(diff)) (\(Fmt.percent(pct)))")
                        .foregroundStyle(Color.trend(diff))
                    Text(selection.date, format: range.isIntraday ? .dateTime.month().day().hour().minute() : .dateTime.year().month().day())
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(Fmt.signed(model.quote?.change)) (\(Fmt.percent(model.quote?.changePercentage)))")
                        .foregroundStyle(Color.trend(model.quote?.change))
                    if let date = model.quote?.date {
                        Text(date, format: .relative(presentation: .named))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
        }
        .padding(.top, 4)
    }

    // MARK: Chart

    private var chartSection: some View {
        VStack(spacing: 14) {
            ZStack {
                if model.points.count > 1 {
                    PriceChartView(
                        points: model.points,
                        range: range,
                        baseline: range == .day ? model.quote?.previousClose : nil,
                        selection: $selection
                    )
                    .opacity(model.isLoadingChart ? 0.4 : 1)
                } else if let error = model.chartError, !model.isLoadingChart {
                    ContentUnavailableView("Chart Unavailable", systemImage: "chart.xyaxis.line", description: Text(error))
                }
                if model.isLoadingChart { ProgressView() }
            }
            .frame(height: 240)
            .animation(.smooth, value: model.points)
            RangePicker(selection: $range)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
    }

    private func performance(_ change: PriceChange) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Performance", systemImage: "speedometer")
            ScrollView(.horizontal, showsIndicators: false) {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(change.entries, id: \.label) { entry in
                            VStack(spacing: 4) {
                                Text(entry.label)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(Fmt.percent(entry.value))
                                    .font(.footnote.weight(.bold))
                                    .foregroundStyle(Color.trend(entry.value))
                                    .monospacedDigit()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .glassEffect(.regular.tint(Color.trend(entry.value).opacity(0.12)), in: .rect(cornerRadius: 16))
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .scrollClipDisabled()
        }
    }

    // MARK: Stats

    private var statsSection: some View {
        let q = model.quote
        var stats: [(String, String)] = [
            ("Open", Fmt.price(q?.open, currency: currency)),
            ("Prev Close", Fmt.price(q?.previousClose, currency: currency)),
            ("Day Range", rangeText(q?.dayLow, q?.dayHigh)),
            ("52W Range", rangeText(q?.yearLow, q?.yearHigh)),
            ("Volume", Fmt.compact(q?.volume)),
            ("Avg Volume", Fmt.compact(model.profile?.averageVolume ?? model.etfInfo?.avgVolume)),
        ]
        if model.resolvedKind == .stock {
            stats += [
                ("Market Cap", Fmt.compactCurrency(q?.marketCap, currency: currency)),
                ("P/E (TTM)", Fmt.number(model.ratios?.priceToEarningsRatioTTM)),
                ("Div Yield", model.ratios?.dividendYieldTTM.map { Fmt.percent($0 * 100, signed: false) } ?? "—"),
                ("Beta", Fmt.number(model.profile?.beta)),
            ]
        } else if model.resolvedKind == .etf {
            stats += [
                ("50D Avg", Fmt.price(q?.priceAvg50, currency: currency)),
                ("200D Avg", Fmt.price(q?.priceAvg200, currency: currency)),
            ]
        }
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Key Stats", systemImage: "chart.bar.doc.horizontal")
            GlassCard {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                    ForEach(0..<(stats.count + 1) / 2, id: \.self) { row in
                        GridRow {
                            StatCell(label: stats[row * 2].0, value: stats[row * 2].1)
                            if row * 2 + 1 < stats.count {
                                StatCell(label: stats[row * 2 + 1].0, value: stats[row * 2 + 1].1)
                            }
                        }
                    }
                }
            }
        }
    }

    private func rangeText(_ low: Double?, _ high: Double?) -> String {
        guard let low, let high else { return "—" }
        return "\(Fmt.number(low)) – \(Fmt.number(high))"
    }

    private func etfSection(_ info: ETFInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Fund Details", systemImage: "square.stack.3d.up.fill")
            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                        GridRow {
                            StatCell(label: "Issuer", value: info.etfCompany ?? "—")
                            StatCell(label: "Expense Ratio", value: info.expenseRatio.map { Fmt.percent($0, signed: false) } ?? "—")
                        }
                        GridRow {
                            StatCell(label: "Assets (AUM)", value: Fmt.compactCurrency(info.assetsUnderManagement, currency: currency))
                            StatCell(label: "NAV", value: Fmt.price(info.nav, currency: info.navCurrency ?? currency))
                        }
                        GridRow {
                            StatCell(label: "Holdings", value: info.holdingsCount.map(String.init) ?? "—")
                            StatCell(label: "Inception", value: info.inceptionDate ?? "—")
                        }
                        GridRow {
                            StatCell(label: "Asset Class", value: info.assetClass ?? "—")
                            StatCell(label: "Domicile", value: info.domicile ?? "—")
                        }
                    }
                    if let sectors = info.sectorsList?.sorted(by: { $0.exposure > $1.exposure }).prefix(6), !sectors.isEmpty {
                        Divider()
                        Text("Sector Exposure")
                            .font(.subheadline.weight(.semibold))
                        ForEach(Array(sectors), id: \.industry) { sector in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(sector.industry).font(.caption)
                                    Spacer()
                                    Text(Fmt.percent(sector.exposure, signed: false)).font(.caption.weight(.semibold)).monospacedDigit()
                                }
                                ProgressView(value: min(max(sector.exposure, 0), 100), total: 100)
                                    .tint(.accentColor)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: About

    @ViewBuilder
    private var aboutSection: some View {
        let description = model.profile?.description ?? model.etfInfo?.description
        let p = model.profile
        let facts: [(String, String?)] = model.resolvedKind == .stock ? [
            ("Sector", p?.sector),
            ("Industry", p?.industry),
            ("CEO", p?.ceo),
            ("Employees", p?.fullTimeEmployees.flatMap(Double.init).map { $0.formatted(.number) }),
            ("Headquarters", [p?.city, p?.state].compactMap { $0 }.joined(separator: ", ").nilIfEmpty),
            ("IPO Date", p?.ipoDate),
        ] : []
        let website = p?.website ?? model.etfInfo?.website
        if description != nil || facts.contains(where: { $0.1 != nil }) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "About", systemImage: "info.circle.fill")
                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        if let description {
                            Text(description)
                                .font(.subheadline)
                                .lineLimit(expandedAbout ? nil : 4)
                            Button(expandedAbout ? "Show Less" : "Show More") {
                                withAnimation(.smooth) { expandedAbout.toggle() }
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                        ForEach(facts.filter { $0.1 != nil }, id: \.0) { fact in
                            HStack {
                                Text(fact.0).foregroundStyle(.secondary)
                                Spacer()
                                Text(fact.1 ?? "").multilineTextAlignment(.trailing)
                            }
                            .font(.subheadline)
                        }
                        if let website, let url = URL(string: website) {
                            Link(destination: url) {
                                Label(url.host() ?? website, systemImage: "safari")
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct StatCell: View {
    var label: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Tag: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .glassEffect(.regular, in: .capsule)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
