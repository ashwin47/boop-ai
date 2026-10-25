//
//  BoopSettings.swift
//  Boop
//

import Carbon.HIToolbox
import Observation
import SwiftUI

@Observable
final class BoopSettings {
    static let shared = BoopSettings()

    private let defaults = UserDefaults.standard
    private static let tokenAccount = "gateway-token"

    /// The single prompt Boop shipped with before actions existed.
    private static let legacyDefaultPrompt = """
        You are a writing assistant. Rewrite the user's text so it reads clearly and correctly: \
        fix spelling, grammar and punctuation, tighten wordy phrasing, and improve flow.

        Rules:
        - Preserve the original meaning, language, tone and register. Casual stays casual.
        - Keep roughly the same length. Do not summarise and do not add new information.
        - Keep any existing formatting, line breaks, lists and code untouched in structure.
        - Reply with the rewritten text only. No preamble, no explanation, no quotation marks, \
        no markdown fences.
        """

    // MARK: - Cloudflare AI Gateway

    var accountID: String {
        didSet { defaults.set(accountID, forKey: "accountID") }
    }

    var gatewayID: String {
        didSet { defaults.set(gatewayID, forKey: "gatewayID") }
    }

    /// Stored in the Keychain rather than UserDefaults.
    var token: String {
        didSet { Keychain.set(token, for: Self.tokenAccount) }
    }

    // MARK: - Behaviour

    var useScreenRecognition: Bool {
        didSet { defaults.set(useScreenRecognition, forKey: "useScreenRecognition") }
    }

    var playSoundsOnComplete: Bool {
        didSet { defaults.set(playSoundsOnComplete, forKey: "playSoundsOnComplete") }
    }

    var modelID: String {
        didSet { defaults.set(modelID, forKey: "modelID") }
    }

    /// The entries shown in the hot-key menu, in order.
    var actions: [RewriteAction] {
        didSet {
            if let data = try? JSONEncoder().encode(actions) {
                defaults.set(data, forKey: "actions")
            }
        }
    }

    var reasoningEffort: ReasoningEffort {
        didSet { defaults.set(reasoningEffort.rawValue, forKey: "reasoningEffort") }
    }

    var hotKeyCode: UInt32 {
        didSet { defaults.set(Int(hotKeyCode), forKey: "hotKeyCode") }
    }

    /// Carbon modifier mask (cmdKey, controlKey, optionKey, shiftKey).
    var hotKeyModifiers: UInt32 {
        didSet { defaults.set(Int(hotKeyModifiers), forKey: "hotKeyModifiers") }
    }

    var model: AIModel {
        AIModel.named(modelID) ?? AIModel.fallback
    }

    var isConfigured: Bool {
        !accountID.isEmpty && !gatewayID.isEmpty && !token.isEmpty
    }

    private init() {
        defaults.register(defaults: [
            "useScreenRecognition": false,
            "playSoundsOnComplete": true,
            "modelID": AIModel.defaultID,
            "reasoningEffort": ReasoningEffort.default.rawValue,
            // Hyper + A — what Raycast's caps-lock hyper key produces.
            "hotKeyCode": Int(kVK_ANSI_A),
            "hotKeyModifiers": Int(cmdKey | controlKey | optionKey | shiftKey),
        ])
        accountID = defaults.string(forKey: "accountID") ?? ""
        useScreenRecognition = defaults.bool(forKey: "useScreenRecognition")
        playSoundsOnComplete = defaults.bool(forKey: "playSoundsOnComplete")
        gatewayID = defaults.string(forKey: "gatewayID") ?? ""
        modelID = defaults.string(forKey: "modelID") ?? AIModel.defaultID
        reasoningEffort = defaults.string(forKey: "reasoningEffort")
            .flatMap(ReasoningEffort.init(rawValue:)) ?? .default
        actions = Self.loadActions(from: defaults)
        hotKeyCode = UInt32(defaults.integer(forKey: "hotKeyCode"))
        hotKeyModifiers = UInt32(defaults.integer(forKey: "hotKeyModifiers"))
        token = Keychain.get(Self.tokenAccount)
    }

    private static func loadActions(from defaults: UserDefaults) -> [RewriteAction] {
        if let data = defaults.data(forKey: "actions"),
           let saved = try? JSONDecoder().decode([RewriteAction].self, from: data) {
            return saved
        }
        var actions = RewriteAction.defaults
        // Carry a prompt customised before actions existed over to "Improve writing".
        if let legacy = defaults.string(forKey: "prompt"), legacy != legacyDefaultPrompt {
            actions[0].prompt = legacy
        }
        return actions
    }
}
