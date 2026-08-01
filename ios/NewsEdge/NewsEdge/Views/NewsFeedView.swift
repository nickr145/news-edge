import SwiftUI

/// Ports NewsFeed.jsx.
struct NewsFeedView: View {
    let articles: [Article]
    let loading: Bool
    @State private var collapsed = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                collapsed.toggle()
            } label: {
                HStack {
                    Text("Live News").font(.headline)
                    Spacer()
                    Text("\(articles.count) articles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !collapsed {
                if articles.isEmpty && !loading {
                    Text("No articles yet. Subscribe to a ticker to begin.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(articles.enumerated()), id: \.element.id) { index, article in
                            ArticleRow(article: article)
                            if index < articles.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct ArticleRow: View {
    let article: Article

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            headline
            HStack(spacing: 8) {
                Text(article.source ?? "unknown")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.15), in: Capsule())
                if let label = article.sentimentLabel, !label.isEmpty {
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(Theme.sentimentColor(label))
                }
                Text("rel \(String(format: "%.2f", article.relevanceScore ?? 0))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(relativeTime(article.publishedAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var headline: some View {
        let text = Text(article.headline)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
        if let url = URL(string: article.url) {
            Link(destination: url) { text }
        } else {
            text
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }
}

#Preview {
    NewsFeedView(articles: [], loading: false)
        .card()
        .padding()
}
