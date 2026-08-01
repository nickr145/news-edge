import Foundation

/// Shared JSON coding used by both the REST client and the news WebSocket.
///
/// The backend is inconsistent about datetime serialization depending on how
/// the value was produced: SQLAlchemy/Pydantic datetimes come back naive
/// ("2026-07-31T00:00:00", `predicted_at` even has naive **with** microseconds:
/// "2026-07-31T23:14:34.485516"), while pandas Timestamps (price bars) come
/// back UTC-aware ("2026-05-04T04:00:00+00:00"). None of these include a 'Z'
/// suffix. Naive strings are treated as UTC — verified against a live local
/// backend run, since every other timestamp in the system is UTC-based.
enum JSONCoding {
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        let formatters = makeDateFormatters()

        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            for formatter in formatters {
                if let date = formatter.date(from: raw) {
                    return date
                }
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected ISO8601 date, got \(raw)"
            )
        }
        return decoder
    }

    private static func makeDateFormatters() -> [any DateParsing] {
        let awareWithFractional = ISO8601DateFormatter()
        awareWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let awareWithoutFractional = ISO8601DateFormatter()
        awareWithoutFractional.formatOptions = [.withInternetDateTime]

        let naiveWithFractional = utcFormatter(format: "yyyy-MM-dd'T'HH:mm:ss.SSSSSS")
        let naiveWithoutFractional = utcFormatter(format: "yyyy-MM-dd'T'HH:mm:ss")

        return [awareWithFractional, awareWithoutFractional, naiveWithFractional, naiveWithoutFractional]
    }

    private static func utcFormatter(format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = format
        return formatter
    }
}

private protocol DateParsing {
    func date(from string: String) -> Date?
}

extension ISO8601DateFormatter: DateParsing {}
extension DateFormatter: DateParsing {}
