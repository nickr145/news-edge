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
                    Text("Live News").font(.headline).foregroundStyle(Theme.text)
                    Spacer()
                    Text("\(articles.count) articles")
                        .font(.mono(11))
                        .foregroundStyle(Theme.muted)
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !collapsed {
                if articles.isEmpty && !loading {
                    Text("No articles yet. Subscribe to a ticker to begin.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
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
                    .font(.mono(9.5))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.surface2, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
                if let label = article.sentimentLabel, !label.isEmpty {
                    Text(label.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(Theme.sentimentColor(label))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(sentimentBadgeBackground(label), in: RoundedRectangle(cornerRadius: 4))
                }
                Text("rel \(String(format: "%.2f", article.relevanceScore ?? 0))")
                    .font(.mono(9.5))
                    .foregroundStyle(Theme.muted)
                Text(relativeTime(article.publishedAt))
                    .font(.mono(9.5))
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 6)
    }

    private func sentimentBadgeBackground(_ label: String) -> Color {
        switch label.lowercased() {
        case "positive": return Theme.accentDim
        case "negative": return Theme.dangerDim
        default: return Color.white.opacity(0.05)
        }
    }

    @ViewBuilder
    private var headline: some View {
        let text = Text(article.headline)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.text)
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
        .background(Theme.background)
}
