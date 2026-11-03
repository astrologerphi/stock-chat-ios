//
//  Stock_ChatApp.swift
//  Stock Chat
//
//  Created by Fei HH on 2026/10/30.
//

import SwiftUI
import SwiftData

@main
struct Stock_ChatApp: App {
    @State private var marketData = MarketData.live

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            StarredSymbol.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(marketData)
                .onAppear {
                    Stars.seedForLocalTestingIfNeeded(in: sharedModelContainer.mainContext)
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
