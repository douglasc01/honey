import SwiftUI
import AppKit

/// A borderless window can't become key by default, so it wouldn't receive the
/// clicks/keys the minigame needs. This lets it become key while still being a
/// borderless desktop companion.
final class GameWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    /// A quick, fixed grow when the play area opens (vs. AppKit's size-scaled default).
    override func animationResizeTime(_ newFrame: NSRect) -> TimeInterval { 0.3 }
}

/// Hosts the SwiftUI content and provides the hover/mouse input the break game
/// needs. While `interceptInput` is set (during a game) it captures all mouse
/// events for the game; otherwise it behaves like a normal companion view
/// (window-drag preserved). A single `.inVisibleRect` tracking area auto-tracks
/// the bounds, so resizes don't need manual rect math.
final class TrackingHostingView: NSHostingView<AnyView> {
    var interceptInput = false
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    var onMove: ((NSPoint) -> Void)?
    var onDown: ((NSPoint) -> Void)?

    private var trackingAreaRef: NSTrackingArea?

    required init(rootView: AnyView) { super.init(rootView: rootView) }
    @MainActor required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let a = trackingAreaRef { removeTrackingArea(a) }
        let a = NSTrackingArea(rect: .zero,
                               options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                               owner: self)
        addTrackingArea(a)
        trackingAreaRef = a
    }

    override func hitTest(_ point: NSPoint) -> NSView? { interceptInput ? self : super.hitTest(point) }
    override var mouseDownCanMoveWindow: Bool { !interceptInput }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
    override func mouseMoved(with event: NSEvent) { onMove?(convert(event.locationInWindow, from: nil)) }
    override func mouseDown(with event: NSEvent) {
        if interceptInput { onDown?(convert(event.locationInWindow, from: nil)) }
        else { super.mouseDown(with: event) }
    }
}
