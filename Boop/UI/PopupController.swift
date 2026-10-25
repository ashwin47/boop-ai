//
//  PopupController.swift
//  Boop
//

import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

@MainActor
@Observable
final class PopupController {
    static let shared = PopupController()

    private(set) var original = ""
    /// The action being run, while the model is working on it.
    private(set) var runningAction: RewriteAction?
    private(set) var errorMessage: String?
    private(set) var highlightedIndex = 0

    @ObservationIgnored private var popover: NSPopover?
    @ObservationIgnored private var anchorWindow: AnchorWindow?
    @ObservationIgnored private var captureTask: Task<Void, Never>?
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var sourceApp: NSRunningApplication?
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var globalKeyMonitor: Any?
    @ObservationIgnored private var clickMonitor: Any?
    @ObservationIgnored private lazy var popoverDelegate = PopoverDelegate { [weak self] in
        self?.teardown()
    }

    private init() {}

    var isRunning: Bool { runningAction != nil }

    var menuItems: [RewriteAction] { BoopSettings.shared.actions }

    // MARK: - Entry point

    /// Called when the global hot key fires.
    func trigger() {
        guard AccessibilityPermission.isGranted else {
            AccessibilityPermission.request()
            return
        }
        guard BoopSettings.shared.isConfigured else {
            SettingsWindow.open()
            return
        }

        // Remember who to hand focus (and the paste) back to. If Boop somehow is
        // frontmost, there's no foreign selection to read.
        let frontmost = NSWorkspace.shared.frontmostApplication
        guard frontmost?.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return }
        sourceApp = frontmost

        captureTask?.cancel()
        captureTask = Task {
            guard let selection = await TextCapture.capture(
                useScreenRecognition: BoopSettings.shared.useScreenRecognition
            ) else {
                guard !Task.isCancelled,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmost?.processIdentifier
                else { return }
                resetMenu()
                original = ""
                errorMessage = "Select some text first, then press the Boop hot key."
                present(anchoredTo: nil, kind: .unknown)
                return
            }
            guard !Task.isCancelled else { return }
            resetMenu()
            original = selection.text
            present(anchoredTo: selection.anchor, kind: selection.anchorKind)
        }
    }

    private func resetMenu() {
        streamTask?.cancel()
        runningAction = nil
        errorMessage = nil
        highlightedIndex = 0
    }

    // MARK: - Menu

    func highlight(_ index: Int) {
        highlightedIndex = index
    }

    func moveHighlight(by offset: Int) {
        let count = menuItems.count
        guard count > 0 else { return }
        highlightedIndex = (highlightedIndex + offset + count) % count
    }

    func run(at index: Int) {
        let items = menuItems
        guard items.indices.contains(index) else { return }
        highlightedIndex = index
        run(items[index])
    }

    /// Sends the selection through `action` and pastes the reply over it.
    func run(_ action: RewriteAction) {
        guard !original.isEmpty, !isRunning else { return }
        streamTask?.cancel()
        errorMessage = nil
        runningAction = action

        let settings = BoopSettings.shared
        let client = GatewayClient(settings: settings)
        let model = settings.modelID
        let effort = settings.reasoningEffort
        let text = original

        streamTask = Task {
            do {
                var output = ""
                for try await delta in client.stream(
                    model: model, system: action.prompt, user: text, effort: effort
                ) {
                    guard !Task.isCancelled else { return }
                    output += delta
                }
                // Cancellation can end AsyncThrowingStream without throwing.
                // A dismissed or superseded request must not paste anything.
                guard !Task.isCancelled else { return }
                let result = output.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !result.isEmpty else {
                    runningAction = nil
                    errorMessage = "The model returned an empty response."
                    return
                }
                if settings.playSoundsOnComplete {
                    CompletionSound.shared.play()
                }
                replaceSelection(with: result)
            } catch {
                guard !Task.isCancelled else { return }
                runningAction = nil
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
    }

    /// Puts the text on the pasteboard, gives focus back to the original app and
    /// sends it a ⌘V so the rewritten text replaces the selection.
    private func replaceSelection(with text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        let app = sourceApp
        dismiss()

        Task {
            // Same trap as the ⌘C capture: a held modifier would turn ⌘V into
            // something else entirely.
            await Synthetic.waitForModifiersToClear()
            app?.activate()
            try? await Task.sleep(for: .milliseconds(120))
            Synthetic.paste()
        }
    }

    // MARK: - Presentation

    private func present(anchoredTo bounds: NSRect?, kind: AnchorKind) {
        let rect = PopupPlacement.anchorRect(for: bounds, kind: kind)

        let window = anchorWindow ?? AnchorWindow()
        anchorWindow = window
        window.setFrame(rect, display: false)
        window.contentView?.frame = NSRect(origin: .zero, size: rect.size)
        window.orderFrontRegardless()

        guard let view = window.contentView else { return }
        let popover = self.popover ?? makePopover()
        self.popover = popover

        // Deliberately no NSApp.activate(): taking focus greys out the selection
        // Boop is about to replace, and drags our other windows forward.
        if !popover.isShown {
            popover.show(relativeTo: view.bounds, of: view,
                         preferredEdge: PopupPlacement.preferredEdge(for: rect))
        }
        // Regenerating/retriggering can reuse an already visible popover.
        popover.positioningRect = view.bounds
        // NSPopover builds its own window; make that one non-activating too so a
        // click on Copy or Paste doesn't yank focus away from the source app.
        if let popoverWindow = popover.contentViewController?.view.window as? NSPanel {
            popoverWindow.styleMask.insert(.nonactivatingPanel)
            popoverWindow.becomesKeyOnlyIfNeeded = true
            // Key (but still non-activating) so arrow keys, Return and digits
            // reach the menu without bringing Boop forward.
            popoverWindow.makeKey()
        }
        popover.contentViewController?.view.window?.orderFrontRegardless()
        installDismissMonitors()
    }

    private func makePopover() -> NSPopover {
        let popover = NSPopover()
        popover.contentSize = PopupPlacement.size
        // `.transient` closes whenever our app stops being active — but Boop is
        // never active by design, and anything stealing focus mid-stream would
        // make the popup vanish. Dismissal is handled explicitly instead.
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.delegate = popoverDelegate

        let host = NSHostingController(rootView: PopupView(controller: self))
        host.preferredContentSize = PopupPlacement.size
        popover.contentViewController = host
        return popover
    }

    func dismiss() {
        if popover?.isShown == true { popover?.performClose(nil) }
        teardown()
    }

    /// Idempotent — reached both from `dismiss()` and from the popover closing
    /// itself when the user clicks away.
    private func teardown() {
        captureTask?.cancel()
        captureTask = nil
        streamTask?.cancel()
        streamTask = nil
        runningAction = nil
        removeDismissMonitors()
        anchorWindow?.orderOut(nil)
    }

    /// Boop isn't the active app while the popup is up, so Escape is also caught
    /// globally in case the popover failed to become key. The local monitor
    /// drives the menu from the keyboard.
    private func installDismissMonitors() {
        removeDismissMonitors()

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Int(event.keyCode) == kVK_Escape else { return }
            self?.dismiss()
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch Int(event.keyCode) {
            case kVK_Escape:
                dismiss()
            case kVK_UpArrow:
                if !isRunning { moveHighlight(by: -1) }
            case kVK_DownArrow:
                if !isRunning { moveHighlight(by: 1) }
            case kVK_Return, kVK_ANSI_KeypadEnter:
                if !isRunning { run(at: highlightedIndex) }
            default:
                // 1–9 run the matching row directly.
                guard let digit = event.charactersIgnoringModifiers.flatMap(Int.init),
                      (1...9).contains(digit),
                      event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty
                else { return event }
                if !isRunning { run(at: digit - 1) }
            }
            return nil
        }
        // Global mouse monitors only see clicks in *other* apps, so this dismisses
        // on a click away without swallowing clicks on our own buttons.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.dismiss()
        }
    }

    private func removeDismissMonitors() {
        for monitor in [keyMonitor, globalKeyMonitor, clickMonitor] {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
        keyMonitor = nil
        globalKeyMonitor = nil
        clickMonitor = nil
    }
}

/// `@Observable` types can't also be `NSObject` subclasses, so the popover's
/// delegate lives here.
private final class PopoverDelegate: NSObject, NSPopoverDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func popoverDidClose(_ notification: Notification) {
        onClose()
    }
}
