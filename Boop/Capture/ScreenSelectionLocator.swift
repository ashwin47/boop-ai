import AppKit
import ScreenCaptureKit
import Vision

/// Captures only the source window, recognizes text on-device, then discards
/// the image. No screenshot is saved or included in the AI request.
enum ScreenSelectionLocator {
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    static func requestPermission() {
        if !CGRequestScreenCaptureAccess(), let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ) {
            NSWorkspace.shared.open(url)
        }
    }

    static func locate(text: String, pid: pid_t) async -> NSRect? {
        guard hasPermission, let source = frontWindow(pid: pid) else { return nil }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            guard !Task.isCancelled, isFrontmost(pid),
                  let window = content.windows.first(where: {
                      $0.windowID == source.id && $0.owningApplication?.processID == pid
                  }) else { return nil }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            // Render at up to 2x for accurate small-text recognition, bounded for large monitors.
            let scale = min(2, 4096 / max(window.frame.width, window.frame.height))
            config.width = max(1, Int(window.frame.width * scale))
            config.height = max(1, Int(window.frame.height * scale))
            config.showsCursor = false
            config.ignoreShadowsSingleWindow = true
            config.shouldBeOpaque = true
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let worker = Task.detached(priority: .userInitiated) {
                try recognize(text: text, in: image)
            }
            let normalized = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard let normalized, !Task.isCancelled, isFrontmost(pid),
                  let current = frontWindow(pid: pid), current.id == source.id,
                  current.frame == source.frame else { return nil }
            // Window frames use AX/Quartz coordinates; Vision uses a bottom-left
            // image origin. Convert using the primary display, including negative displays.
            let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
            return screenBounds(normalized: normalized, window: window.frame, primaryTop: primaryTop)
        } catch {
            return nil
        }
    }

    nonisolated static func screenBounds(normalized: CGRect, window: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: window.minX + normalized.minX * window.width,
               y: primaryTop - window.maxY + normalized.minY * window.height,
               width: normalized.width * window.width,
               height: normalized.height * window.height)
    }

    nonisolated static func recognize(text: String, in image: CGImage) throws -> CGRect? {
        try Task.checkCancellation()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        try Task.checkCancellation()
        let observations = request.results ?? []
        let candidates = observations.compactMap { $0.topCandidates(1).first }
        let lines = candidates.map { candidate -> ScreenTextMatcher.Line in
            let range = candidate.string.startIndex..<candidate.string.endIndex
            let box = (try? candidate.boundingBox(for: range))?.boundingBox ?? .zero
            return ScreenTextMatcher.Line(text: candidate.string, bounds: box)
        }
        guard let match = ScreenTextMatcher.locate(text, in: lines) else { return nil }
        return match.spans.reduce(CGRect.null) { result, span in
            let candidate = candidates[span.line]
            guard let range = Range(span.range, in: candidate.string),
                  let box = try? candidate.boundingBox(for: range) else {
                return result.union(lines[span.line].bounds)
            }
            return result.union(box.boundingBox)
        }
    }

    private static func isFrontmost(_ pid: pid_t) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    }

    private static func frontWindow(pid: pid_t) -> (id: CGWindowID, frame: CGRect)? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }
        for window in windows {
            guard window[kCGWindowOwnerPID as String] as? pid_t == pid,
                  window[kCGWindowLayer as String] as? Int == 0,
                  let id = window[kCGWindowNumber as String] as? CGWindowID,
                  let dictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: dictionary),
                  frame.width > 40, frame.height > 40 else { continue }
            return (id, frame)
        }
        return nil
    }
}
