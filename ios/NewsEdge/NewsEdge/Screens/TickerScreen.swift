import SwiftUI

/// Ports TickerPage.jsx: loads news/sentiment/risk/price data for a ticker,
/// polls every 30s, streams live articles over WebSocket, and lets the user
/// trigger a prediction.
struct TickerScreen: View {
    let ticker: String
    @Environment(WatchlistStore.self) private var watchlistStore

    @State private var articles: [Article] = []
    @State private var summary: SentimentSummary?
    @State private var trend: SentimentTrend?
    @State private var bars: [PriceBar] = []
    @State private var risk: RiskMetrics?
    @State private var prediction: Prediction?

    @State private var windowDays = 30
    @State private var minRelevance = 0.35
    @State private var horizonDays = 5

    @State private var isLoading = false
    @State private var isPredicting = false
    @State private var errorMessage: String?

    private let windowOptions = [1, 7, 30, 90]
    private let relevanceOptions = [0.2, 0.35, 0.5, 0.7]

    private var loadKey: String { "\(ticker)|\(windowDays)|\(minRelevance)" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Theme.danger)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }

                controlsRow

                PredictionCardView(
                    prediction: prediction,
                    predicting: isPredicting,
                    horizonDays: $horizonDays,
                    onPredict: triggerPrediction
                )
                .card()

                RiskPanelView(risk: risk, isLoading: isLoading)
                    .card()

                PriceChartView(bars: bars, trend: trend, isLoading: isLoading)
                    .card()

                SentimentPanelView(summary: summary, trend: trend, isLoading: isLoading)
                    .card()

                NewsFeedView(articles: articles, loading: isLoading)
                    .card()
            }
            .padding()
        }
        .refreshable {
            await refresh()
        }
        .navigationTitle(ticker)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    watchlistStore.toggle(ticker)
                } label: {
                    Image(systemName: watchlistStore.isWatched(ticker) ? "star.fill" : "star")
                }
                .accessibilityLabel(watchlistStore.isWatched(ticker) ? "Remove from watchlist" : "Add to watchlist")
            }
        }
        .task(id: loadKey) {
            await subscribeAndPoll()
        }
        .task(id: loadKey) {
            await listenForLiveNews()
        }
    }

    private var controlsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Window", selection: $windowDays) {
                ForEach(windowOptions, id: \.self) { days in
                    Text("\(days)d").tag(days)
                }
            }
            .pickerStyle(.segmented)

            Picker("Min relevance", selection: $minRelevance) {
                ForEach(relevanceOptions, id: \.self) { value in
                    Text(String(format: "%.2f", value)).tag(value)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Data loading

    private func subscribeAndPoll() async {
        isLoading = true
        _ = try? await APIClient.shared.subscribe(ticker: ticker, backfillDays: windowDays)
        await refresh()
        isLoading = false

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            if Task.isCancelled { break }
            await refresh()
        }
    }

    private func refresh() async {
        let barLimit = max(windowDays, 30)
        let trendHours = min(windowDays * 24, 24 * 30)
        do {
            async let articlesResult = APIClient.shared.articles(ticker: ticker, days: windowDays, limit: 100, minRelevance: minRelevance)
            async let summaryResult = APIClient.shared.sentimentSummary(ticker: ticker, days: windowDays, minRelevance: minRelevance)
            async let trendResult = APIClient.shared.sentimentTrend(ticker: ticker, hours: trendHours, minRelevance: minRelevance)
            async let riskResult = APIClient.shared.riskMetrics(ticker: ticker, benchmark: "SPY", days: 365)
            async let barsResult = APIClient.shared.priceBars(ticker: ticker, limit: barLimit)

            let (newArticles, newSummary, newTrend, newRisk, newBars) = try await (
                articlesResult, summaryResult, trendResult, riskResult, barsResult
            )
            articles = dedupe(newArticles)
            summary = newSummary
            trend = newTrend
            risk = newRisk
            bars = newBars
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load data. Retrying…"
        }
    }

    /// Reconnects with a fixed backoff on drop/error; SwiftUI cancels this
    /// task automatically when `loadKey` changes or the view disappears.
    private func listenForLiveNews() async {
        while !Task.isCancelled {
            let socket = NewsSocket()
            do {
                for try await article in socket.stream(ticker: ticker) {
                    articles = Array(dedupe([article] + articles).prefix(100))
                    let trendHours = min(windowDays * 24, 24 * 30)
                    async let newSummary = APIClient.shared.sentimentSummary(ticker: ticker, days: windowDays, minRelevance: minRelevance)
                    async let newTrend = APIClient.shared.sentimentTrend(ticker: ticker, hours: trendHours, minRelevance: minRelevance)
                    if let value = try? await newSummary { summary = value }
                    if let value = try? await newTrend { trend = value }
                }
            } catch {
                // Fall through to reconnect below.
            }
            socket.disconnect()
            if Task.isCancelled { break }
            try? await Task.sleep(for: .seconds(3))
        }
    }

    private func dedupe(_ items: [Article]) -> [Article] {
        var seen = Set<String>()
        var result: [Article] = []
        for item in items {
            let key = "\(item.url)|\(item.headline)|\(item.publishedAt.timeIntervalSince1970)"
            if seen.insert(key).inserted {
                result.append(item)
            }
        }
        return result
    }

    private func triggerPrediction() {
        guard !isPredicting else { return }
        isPredicting = true
        Task {
            defer { isPredicting = false }
            do {
                prediction = try await APIClient.shared.predictSync(ticker: ticker, horizonDays: horizonDays)
                errorMessage = nil
            } catch {
                errorMessage = "Prediction failed. Please try again."
            }
        }
    }
}

#Preview {
    NavigationStack {
        TickerScreen(ticker: "AAPL")
    }
    .environment(WatchlistStore())
}
