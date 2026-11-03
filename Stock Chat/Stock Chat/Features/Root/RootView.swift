import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case home, etfs, stocks, search
}

struct RootView: View {
    @State private var selection: AppTab = .home
    @State private var homePath = NavigationPath()
    @State private var searchText = ""
    @State private var searchPath: [SecurityRef] = []
    @State private var router = AppRouter()
    @AppStorage("selectedMarket") private var market: Market = .us
    @Environment(MarketData.self) private var marketData

    var body: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                NavigationStack(path: $homePath) {
                    HomeView(market: $market)
                        .withSecurityDestinations()
                }
            }
            Tab("ETFs", systemImage: "square.stack.3d.up.fill", value: AppTab.etfs) {
                NavigationStack {
                    SecurityListView(kind: .etf, market: market)
                        .withSecurityDestinations()
                }
            }
            Tab("Stocks", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.stocks) {
                NavigationStack {
                    SecurityListView(kind: .stock, market: market)
                        .withSecurityDestinations()
                }
            }
            Tab(value: AppTab.search, role: .search) {
                NavigationStack(path: $searchPath) {
                    SearchView(market: market, query: $searchText, path: searchPath)
                        .withSecurityDestinations()
                        .searchable(
                            text: $searchText,
                            placement: .navigationBarDrawer(displayMode: .always),
                            prompt: "Symbol or company name"
                        )
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            MarketStatusAccessory(market: market)
        }
        // Rebuild the tab content (and reload its data) after API keys change.
        .id(marketData.revision)
        .sheet(isPresented: $router.isSettingsPresented) {
            SettingsView()
        }
        .environment(router)
        #if DEBUG
        .onAppear(perform: applyDebugLaunchArguments)
        #endif
    }

    #if DEBUG
    /// Supports `-debugTab etfs|stocks|search`, `-debugSearch <text>` and `-debugOpen AAPL[:etf]` and `-debugSettings YES` launch arguments for simulator checks.
    private func applyDebugLaunchArguments() {
        let defaults = UserDefaults.standard
        switch defaults.string(forKey: "debugTab") {
        case "etfs": selection = .etfs
        case "stocks": selection = .stocks
        case "search": selection = .search
        default: break
        }
        if let query = defaults.string(forKey: "debugSearch") {
            selection = .search
            searchText = query
        }
        if let open = defaults.string(forKey: "debugOpen") {
            let parts = open.split(separator: ":")
            let kind: SecurityKind = parts.count > 1 && parts[1] == "etf" ? .etf : .stock
            homePath.append(SecurityRef(symbol: String(parts[0]), name: String(parts[0]), kind: kind, market: market))
        }
        if defaults.bool(forKey: "debugSettings") { router.isSettingsPresented = true }
    }
    #endif
}

extension View {
    func withSecurityDestinations() -> some View {
        navigationDestination(for: SecurityRef.self) { ref in
            SecurityDetailView(ref: ref)
        }
    }
}

struct MarketStatusAccessory: View {
    var market: Market

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let session = market.session(at: context.date)
            HStack(spacing: 10) {
                Text(market.flag)
                Circle()
                    .fill(session.isLive ? Color.gain : .orange)
                    .frame(width: 8, height: 8)
                    .shadow(color: session.isLive ? .gain : .orange, radius: 4)
                    .symbolEffect(.pulse, isActive: session.isLive)
                Text(session.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(context.date, format: .dateTime.hour().minute().timeZone(.exemplarLocation))
                    .environment(\.timeZone, market.timeZone)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 16)
        }
    }
}
