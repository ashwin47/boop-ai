import Foundation
import CoreGraphics

/// Pure matching logic, shared by the Vision fallback and screenshot regression checks.
nonisolated enum ScreenTextMatcher {
    struct Line {
        let text: String
        /// Normalized image coordinates, with a bottom-left origin (Vision).
        let bounds: CGRect
    }

    struct Span {
        let line: Int
        let range: NSRange
    }

    struct Match {
        let bounds: CGRect
        let spans: [Span]
        let score: Double
    }

    private struct Normalized {
        var characters: [Character] = []
        var ranges: [NSRange] = []

        init(_ string: String) {
            for index in string.indices {
                let end = string.index(after: index)
                let folded = string[index..<end].folding(
                    options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")
                )
                for character in folded where character.isLetter || character.isNumber {
                    characters.append(character)
                    ranges.append(NSRange(index..<end, in: string))
                }
            }
        }
    }

    /// Only accept a strong, unique match. Repeated or tiny strings cannot reliably
    /// tell us which occurrence the user selected, so leave them to the fallback.
    static func locate(_ selection: String, in lines: [Line]) -> Match? {
        let target = Normalized(selection).characters
        guard target.count >= 4, target.count <= 2000, lines.count <= 600 else { return nil }
        let normalized = lines.map { Normalized($0.text) }
        var matches: [Match] = []
        let order = lines.indices.filter {
            let box = lines[$0].bounds
            return box.origin.x.isFinite && box.origin.y.isFinite
                && box.width.isFinite && box.height.isFinite && box.width > 0 && box.height > 0
        }.sorted { lines[$0].bounds.midY > lines[$1].bounds.midY }
        // Vision can split a line around links or an overlapping formatting
        // toolbar. Reassemble fragments on the same baseline before following
        // wrapped lines and paragraphs.
        var rows: [[Int]] = []
        for index in order {
            if let row = rows.indices.first(where: { row in
                let reference = lines[rows[row][0]].bounds
                let box = lines[index].bounds
                let gap = max(reference.minX, box.minX) - min(reference.maxX, box.maxX)
                return abs(reference.midY - box.midY) < min(reference.height, box.height) * 0.35
                    && gap < max(reference.height, box.height) * 12
            }) {
                rows[row].append(index)
            } else {
                rows.append([index])
            }
        }
        rows = rows.map { $0.sorted { lines[$0].bounds.minX < lines[$1].bounds.minX } }
        let rowBounds = rows.map { row in row.reduce(CGRect.null) { $0.union(lines[$1].bounds) } }
        let rowLengths = rows.map { row in row.reduce(0) { $0 + normalized[$1].characters.count } }
        for start in rows.indices {
            var run: [Int] = []
            var characters: [Character] = []
            var origins: [(Int, NSRange)] = []
            var next: Int? = start
            for _ in 0..<12 {
                guard let index = next else { break }
                run.append(index)
                for line in rows[index] {
                    characters += normalized[line].characters
                    origins += normalized[line].ranges.map { (line, $0) }
                }
                guard !characters.isEmpty else { break }

                // Exact substring matching also handles a selection inside a line.
                var exact = false
                if characters.count >= target.count {
                    for offset in 0...(characters.count - target.count) {
                        if characters[offset..<(offset + target.count)].elementsEqual(target) {
                            matches.append(makeMatch(origins: Array(origins[offset..<(offset + target.count)]),
                                                     lines: lines, score: 1))
                            exact = true
                        }
                    }
                }
                // OCR can miss letters hidden by a formatting toolbar. Keep a
                // strict error budget rather than accepting arbitrary partial text.
                let tolerance = max(1, target.count / 10)
                if !exact && target.count >= 12 && abs(characters.count - target.count) <= tolerance {
                    let distance = editDistance(characters, target)
                    let score = 1 - Double(distance) / Double(max(characters.count, target.count))
                    if score >= 0.90 {
                        matches.append(makeMatch(origins: origins, lines: lines, score: score))
                    }
                }
                if characters.count > target.count + tolerance { break }
                let previous = rowBounds[index]
                next = rows.indices.filter { candidate in
                    let box = rowBounds[candidate]
                    let overlap = min(previous.maxX, box.maxX) - max(previous.minX, box.minX)
                    // Isolated single-letter formatting controls (B / I) must
                    // not divert a paragraph match away from the selected text.
                    return !run.contains(candidate) && rowLengths[candidate] >= 3
                        && box.midY < previous.minY
                        && previous.minY - box.maxY < max(previous.height, box.height) * 3
                        && overlap > min(previous.width, box.width) * 0.5
                }.max { rowBounds[$0].midY < rowBounds[$1].midY }
            }
        }

        var unique: [Match] = []
        for match in matches.sorted(by: { $0.score > $1.score }) {
            // Overlapping runs can find the same selection; they aren't competing locations.
            if !unique.contains(where: { sameLocation($0, match) }) {
                unique.append(match)
            }
        }
        guard let best = unique.first else { return nil }
        if unique.count > 1 && best.score - unique[1].score < 0.06 { return nil }
        return best
    }

    private static func makeMatch(origins: [(Int, NSRange)], lines: [Line], score: Double) -> Match {
        var spans: [Span] = []
        for (line, range) in origins {
            if let previous = spans.last, previous.line == line {
                spans[spans.count - 1] = Span(line: line, range: NSUnionRange(previous.range, range))
            } else {
                spans.append(Span(line: line, range: range))
            }
        }
        let bounds = spans.reduce(CGRect.null) { $0.union(lines[$1.line].bounds) }
        return Match(bounds: bounds, spans: spans, score: score)
    }

    private static func sameLocation(_ a: Match, _ b: Match) -> Bool {
        let intersection = a.spans.reduce(0) { total, span in
            total + b.spans.filter { $0.line == span.line }.reduce(0) {
                $0 + NSIntersectionRange(span.range, $1.range).length
            }
        }
        let length = max(a.spans.reduce(0) { $0 + $1.range.length },
                         b.spans.reduce(0) { $0 + $1.range.length })
        return Double(intersection) / Double(max(length, 1)) > 0.8
    }

    private static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        var previous = Array(0...b.count)
        for (i, character) in a.enumerated() {
            var current = [i + 1] + Array(repeating: 0, count: b.count)
            for j in b.indices {
                current[j + 1] = min(current[j] + 1, previous[j + 1] + 1,
                                     previous[j] + (character == b[j] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}
