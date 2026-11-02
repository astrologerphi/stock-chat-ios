import SwiftUI
import SwiftData

enum SearchScope: String, CaseIterable, Identifiable {
    case all = "All", stocks = "Stocks", etfs = "ETFs"
    var id: String { rawValue }

    func matches(_ kind: SecurityKind) -> Bool {
        switch self {
        case .all: true
        case .stocks: kind == .stock
        case .etfs: kind == .etf
        }
    }
}

@Observable
final class SearchModel {
    var results: [SecuritySummary] = []
    var isSearching = false
    var error: String?
    var lastQuery = ""

    func search(_ query: String, provider: any MarketDataProvider) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            error = nil
            lastQuery = ""
            return
        }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            let found = try await provider.search(trimmed)
            guard !Task.isCancelled else { return }
            results = found
            lastQuery = trimmed
            error = nil
        } catch is CancellationError {
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            self.error = error.localizedDescription
        }
    }
}

struct SearchView: View {
    var market: Market

    @Environment(MarketData.self) private var marketData
    @Environment(\.modelContext) private var context
    @Query private var stars: [StarredSymbol]
    @Binding var query: String
    /// The search tab's navigation path; whatever gets opened from here is remembered as a recent.
    var path: [SecurityRef] = []
    @State private var scope: SearchScope = .all
    @State private var model = SearchModel()
    @AppStorage("recentSearches") private var recentData = Data()

    private static let popular: [SecurityRef] = [
        .init(symbol: "AAPL", name: "Apple Inc.", kind: .stock),
        .init(symbol: "MSFT", name: "Microsoft Corporation", kind: .stock),
        .init(symbol: "NVDA", name: "NVIDIA Corporation", kind: .stock),
        .init(symbol: "AMZN", name: "Amazon.com, Inc.", kind: .stock),
        .init(symbol: "GOOGL", name: "Alphabet Inc.", kind: .stock),
        .init(symbol: "TSLA", name: "Tesla, Inc.", kind: .stock),
        .init(symbol: "SPY", name: "SPDR S&P 500 ETF Trust", kind: .etf),
        .init(symbol: "QQQ", name: "Invesco QQQ Trust", kind: .etf),
        .init(symbol: "VOO", name: "Vanguard S&P 500 ETF", kind: .etf),
        .init(symbol: "SOXX", name: "iShares Semiconductor ETF", kind: .etf),
    ]

    private var recents: [SecurityRef] {
        (try? JSONDecoder().decode([SecurityRef].self, from: recentData)) ?? []
    }

    private var filteredResults: [SecuritySummary] {
        model.results.filter { scope.matches($0.kind) }
    }

    var body: some View {
        List {
            scopePicker
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                suggestions
            } else {
                results
            }
        }
        .scrollContentBackground(.hidden)
        .background { AppBackground(tint: .indigo) }
        .navigationTitle("Search")
        .onChange(of: path.first) { _, opened in
            if let opened { remember(opened) }
        }
        .task(id: query) { await model.search(query, provider: marketData.provider(for: market)) }
    }

    @ViewBuilder
    private var results: some View {
        if let error = model.error {
            ErrorBanner(message: error) { Task { await model.search(query, provider: marketData.provider(for: market)) } }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        if model.isSearching && filteredResults.isEmpty {
            HStack { Spacer(); ProgressView(); Spacer() }
                .listRowBackground(Color.clear)
        } else if filteredResults.isEmpty && !model.lastQuery.isEmpty && model.error == nil {
            ContentUnavailableView.search(text: query)
                .listRowBackground(Color.clear)
        } else {
            Section {
                ForEach(filteredResults) { item in
                    row(item)
                }
            } header: {
                if !filteredResults.isEmpty {
                    Text("\(filteredResults.count) results in \(market.flag) \(market.displayName)")
                }
            }
        }
    }

    @ViewBuilder
    private var suggestions: some View {
        if !recents.isEmpty {
            Section {
                ForEach(recents) { ref in
                    row(SecuritySummary(symbol: ref.symbol, name: ref.name, kind: ref.kind, market: ref.market))
                }
            } header: {
                HStack {
                    Text("Recent")
                    Spacer()
                    Button("Clear") { withAnimation { recentData = Data() } }
                        .font(.footnote)
                }
            }
        }
        Section("Popular") {
            ForEach(Self.popular.filter { scope.matches($0.kind) }) { ref in
                row(SecuritySummary(symbol: ref.symbol, name: ref.name, kind: ref.kind, market: ref.market))
            }
        }
    }

    private var scopePicker: some View {
        Picker("Type", selection: $scope.animation(.smooth)) {
            ForEach(SearchScope.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
    }

    private func row(_ item: SecuritySummary) -> some View {
        NavigationLink(value: item.ref) {
            SecurityRow(item: item, starred: Stars.isStarred(item.ref, in: stars), showsKind: true)
        }
        .glassListRow()
        .swipeActions(edge: .trailing) {
            let starred = Stars.isStarred(item.ref, in: stars)
            Button {
                withAnimation { Stars.toggle(item.ref, in: context) }
            } label: {
                Label(starred ? "Unstar" : "Star", systemImage: starred ? "star.slash.fill" : "star.fill")
            }
            .tint(.yellow)
        }
        .contextMenu { StarButton(ref: item.ref) }
    }

    private func remember(_ ref: SecurityRef) {
        var list = recents.filter { $0.id != ref.id }
        list.insert(ref, at: 0)
        recentData = (try? JSONEncoder().encode(Array(list.prefix(10)))) ?? Data()
    }
}
