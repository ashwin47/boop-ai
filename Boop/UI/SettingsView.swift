//
//  SettingsView.swift
//  Boop
//

import AppKit
import Combine
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            GatewaySettings()
                .tabItem { Label("Gateway", systemImage: "key") }
            ActionSettings()
                .tabItem { Label("Actions", systemImage: "list.bullet") }
        }
        .frame(width: 480, height: 460)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Bindable private var settings = BoopSettings.shared
    @State private var hasAccessibility = AccessibilityPermission.isGranted
    @State private var hasScreenRecording = ScreenSelectionLocator.hasPermission

    /// Re-checked when the app comes forward rather than on a timer: the window is
    /// never released, so a `Timer.publish` here would keep firing for the life of
    /// the app even with Settings closed.
    private let becameActive = NotificationCenter.default
        .publisher(for: NSApplication.didBecomeActiveNotification)

    var body: some View {
        Form {
            Section {
                LabeledContent("Shortcut") {
                    HotKeyRecorder(settings: settings)
                }
                Text("Defaults to Hyper + A (⌃ ⌥ ⇧ ⌘ A) — what a caps-lock Hyper key sends.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Hot Key")
            }

            Section {
                Picker("Model", selection: $settings.modelID) {
                    ForEach(Provider.allCases) { provider in
                        Section(provider.rawValue) {
                            ForEach(AIModel.models(for: provider)) { model in
                                Text(model.name).tag(model.id)
                            }
                        }
                    }
                }
                Picker("Reasoning effort", selection: $settings.reasoningEffort) {
                    ForEach(ReasoningEffort.allCases) { effort in
                        Text(effort.label).tag(effort)
                    }
                }
                Text("Higher effort means slower, more considered rewrites. Models that don't support reasoning ignore this and fall back to their default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Model")
            }

            Section {
                Toggle("Play sounds on complete", isOn: $settings.playSoundsOnComplete)
            } header: {
                Text("Sounds")
            }

            Section {
                Toggle("Find selected text on screen", isOn: $settings.useScreenRecognition)
                Text("When an app cannot provide text bounds, recognize the selected text in a screenshot of its window. Processing stays on your Mac; the image is never saved or sent to AI.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if settings.useScreenRecognition {
                    LabeledContent("Screen Recording") {
                        if hasScreenRecording {
                            Label("Granted", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Button("Allow Screen Recording…") {
                                ScreenSelectionLocator.requestPermission()
                                hasScreenRecording = ScreenSelectionLocator.hasPermission
                            }
                        }
                    }
                    Text("macOS requires Screen Recording permission for this fallback. You may need to restart Boop after granting access.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Popover Placement")
            }

            Section {
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { UpdaterManager.shared.automaticallyChecksForUpdates },
                    set: { UpdaterManager.shared.automaticallyChecksForUpdates = $0 }
                ))
                LabeledContent("Version") {
                    HStack(spacing: 8) {
                        Text(UpdaterManager.shared.currentVersion)
                            .foregroundStyle(.secondary)
                        Button("Check Now") { UpdaterManager.shared.checkForUpdates() }
                    }
                }
            } header: {
                Text("Updates")
            }

            Section {
                LabeledContent("Accessibility") {
                    HStack(spacing: 8) {
                        Label(
                            hasAccessibility ? "Granted" : "Not granted",
                            systemImage: hasAccessibility
                                ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                        )
                        .foregroundStyle(hasAccessibility ? Color.green : Color.orange)
                        if !hasAccessibility {
                            Button("Open Settings…") { AccessibilityPermission.openSettings() }
                        }
                    }
                }
                Text("Boop needs Accessibility access to read the selected text and to paste the result back.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Permissions")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            hasAccessibility = AccessibilityPermission.isGranted
            hasScreenRecording = ScreenSelectionLocator.hasPermission
        }
        .onReceive(becameActive) { _ in
            hasAccessibility = AccessibilityPermission.isGranted
            hasScreenRecording = ScreenSelectionLocator.hasPermission
        }
    }
}

// MARK: - Gateway

private struct GatewaySettings: View {
    @Bindable private var settings = BoopSettings.shared

    var body: some View {
        Form {
            Section {
                TextField("Account ID", text: $settings.accountID, prompt: Text("a1b2c3…"))
                TextField("Gateway name", text: $settings.gatewayID, prompt: Text("boop"))
                SecureField("Gateway token", text: $settings.token)
            } header: {
                Text("Cloudflare AI Gateway")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Boop sends every request through your own Cloudflare AI Gateway, so provider keys stay in your Cloudflare account and never touch this app.")
                    Text("Store your OpenAI / Anthropic / Google keys in the gateway's provider settings, then create a gateway authentication token and paste it above.")
                    Link(
                        "Open the AI Gateway dashboard",
                        destination: URL(string: "https://dash.cloudflare.com/?to=/:account/ai/ai-gateway")!
                    )
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }

            Section {
                LabeledContent("Status") {
                    Label(
                        settings.isConfigured ? "Configured" : "Incomplete",
                        systemImage: settings.isConfigured
                            ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                    )
                    .foregroundStyle(settings.isConfigured ? Color.green : Color.orange)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Actions

private struct ActionSettings: View {
    @Bindable private var settings = BoopSettings.shared
    @State private var selection: RewriteAction.ID?

    private var selectedIndex: Int? {
        settings.actions.firstIndex { $0.id == selection }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $selection) {
                ForEach(settings.actions) { action in
                    Label(action.name.isEmpty ? "Untitled" : action.name, systemImage: action.icon)
                        .tag(action.id)
                }
                .onMove { settings.actions.move(fromOffsets: $0, toOffset: $1) }
            }
            .frame(height: 150)

            HStack(spacing: 4) {
                Button {
                    let action = RewriteAction(
                        name: "New action", icon: "sparkles",
                        prompt: RewriteAction.template("Rewrite the user's text to ")
                    )
                    settings.actions.append(action)
                    selection = action.id
                } label: {
                    Image(systemName: "plus").frame(width: 16)
                }
                Button {
                    guard let index = selectedIndex else { return }
                    settings.actions.remove(at: index)
                    selection = nil
                } label: {
                    Image(systemName: "minus").frame(width: 16)
                }
                .disabled(selectedIndex == nil)
                Spacer()
                Text("Drag to reorder. 1–9 run an action from the menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Restore Defaults") {
                    settings.actions = RewriteAction.defaults
                    selection = nil
                }
            }
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            if let index = selectedIndex {
                Form {
                    TextField("Name", text: $settings.actions[index].name)
                    Picker("Icon", selection: $settings.actions[index].icon) {
                        ForEach(iconChoices(including: settings.actions[index].icon), id: \.self) { icon in
                            Image(systemName: icon).tag(icon)
                        }
                    }
                    Section {
                        TextEditor(text: $settings.actions[index].prompt)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(minHeight: 120)
                    } header: {
                        Text("System Prompt")
                    } footer: {
                        Text("The selected text is sent as the user message, and the reply replaces it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)
            } else {
                Text("Select an action to edit its name, icon and prompt.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// Keeps an icon chosen before the list changed selectable.
    private func iconChoices(including current: String) -> [String] {
        RewriteAction.iconChoices.contains(current)
            ? RewriteAction.iconChoices : [current] + RewriteAction.iconChoices
    }
}
