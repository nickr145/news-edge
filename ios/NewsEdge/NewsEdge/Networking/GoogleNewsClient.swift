import Foundation

/// Keyless Google News RSS, used once per ticker to backfill ~30 days of history that Yahoo (last day or two)
/// can't provide. Items carry no ticker tags, so an article only counts as relevant if its headline
/// mentions the ticker or the company's first name; everything else gets no symbols and is filtered out.
struct GoogleNewsClient: Sendable {
    var session: URLSession = .shared

    /// Samples `weeks` consecutive 7-day windows (Google's `after:`/`before:` operators) and keeps the
    /// newest `perWindow` items of each, so the result spans ~a month instead of just the latest day.
    func news(ticker: String, companyName: String?, weeks: Int = 4, perWindow: Int = 6, now: Date = Date()) async throws -> [Article] {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX"); day.timeZone = TimeZone(identifier: "UTC"); day.dateFormat = "yyyy-MM-dd"
        return try await withThrowingTaskGroup(of: [Article].self) { group in
            for w in 0..<weeks {
                let before = now.addingTimeInterval(Double(1 - 7 * w) * 86_400)  // exclusive upper bound
                let after = before.addingTimeInterval(-7 * 86_400)
                group.addTask {
                    (try? await window(ticker: ticker, companyName: companyName, after: day.string(from: after),
                                       before: day.string(from: before), limit: perWindow)) ?? []
                }
            }
            var seen = Set<Int>(), all: [Article] = []
            for try await items in group { for item in items where seen.insert(item.id).inserted { all.append(item) } }
            return all
        }
    }

    /// Free-text search (leadership / supply-chain / sector / macro queries); items come back untagged.
    func search(query: String, limit: Int = 10) async throws -> [Article] {
        var c = URLComponents(string: "https://news.google.com/rss/search")!
        c.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "hl", value: "en-US"), URLQueryItem(name: "gl", value: "US"), URLQueryItem(name: "ceid", value: "US:en"),
        ]
        guard let url = c.url else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let data: Data
        do { (data, _) = try await session.data(for: request) } catch { throw APIError.transport(error) }
        return Self.articles(from: data, ticker: "", companyName: nil, limit: limit)
    }

    private func window(ticker: String, companyName: String?, after: String, before: String, limit: Int) async throws -> [Article] {
        var c = URLComponents(string: "https://news.google.com/rss/search")!
        c.queryItems = [
            URLQueryItem(name: "q", value: "\(ticker.uppercased()) stock after:\(after) before:\(before)"),
            URLQueryItem(name: "hl", value: "en-US"), URLQueryItem(name: "gl", value: "US"), URLQueryItem(name: "ceid", value: "US:en"),
        ]
        guard let url = c.url else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let data: Data
        do { (data, _) = try await session.data(for: request) } catch { throw APIError.transport(error) }
        return Self.articles(from: data, ticker: ticker, companyName: companyName, limit: limit)
    }

    static func articles(from data: Data, ticker: String, companyName: String?, limit: Int) -> [Article] {
        let parser = RSSParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        xml.parse()

        let firstName = companyName?
            .split(separator: " ").first
            .map { $0.lowercased().filter(\.isLetter) }
            .flatMap { $0.count >= 4 ? $0 : nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"

        let articles: [Article] = parser.items.compactMap { item in
            guard let title = item.title, let link = item.link, let date = item.pubDate.flatMap(formatter.date(from:))
            else { return nil }
            var headline = title
            if let source = item.source, headline.hasSuffix(" - \(source)") {
                headline = String(headline.dropLast(source.count + 3))
            }
            let lower = headline.lowercased()
            let mentions = !ticker.isEmpty && (lower.contains(ticker.lowercased()) || (firstName.map(lower.contains) ?? false))
            return Article(
                id: YahooClient.stableID(link), url: link, headline: headline,
                summary: nil, body: nil, source: item.source, publishedAt: date,
                sentimentLabel: nil, compound: nil, relevanceScore: nil,
                sourceWeight: Analytics.sourceWeight(item.source), nearEarnings: nil, isSecFiling: nil,
                symbols: mentions ? [ticker.uppercased()] : []
            )
        }
        return Array(articles.sorted { $0.publishedAt > $1.publishedAt }.prefix(limit))
    }
}

private final class RSSParser: NSObject, XMLParserDelegate {
    struct Item { var title, link, pubDate, source: String? }
    var items: [Item] = []
    private var current: Item?
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if name == "item" { current = Item() }
        text = ""
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, foundCDATA data: Data) { text += String(decoding: data, as: UTF8.self) }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard current != nil else { return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "title": current?.title = value
        case "link": current?.link = value
        case "pubDate": current?.pubDate = value
        case "source": current?.source = value
        case "item": if let item = current { items.append(item) }; current = nil
        default: break
        }
    }
}
