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

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(watchlistStore)
        }
    }
}
