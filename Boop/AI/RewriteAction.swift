//
//  RewriteAction.swift
//  Boop
//

import Foundation

/// One entry in the hot-key menu: a named system prompt applied to the selection.
struct RewriteAction: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    /// SF Symbol shown next to the name.
    var icon: String
    var prompt: String

    /// Output rules every rewrite needs, or the reply can't be pasted straight
    /// over the selection.
    static let outputRules = """
        Rules:
        - Preserve the original meaning and language unless told otherwise.
        - Keep any existing formatting, line breaks, lists and code untouched in structure.
        - Reply with the rewritten text only. No preamble, no explanation, no quotation marks, \
        no markdown fences.
        """

    static func template(_ task: String) -> String {
        "You are a writing assistant. \(task)\n\n\(outputRules)"
    }

    static let defaults: [RewriteAction] = [
        RewriteAction(
            name: "Improve writing", icon: "wand.and.stars",
            prompt: template("""
                Rewrite the user's text so it reads clearly and correctly: fix spelling, grammar \
                and punctuation, tighten wordy phrasing, and improve flow. Keep the tone and \
                register — casual stays casual — and roughly the same length.
                """)
        ),
        RewriteAction(
            name: "Expand my writing", icon: "arrow.up.left.and.arrow.down.right",
            prompt: template("""
                Expand the user's text with more detail and smoother transitions. Do not invent \
                facts; elaborate only on what is already there. Keep the original tone.
                """)
        ),
        RewriteAction(
            name: "Fix spelling and grammar", icon: "textformat.abc",
            prompt: template("""
                Fix only spelling, grammar and punctuation mistakes in the user's text. Do not \
                reword anything that is already correct.
                """)
        ),
        RewriteAction(
            name: "Simplify my writing", icon: "text.alignleft",
            prompt: template("""
                Rewrite the user's text in plain, simple language with short sentences and common \
                words, so anyone can understand it.
                """)
        ),
    ]

    /// Icons offered in Settings.
    static let iconChoices = [
        "wand.and.stars", "sparkles", "bolt", "textformat.abc", "text.alignleft",
        "arrow.down.right.and.arrow.up.left", "arrow.up.left.and.arrow.down.right",
        "briefcase", "face.smiling", "globe", "list.bullet", "checkmark.circle",
        "pencil", "lightbulb", "heart",
    ]
}
