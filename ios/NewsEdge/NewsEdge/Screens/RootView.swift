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
    }
}

#Preview {
    RootView()
        .environment(WatchlistStore())
}
