//
//  TextCapture.swift
//  Boop
//

import AppKit
import ApplicationServices
import OSLog

/// How much the anchor rectangle actually tells us about where the text is.
enum AnchorKind {
    /// The rect of the selected glyphs. Point straight at it.
    case glyphs
    /// The focused control. The selection is somewhere inside it.
    case element
    /// Just the app's window — barely narrows anything down.
    case window
    /// Nothing at all.
    case unknown
}

/// What Boop managed to grab when the hot key fired.
struct Selection {
    let text: String
    /// Where to point the popover, in AppKit screen coordinates (origin
    /// bottom-left), or nil when nothing could be worked out at all.
    let anchor: NSRect?
    let anchorKind: AnchorKind
}

enum TextCapture {
    private static let logger = Logger(subsystem: "com.fayazahmed.Boop", category: "Selection")

    private struct Snapshot {
        var text: String?
        var bounds: NSRect?
        var fallback: NSRect?
        var fallbackKind: AnchorKind = .unknown
        var method = "fallback"
    }

    /// Chromium may build its accessibility tree asynchronously after it is enabled.
    /// Re-query fresh elements on a short, bounded retry schedule before using ⌘C.
    static func capture(useScreenRecognition: Bool = false) async -> Selection? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.05)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        var snapshot = Snapshot()
        for attempt in 0..<3 {
            if attempt > 0 {
                do { try await Task.sleep(for: .milliseconds(attempt * 60)) }
                catch { return nil }
            }
            guard !Task.isCancelled,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return nil }
            snapshot = inspect(app: app, pid: pid)
            if snapshot.text != nil && snapshot.bounds != nil { break }
        }

        guard !Task.isCancelled,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return nil }
        let text: String
        if let selected = snapshot.text {
            text = selected
        } else {
            guard let copied = await copyViaPasteboard(expectedPID: pid) else { return nil }
            text = copied
            // Copy also gives a newly enabled web accessibility tree time to settle.
            let refreshed = inspect(app: app, pid: pid)
            if refreshed.text == copied { snapshot = refreshed }
        }
        if snapshot.bounds == nil, useScreenRecognition {
            if !ScreenSelectionLocator.hasPermission {
                snapshot.method = "screen recognition needs permission"
            } else if let bounds = await ScreenSelectionLocator.locate(text: text, pid: pid) {
                snapshot.bounds = bounds
                snapshot.method = "screen recognition"
            } else {
                snapshot.method = "screen recognition unavailable or ambiguous"
            }
        }
        guard !Task.isCancelled,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return nil }
        let kind: AnchorKind = snapshot.bounds == nil ? snapshot.fallbackKind : .glyphs
        logger.info("Selection anchor: \(snapshot.method, privacy: .public), kind: \(String(describing: kind), privacy: .public)")
        return Selection(text: text, anchor: snapshot.bounds ?? snapshot.fallback, anchorKind: kind)
    }

    private static func inspect(app: AXUIElement, pid: pid_t) -> Snapshot {
        let deadline = ContinuousClock.now + .milliseconds(200)
        var snapshot = Snapshot()
        let focused = focusedElement(app: app, pid: pid)
        let window = element(app, kAXFocusedWindowAttribute)
        if let window, let frame = elementFrame(window) {
            snapshot.fallback = frame
            snapshot.fallbackKind = .window
        }
        if let focused, let frame = elementFrame(focused) {
            let role = attribute(focused, kAXRoleAttribute) as? String
            if role != kAXWindowRole && role != kAXApplicationRole && role != "AXWebArea" {
                snapshot.fallback = frame
                snapshot.fallbackKind = .element
            }
        }

        var visited: [AXUIElement] = []
        func probe(_ candidate: AXUIElement) -> Bool {
            guard ContinuousClock.now < deadline,
                  !visited.contains(where: { CFEqual($0, candidate) }) else { return false }
            var candidatePID: pid_t = 0
            guard AXUIElementGetPid(candidate, &candidatePID) == .success,
                  candidatePID == pid else { return false }
            visited.append(candidate)
            AXUIElementSetMessagingTimeout(candidate, 0.04)

            // Treat text markers as opaque AX values; the owning app interprets them.
            let marker = attribute(candidate, "AXSelectedTextMarkerRange")
            let markerText = marker.flatMap {
                nonempty(parameter(candidate, "AXStringForTextMarkerRange", $0) as? String)
            }
            let rangeText = nonempty(attribute(candidate, kAXSelectedTextAttribute) as? String)
            guard let text = markerText ?? rangeText else { return false }
            // Never attach one element's bounds to another element's different selection.
            guard snapshot.text == nil || snapshot.text == text else { return false }
            snapshot.text = text

            if let marker, markerText == text,
               let bounds = rectangle(parameter(candidate, "AXBoundsForTextMarkerRange", marker)) {
                snapshot.bounds = bounds
                snapshot.method = "text-marker range"
                return true
            }
            if rangeText == text, let bounds = selectionBounds(candidate) {
                snapshot.bounds = bounds
                snapshot.method = "character range"
                return true
            }
            return false
        }

        // A contenteditable's selection can belong to its containing AXWebArea.
        var ancestor = focused
        for _ in 0..<10 {
            guard let current = ancestor, ContinuousClock.now < deadline else { break }
            if probe(current) { return snapshot }
            ancestor = element(current, kAXParentAttribute)
        }

        // When focus is a window/group, find its web area without walking an
        // unbounded document tree. Never inspect other windows or applications.
        var queue = window.map { [$0] } ?? []
        var index = 0
        while index < queue.count && index < 60 && ContinuousClock.now < deadline {
            let current = queue[index]
            index += 1
            if probe(current) { return snapshot }
            if let children = attribute(current, kAXChildrenAttribute) as? [AXUIElement] {
                for child in children where queue.count < 60 {
                    if !queue.contains(where: { CFEqual($0, child) }) { queue.append(child) }
                }
            }
        }
        return snapshot
    }

    private static func nonempty(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    private static func focusedElement(app: AXUIElement, pid: pid_t) -> AXUIElement? {
        if let focused = element(app, kAXFocusedUIElementAttribute) { return focused }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.04)
        guard let focused = element(system, kAXFocusedUIElementAttribute) else { return nil }
        var focusedPID: pid_t = 0
        guard AXUIElementGetPid(focused, &focusedPID) == .success, focusedPID == pid else { return nil }
        return focused
    }

    // MARK: - Accessibility

    private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private static func element(_ parent: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(parent, name), CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    /// Asks the focused element for the on-screen rectangle of its selected range.
    private static func selectionBounds(_ element: AXUIElement) -> NSRect? {
        guard let rangeValue = attribute(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(rangeValue) == AXValueGetTypeID(),
              AXValueGetType(rangeValue as! AXValue) == .cfRange
        else { return nil }

        var range = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range),
              range.location >= 0, range.length > 0 else {
            return nil
        }

        // Preserve the full selection so the popover can sit outside it, including
        // when AppKit flips it above a multiline selection near the screen bottom.
        guard let probeValue = AXValueCreate(.cfRange, &range) else { return nil }
        return rectangle(parameter(element, kAXBoundsForRangeParameterizedAttribute, probeValue))
    }

    private static func parameter(_ element: AXUIElement, _ name: String, _ value: CFTypeRef) -> AnyObject? {
        var result: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, name as CFString, value, &result
        ) == .success else { return nil }
        return result
    }

    private static func rectangle(_ value: AnyObject?) -> NSRect? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID(),
              AXValueGetType(value as! AXValue) == .cgRect else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect) else { return nil }
        return visibleRectangle(rect)
    }

    private static func visibleRectangle(_ rect: CGRect) -> NSRect? {
        guard rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.width.isFinite, rect.height.isFinite,
              rect.width >= 0, rect.height > 0 else { return nil }
        var converted = convertFromAX(rect)
        converted.size.width = max(converted.width, 1)
        // Ignore stale/offscreen bounds; clip selections that are partly scrolled out.
        return NSScreen.screens.map { converted.intersection($0.visibleFrame) }
            .filter { !$0.isNull && !$0.isEmpty }
            .max { $0.width * $0.height < $1.width * $1.height }
    }

    private static func elementFrame(_ element: AXUIElement) -> NSRect? {
        AXUIElementSetMessagingTimeout(element, 0.04)
        if let frame = rectangle(attribute(element, "AXFrame")) { return frame }
        // AXPosition + AXSize are the standard attributes; AXFrame is not universal.
        guard let position = attribute(element, kAXPositionAttribute),
              let size = attribute(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(),
              CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        return visibleRectangle(CGRect(origin: origin, size: dimensions))
    }

    /// Accessibility reports top-left-origin coordinates relative to the display
    /// whose origin is (0,0); AppKit wants bottom-left origin.
    private static func convertFromAX(_ rect: CGRect) -> NSRect {
        let zeroScreen = NSScreen.screens.first { $0.frame.origin == .zero }
            ?? NSScreen.screens.first
        guard let zeroScreen else { return rect }
        return NSRect(
            x: rect.origin.x,
            y: zeroScreen.frame.maxY - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    // MARK: - Pasteboard fallback

    private static func copyViaPasteboard(expectedPID: pid_t) async -> String? {
        await Synthetic.waitForModifiersToClear()
        guard !Task.isCancelled,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == expectedPID else { return nil }

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture()
        let changeCountBefore = pasteboard.changeCount

        Synthetic.copy()

        // Apps answer ⌘C on their own schedule; poll briefly rather than guessing.
        var copied: String?
        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(20))
            if pasteboard.changeCount != changeCountBefore {
                copied = pasteboard.string(forType: .string)
                break
            }
        }

        snapshot.restore()

        guard let copied, !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return copied
    }
}
