//
//  NewsEdgeApp.swift
//  NewsEdge
//
//  Created by Nicholas Rebello on 2026-07-30.
//

import SwiftUI

@main
struct NewsEdgeApp: App {
    @State private var watchlistStore = WatchlistStore()

    init() {
        // Load the 105 MB Core ML model off the main thread so the first news fetch doesn't pay for it.
        Task.detached(priority: .utility) { _ = FinBERTScorer.shared }
        // No bundled model (release builds): fetch it once, Wi-Fi only; NLTagger covers the gap.
        Task { @MainActor in FinBERTModelStore.shared.startIfNeeded() }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(watchlistStore)
                .environment(FinBERTModelStore.shared)
        }
    }
}
