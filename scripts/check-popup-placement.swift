import AppKit

/// Compiles alongside the production capture/placement code; does not open an
/// app, read the clipboard, or request Accessibility access.
@main
struct PlacementChecks {
    static func main() {
        let primary = NSRect(x: 0, y: 30, width: 1440, height: 850)
        let leftDisplay = NSRect(x: -1920, y: -200, width: 1920, height: 1080)
        let upperDisplay = NSRect(x: 0, y: 900, width: 1440, height: 900)
        let frames = [primary, leftDisplay, upperDisplay]
        let mouse = NSPoint(x: 1300, y: 800)
        func anchor(_ rect: NSRect?, _ kind: AnchorKind = .glyphs) -> NSRect {
            PopupPlacement.anchorRect(for: rect, kind: kind, visibleFrames: frames, mouse: mouse)
        }
        func edge(_ rect: NSRect) -> NSRectEdge {
            PopupPlacement.preferredEdge(for: rect, visibleFrames: frames)
        }

        let line = NSRect(x: 300, y: 550, width: 420, height: 22)
        let single = anchor(line)
        precondition(single.midX == line.midX, "Anchor must center on the selection, not its first glyph")
        precondition(single.minY < line.minY && single.maxY > line.maxY, "Leave a gap on both sides")
        precondition(edge(single) == .minY, "Prefer below when there is room")
        precondition(single == PopupPlacement.anchorRect(
            for: line, kind: .glyphs, visibleFrames: frames, mouse: .zero
        ), "Moving the pointer must not move a known selection anchor")

        let multiline = NSRect(x: 350, y: 60, width: 500, height: 160)
        let multi = anchor(multiline)
        precondition(multi.contains(multiline), "Keep the entire multiline selection clear")
        precondition(edge(multi) == .maxY, "Bottom-of-screen selections need the popover above")

        let left = NSRect(x: -1800, y: -170, width: 320, height: 20)
        precondition(leftDisplay.contains(anchor(left)), "Respect negative display coordinates")
        precondition(edge(anchor(left)) == .maxY, "Choose the edge using the selection's own display")
        let upper = NSRect(x: 400, y: 1550, width: 400, height: 24)
        precondition(upperDisplay.contains(anchor(upper)) && edge(anchor(upper)) == .minY,
                     "Respect vertically stacked displays")

        let scrolled = NSRect(x: 500, y: 820, width: 300, height: 300)
        let clipped = anchor(scrolled)
        precondition(upperDisplay.contains(clipped), "Choose the display with the largest visible portion")
        let huge = anchor(NSRect(x: -3000, y: -2000, width: 9000, height: 5000))
        precondition(frames.contains(where: { $0.contains(huge) }), "Oversized anchors must fit one display")

        let pointer = NSRect(origin: mouse, size: NSSize(width: 1, height: 1))
        precondition(anchor(nil) == pointer)
        precondition(anchor(NSRect(x: CGFloat.nan, y: 100, width: 30, height: 20)) == pointer)
        precondition(anchor(NSRect(x: 10000, y: 10000, width: 30, height: 20)) == pointer,
                     "Reject stale offscreen bounds")
        let control = NSRect(x: 300, y: 60, width: 600, height: 240)
        precondition(anchor(control, .element).contains(control), "Do not invent a line inside a control")
        precondition(anchor(primary, .window).origin == NSPoint(x: primary.midX, y: primary.midY),
                     "A window fallback must not follow a mouse parked outside the editor")
        precondition(anchor(primary, .unknown) == pointer)
        print("Placement checks passed: selection centering, mouse independence, multiline clearance, screen edges, multiple displays, clipping, and fallbacks.")
    }
}
