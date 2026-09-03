import Foundation

struct FilenameDateParser {
    private let patterns: [(NSRegularExpression, String)] = [
        (try! NSRegularExpression(pattern: #"(?<!\d)(\d{4})(\d{2})(\d{2})[_-]?(\d{2})(\d{2})(\d{2})(?!\d)"#), "yyyyMMddHHmmss"),
        (try! NSRegularExpression(pattern: #"(?<!\d)(\d{4})[-_](\d{2})[-_](\d{2})[\s_-](\d{2})[-_](\d{2})[-_](\d{2})(?!\d)"#), "yyyyMMddHHmmss"),
        (try! NSRegularExpression(pattern: #"(?<!\d)(\d{4})(\d{2})(\d{2})(?!\d)"#), "yyyyMMdd")
    ]

    func parse(_ filename: String) -> Date? {
        let range = NSRange(filename.startIndex..<filename.endIndex, in: filename)
        for (regex, format) in patterns {
            guard let match = regex.firstMatch(in: filename, range: range) else { continue }
            var parts: [String] = []
            for index in 1..<match.numberOfRanges {
                guard let substringRange = Range(match.range(at: index), in: filename) else { continue }
                parts.append(String(filename[substringRange]))
            }
            let normalized = parts.joined()
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone.current
            formatter.dateFormat = format
            if let date = formatter.date(from: normalized) {
                return date
            }
        }
        return nil
    }
}
