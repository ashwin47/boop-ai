import AppKit
import ImageIO

@main
struct ScreenRecognitionChecks {
    static func main() throws {
        typealias Line = ScreenTextMatcher.Line
        let first = CGRect(x: 0.3, y: 0.5, width: 0.4, height: 0.025)
        let second = CGRect(x: 0.3, y: 0.465, width: 0.35, height: 0.025)
        let source = "I looove this app, this helpss you fix your grammer in you mac with a little poopover and its called book"
        let sourceBox = CGRect(x: 0.2965, y: 0.0742, width: 0.3997, height: 0.0136)
        let exact = ScreenTextMatcher.locate(source, in: [Line(text: source, bounds: sourceBox)])
        precondition(exact?.bounds == sourceBox)
        let noisy = source.replacingOccurrences(of: "helpss", with: "helps")
        precondition(ScreenTextMatcher.locate(source, in: [Line(text: noisy, bounds: sourceBox)]) != nil,
                     "Tolerate a small OCR error under the selection highlight")

        let paragraph = [Line(text: "Before: improve this sentence please. After.", bounds: first)]
        let partial = ScreenTextMatcher.locate("improve this sentence please", in: paragraph)!
        let range = Range(partial.spans[0].range, in: paragraph[0].text)!
        precondition(paragraph[0].text[range] == "improve this sentence please",
                     "Return the selected substring, not the whole line")

        let multiline = [Line(text: "Please fix this sentence", bounds: first),
                         Line(text: "and preserve its meaning.", bounds: second)]
        precondition(ScreenTextMatcher.locate("Please fix this sentence and preserve its meaning", in: multiline)?.spans.count == 2)
        precondition(ScreenTextMatcher.locate("Please fix this sentence and preserve its meaning", in: multiline.reversed())?.spans.count == 2,
                     "Recognition order must not break wrapped text")

        let duplicate = [Line(text: source, bounds: first), Line(text: source, bounds: second)]
        precondition(ScreenTextMatcher.locate(source, in: duplicate) == nil,
                     "Do not guess which repeated sentence is selected")
        precondition(ScreenTextMatcher.locate("hello world", in: [Line(text: "hello world hello world", bounds: first)]) == nil,
                     "Repeated substrings on one line are also ambiguous")
        precondition(ScreenTextMatcher.locate("hi", in: [Line(text: "hi", bounds: first)]) == nil)
        precondition(ScreenTextMatcher.locate("Completely unrelated selected text", in: multiline) == nil)
        precondition(ScreenTextMatcher.locate("café déjà vu", in: [Line(text: "cafe deja vu", bounds: first)]) != nil)
        precondition(ScreenTextMatcher.locate("你好世界", in: [Line(text: "你好世界", bounds: first)]) != nil)

        // Regression: a selected multi-paragraph composer with a floating B/I
        // toolbar obscuring "for Ind" and splitting one line into two OCR results.
        let paragraphs = """
            Its been over 6 months and @Patreon still hasnt fixed payments for Indians.
            Support team just says - try a different card.
            Want to support this creator but there's literally no way to do it right now as they are only on Patreon.
            """
        let fragments = [
            Line(text: "Its been over 6 months and @Patreon still hasnt fixed", bounds: CGRect(x: 0.146, y: 0.825, width: 0.742, height: 0.022)),
            Line(text: "payments", bounds: CGRect(x: 0.146, y: 0.792, width: 0.135, height: 0.025)),
            Line(text: "lians.", bounds: CGRect(x: 0.371, y: 0.794, width: 0.081, height: 0.025)),
            Line(text: "B", bounds: CGRect(x: 0.295, y: 0.785, width: 0.016, height: 0.016)),
            Line(text: "I", bounds: CGRect(x: 0.343, y: 0.783, width: 0.018, height: 0.017)),
            Line(text: "Support team just says - try a different card.", bounds: CGRect(x: 0.146, y: 0.721, width: 0.617, height: 0.026)),
            Line(text: "Want to support this creator but there's literally no way", bounds: CGRect(x: 0.146, y: 0.651, width: 0.761, height: 0.028)),
            Line(text: "to do it right now as they are only on Patreon.", bounds: CGRect(x: 0.144, y: 0.621, width: 0.631, height: 0.026)),
        ]
        let paragraphMatch = ScreenTextMatcher.locate(paragraphs, in: fragments)!
        precondition(paragraphMatch.spans.map(\.line) == [0, 1, 2, 5, 6, 7],
                     "Join same-line fragments and skip the floating toolbar across paragraph breaks")
        precondition(paragraphMatch.bounds.minY == 0.621 && paragraphMatch.bounds.maxY == 0.847,
                     "Anchor around the highlighted paragraphs, not the editor toolbar or feed below")
        precondition(ScreenTextMatcher.locate(paragraphs, in: Array(fragments.dropLast(2))) == nil,
                     "Reject incomplete matches when a substantial part of the selection is missing")
        let converted = ScreenSelectionLocator.screenBounds(
            normalized: CGRect(x: 0.25, y: 0.1, width: 0.5, height: 0.05),
            window: CGRect(x: -1600, y: 200, width: 1000, height: 800), primaryTop: 1080
        )
        precondition(converted == CGRect(x: -1350, y: 160, width: 500, height: 40),
                     "Map normalized image coordinates into screen points, including negative displays")
        precondition(ScreenTextMatcher.locate("hello world", in: [Line(text: "hello world", bounds: .zero)]) == nil)
        print("Screen text matching checks passed: exact, fuzzy, substring, multiline, split lines, toolbar occlusion, paragraph breaks, duplicate rejection, unrelated text, and Unicode.")

        // Optional integration check against a user-supplied screenshot. Nothing is saved.
        if CommandLine.arguments.count >= 3 {
            let url = URL(fileURLWithPath: CommandLine.arguments[1])
            let selectedText = CommandLine.arguments[2]
            let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil)!
            let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)!
            let start = ContinuousClock.now
            guard let bounds = try ScreenSelectionLocator.recognize(text: selectedText, in: image) else {
                fatalError("No confident unique match in the screenshot")
            }
            print("Screenshot match (normalized, bottom-left):", bounds)
            print("Recognition elapsed:", ContinuousClock.now - start)
        }
    }
}
