import SwiftUI
import SwiftData

@Observable
final class SecurityListModel {
    var items: [SecuritySummary] = []
    var isLoading = false
    var error: String?
    private(set) var limit = 0
    private(set) var reachedEnd = false
    @ObservationIgnored private var loadToken = UUID()

    static let pageSize = 50
    static let maxItems = 500

    func load(kind: SecurityKind, sector: String?, provider: any MarketDataProvider, reset: Bool) async {
        if reset {
            limit = 0
            reachedEnd = false
        } else if isLoading || reachedEnd {
            return
        }
        let token = UUID()
        loadToken = token
        isLoading = true
        defer { if loadToken == token { isLoading = false } }
        let nextLimit = min(limit + Self.pageSize, Self.maxItems)
        do {
            let result = switch kind {
            case .etf: try await provider.etfs(limit: nextLimit)
            default: try await provider.stocks(sector: sector, limit: nextLimit)
            }
            guard loadToken == token else { return }
            error = nil
            items = result
            reachedEnd = result.count < nextLimit || nextLimit >= Self.maxItems
            limit = nextLimit
        } catch is CancellationError {
        } catch {
            if (error as? URLError)?.code == .cancelled || loadToken != token { return }
            self.error = error.localizedDescription
        }
    }
}

struct SecurityListView: View {
    var kind: SecurityKind
    var market: Market

    @Environment(MarketData.self) private var marketData
    @Environment(\.modelContext) private var context
    @Query private var stars: [StarredSymbol]
    @State private var model = SecurityListModel()
    @State private var sector: String?
    @Namespace private var chipNamespace

    static let sectors = [
        "Technology", "Healthcare", "Financial Services", "Consumer Cyclical", "Communication Services",
        "Industrials", "Consumer Defensive", "Energy", "Utilities", "Real Estate", "Basic Materials",
    ]

    var body: some View {
        List {
            if kind == .stock {
                sectorChips
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            if let error = model.error {
                ErrorBanner(message: error) { Task { await load(reset: true) } }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            Section {
                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                    NavigationLink(value: item.ref) {
                        HStack(spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                                .frame(width: 26, alignment: .trailing)
                            SecurityRow(item: item, starred: Stars.isStarred(item.ref, in: stars))
                        }
                    }
                    .glassListRow()
                    .swipeActions(edge: .trailing) { starAction(item.ref) }
                    .contextMenu { StarButton(ref: item.ref) }
                    .onAppear {
                        if item.id == model.items.last?.id {
                            Task { await load(reset: false) }
                        }
                    }
                }
                if model.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            } header: {
                if !model.items.isEmpty {
                    Text(kind == .etf ? "Largest US ETFs by assets" : "Largest \(sector ?? "US") companies by market cap")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background { AppBackground(tint: kind == .etf ? .purple : .teal) }
        .navigationTitle(kind == .etf ? "ETFs" : "Stocks")
        .navigationSubtitle("\(market.flag) \(market.displayName)")
        .task(id: "\(market.rawValue)|\(sector ?? "")") { await load(reset: true) }
        .refreshable { await load(reset: true) }
        .animation(.smooth, value: model.items.count)
    }

    private func load(reset: Bool) async {
        await model.load(kind: kind, sector: sector, provider: marketData.provider(for: market), reset: reset)
    }

    @ViewBuilder
    private func starAction(_ ref: SecurityRef) -> some View {
        let starred = Stars.isStarred(ref, in: stars)
        Button {
            withAnimation { Stars.toggle(ref, in: context) }
        } label: {
            Label(starred ? "Unstar" : "Star", systemImage: starred ? "star.slash.fill" : "star.fill")
        }
        .tint(.yellow)
    }

    private var sectorChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    chip(title: "All", value: nil)
                    ForEach(Self.sectors, id: \.self) { chip(title: $0, value: $0) }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
        }
    }

    private func chip(title: String, value: String?) -> some View {
        let selected = sector == value
        return Button {
            withAnimation(.bouncy) { sector = value }
        } label: {
            Text(title)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .glassEffect(selected ? .regular.tint(.accentColor).interactive() : .regular.interactive(), in: .capsule)
        .glassEffectID(title, in: chipNamespace)
    }
}
