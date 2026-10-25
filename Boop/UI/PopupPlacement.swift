//
//  PopupPlacement.swift
//  Boop
//

import AppKit

enum PopupPlacement {
    static let size = NSSize(width: 300, height: 160)
    private static let selectionGap: CGFloat = 6

    static func anchorRect(for bounds: NSRect?, kind: AnchorKind) -> NSRect {
        anchorRect(for: bounds, kind: kind, visibleFrames: NSScreen.screens.map(\.visibleFrame),
                   mouse: NSEvent.mouseLocation)
    }

    /// Keep the whole selection's vertical extent, so flipping the popover above
    /// it never points into (or covers) the middle of a multiline highlight.
    static func anchorRect(
        for bounds: NSRect?, kind: AnchorKind, visibleFrames: [NSRect], mouse: NSPoint
    ) -> NSRect {
        guard let rect = valid(bounds), let visible = screen(for: rect, in: visibleFrames) else {
            return pointRect(mouse)
        }
        let clipped = rect.intersection(visible)
        switch kind {
        case .glyphs:
            return clipped.insetBy(dx: 0, dy: -selectionGap).intersection(visible)
        case .element:
            // We only know the control's bounds. Keep the popup outside the
            // control rather than inventing a first line at its top-left corner.
            return clipped.insetBy(dx: 0, dy: -selectionGap).intersection(visible)
        case .window:
            // A mouse parked outside the editor is unrelated to a keyboard selection.
            // With only a window available, use a stable position inside that window.
            return pointRect(NSPoint(x: clipped.midX, y: clipped.midY))
        case .unknown:
            return pointRect(mouse)
        }
    }

    static func preferredEdge(for anchor: NSRect) -> NSRectEdge {
        preferredEdge(for: anchor, visibleFrames: NSScreen.screens.map(\.visibleFrame))
    }

    static func preferredEdge(for anchor: NSRect, visibleFrames: [NSRect]) -> NSRectEdge {
        guard let visible = screen(for: anchor, in: visibleFrames) else { return .minY }
        let below = anchor.minY - visible.minY
        let above = visible.maxY - anchor.maxY
        // Include room for the popover's arrow and chrome. AppKit still has the
        // final say when neither side fits, or the window changes screens.
        let requiredHeight = size.height + 24
        return below >= requiredHeight || below >= above ? .minY : .maxY
    }

    private static func pointRect(_ point: NSPoint) -> NSRect {
        NSRect(x: point.x, y: point.y, width: 1, height: 1)
    }

    private static func valid(_ bounds: NSRect?) -> NSRect? {
        guard let bounds, bounds.origin.x.isFinite, bounds.origin.y.isFinite,
              bounds.width.isFinite, bounds.height.isFinite,
              bounds.width >= 0, bounds.height > 0 else { return nil }
        return NSRect(x: bounds.minX, y: bounds.minY,
                      width: max(bounds.width, 1), height: bounds.height)
    }

    private static func screen(for rect: NSRect, in frames: [NSRect]) -> NSRect? {
        frames.filter { $0.intersects(rect) }.max {
            let left = $0.intersection(rect)
            let right = $1.intersection(rect)
            return left.width * left.height < right.width * right.height
        }
    }
}
