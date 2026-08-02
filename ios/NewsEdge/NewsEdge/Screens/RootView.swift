import SwiftUI

struct RootView: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            SearchScreen(path: $path)
                .navigationDestination(for: String.self) { symbol in
                    TickerScreen(ticker: symbol)
                }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark) // the web app has no light theme; match it exactly
    }
}

#Preview {
    RootView()
        .environment(WatchlistStore())
}
