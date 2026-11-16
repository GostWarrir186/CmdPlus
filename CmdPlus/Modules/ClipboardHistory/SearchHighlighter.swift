import SwiftUI

/// Подсвечивает найденные слова в тексте.
enum SearchHighlighter {
    /// Сжимает переводы строк в пробелы и обрезает текст до `limit` символов.
    /// Если первое совпадение далеко от начала, показывает фрагмент вокруг него.
    static func preview(of text: String, terms: [String], limit: Int = 300) -> String {
        let flat = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let firstMatch = terms
            .compactMap { flat.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) }
            .map(\.lowerBound)
            .min()

        var start = flat.startIndex
        var prefix = ""
        if let firstMatch, flat.distance(from: flat.startIndex, to: firstMatch) > 80 {
            start = flat.index(firstMatch, offsetBy: -30)
            prefix = "…"
        }
        let end = flat.index(start, offsetBy: limit, limitedBy: flat.endIndex) ?? flat.endIndex
        let suffix = end < flat.endIndex ? "…" : ""
        return prefix + flat[start..<end] + suffix
    }

    /// Строка, в которой совпадения выделены жирным и цветной подложкой.
    static func highlight(_ text: String, terms: [String]) -> AttributedString {
        var ranges: [Range<String.Index>] = []
        for term in terms where !term.isEmpty {
            var searchRange = text.startIndex..<text.endIndex
            while let found = text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange) {
                ranges.append(found)
                searchRange = found.upperBound..<text.endIndex
            }
        }
        guard !ranges.isEmpty else { return AttributedString(text) }
        ranges.sort { $0.lowerBound < $1.lowerBound }

        var result = AttributedString()
        var cursor = text.startIndex
        for range in ranges {
            // Совпадения могут пересекаться — выделяем только ещё не выделенную часть.
            let start = max(range.lowerBound, cursor)
            guard start < range.upperBound else { continue }
            result += AttributedString(text[cursor..<start])
            var match = AttributedString(text[start..<range.upperBound])
            match.inlinePresentationIntent = .stronglyEmphasized
            match.backgroundColor = Color.yellow.opacity(0.45)
            result += match
            cursor = range.upperBound
        }
        result += AttributedString(text[cursor...])
        return result
    }
}
