import SwiftUI
import AppKit

enum Corner: String, CaseIterable {
    case bottomRight = "Bottom Right"
    case bottomLeft  = "Bottom Left"
    case topRight    = "Top Right"
    case topLeft     = "Top Left"
}

enum Layer: String, CaseIterable {
    case behind = "Behind Everything"
    case onTop  = "Always on Top"
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let honey = Honey(sheet: SpriteSheet.load())
    private lazy var game = BreakGame(honey: honey)
    private var statusItem: NSStatusItem!
    private var window: NSWindow!
    private var hostingView: TrackingHostingView!

    private var corner: Corner? = .bottomRight
    private var freeOrigin: CGPoint?
    private var isProgrammaticMove = false
    private var layer: Layer = .behind
    private var showOnDesktop = true

    // Break-game feature
    private var breakEnabled = true
    private var enabledGames: Set<String> = ["catch", "tap", "react"]
    private var forcedGame: String?
    private var hoverMs = 5000
    private var chosenMode = "catch"

    // Session/window arbitration
    private var gameOwnsWindow = false
    private var savedFrame = NSRect.zero          // widget footprint at arm start (growth origin)
    private var gameFullFrame = NSRect.zero       // fully-grown play area (growth target)
    private var savedLayer: Layer = .behind
    private var savedMovable = true

    private let games: [(id: String, name: String)] = [
        ("catch", "Snack Catch"), ("tap", "Quick Tap"), ("react", "Reaction")
    ]

    private let sizes: [(name: String, scale: Int)] = [
        ("Small", 3), ("Medium", 4), ("Large", 5)
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadSettings()
        honey.onFrameChange = { [weak self] in self?.updateMenuBarIcon() }
        honey.onLayoutChange = { [weak self] in self?.relayout() }
        honey.start()
        configureGame()
        makeWindow()
        makeStatusItem()
        updateMenuBarIcon()
    }

    private func configureGame() {
        game.getChar = { [weak self] in self?.honey.cast.id ?? "honey" }
        game.getMode = { [weak self] in self?.chosenMode ?? "catch" }
        game.armMs = Double(hoverMs)
        game.onArmBegin = { [weak self] in self?.armInWidget() }
        game.onGameShown = { [weak self] in self?.growIntoPlayArea() }
        game.onGameHidden = { [weak self] in self?.hideGameOverlay() }
    }

    // MARK: - Persistence

    private func loadSettings() {
        let d = UserDefaults.standard
        if d.object(forKey: "scale") != nil { honey.scale = d.integer(forKey: "scale") }
        if let raw = d.string(forKey: "corner") {
            corner = (raw == "free") ? nil : Corner(rawValue: raw)
            if corner == nil, d.object(forKey: "freeOriginX") != nil {
                freeOrigin = CGPoint(x: d.double(forKey: "freeOriginX"), y: d.double(forKey: "freeOriginY"))
            }
        }
        if let raw = d.string(forKey: "layer"), let l = Layer(rawValue: raw) { layer = l }
        if d.object(forKey: "showOnDesktop") != nil { showOnDesktop = d.bool(forKey: "showOnDesktop") }
        if let raw = d.string(forKey: "forcedCast") { honey.forcedCastID = (raw == "auto") ? nil : raw }
        if let raw = d.array(forKey: "enabledCasts") as? [String], !raw.isEmpty {
            honey.enabledCasts = Set(raw)
        }
        if d.object(forKey: "breakEnabled") != nil { breakEnabled = d.bool(forKey: "breakEnabled") }
        if let raw = d.array(forKey: "enabledGames") as? [String], !raw.isEmpty { enabledGames = Set(raw) }
        if let raw = d.string(forKey: "forcedGame") { forcedGame = (raw == "random") ? nil : raw }
        if d.object(forKey: "hoverMs") != nil { hoverMs = d.integer(forKey: "hoverMs") }
    }

    private func saveSettings() {
        let d = UserDefaults.standard
        d.set(honey.scale, forKey: "scale")
        d.set(corner?.rawValue ?? "free", forKey: "corner")
        if let o = freeOrigin {
            d.set(Double(o.x), forKey: "freeOriginX")
            d.set(Double(o.y), forKey: "freeOriginY")
        }
        d.set(layer.rawValue, forKey: "layer")
        d.set(showOnDesktop, forKey: "showOnDesktop")
        d.set(honey.forcedCastID ?? "auto", forKey: "forcedCast")
        d.set(Array(honey.enabledCasts), forKey: "enabledCasts")
        d.set(breakEnabled, forKey: "breakEnabled")
        d.set(Array(enabledGames), forKey: "enabledGames")
        d.set(forcedGame ?? "random", forKey: "forcedGame")
        d.set(hoverMs, forKey: "hoverMs")
    }

    // MARK: - Floating companion window

    private func makeWindow() {
        hostingView = TrackingHostingView(
            rootView: AnyView(ContentView(game: game).environmentObject(honey))
        )
        hostingView.onEnter = { [weak self] in self?.hoverEntered() }
        hostingView.onExit = { [weak self] in self?.hoverExited() }
        hostingView.onMove = { [weak self] p in self?.pointerMoved(p) }
        hostingView.onDown = { [weak self] p in self?.pointerDown(p) }

        let win = GameWindow(
            contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        win.contentView = hostingView
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.isMovableByWindowBackground = true
        win.acceptsMouseMovedEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        win.tabbingMode = .disallowed
        win.delegate = self
        self.window = win

        applyLayer()
        layoutWindow()
        if showOnDesktop { win.orderFrontRegardless() }
    }

    // MARK: - Break-game input + window transition

    private func hoverEntered() {
        guard breakEnabled else { return }
        if game.phase == .idle { chosenMode = forcedGame ?? enabledGames.randomElement() ?? "catch" }
        game.mouseEntered()
    }
    private func hoverExited() { game.mouseExited() }

    /// Convert a hosting-view point to logical field cells. NSHostingView is a
    /// flipped view, so `convert(_:from:nil)` already yields top-left coords —
    /// only flip manually if the view ever reports non-flipped.
    private func fieldPoint(_ p: NSPoint) -> (Double, Double) {
        let s = CGFloat(game.renderScale)
        let y = hostingView.isFlipped ? p.y : hostingView.bounds.height - p.y
        return (Double(p.x / s), Double(y / s))
    }
    private func pointerMoved(_ p: NSPoint) { let f = fieldPoint(p); game.setMouse(f.0, f.1) }
    private func pointerDown(_ p: NSPoint)  { let f = fieldPoint(p); game.pointerDown(f.0, f.1) }

    /// Hover armed: the meter fills inside the widget's own footprint, which
    /// stays draggable. We only pause the ambient animation — the window keeps
    /// its exact frame (no resize/re-pin), so the perk-up stays centered where
    /// the sprite was and a mouse-out reliably fires `exit` to cancel. The
    /// perk pose is fitted into the ambient box by PerkView.
    private func armInWidget() {
        honey.paused = true
    }

    /// Meter full: take over the window and quickly grow the bordered play area
    /// out from the widget's current corner.
    private func growIntoPlayArea() {
        guard let screen = window.screen ?? NSScreen.main else { return }
        savedFrame = window.frame
        savedLayer = layer
        savedMovable = window.isMovableByWindowBackground
        gameOwnsWindow = true
        hostingView.interceptInput = true
        window.isMovableByWindowBackground = false

        let vf = screen.visibleFrame
        let sW = Int((vf.width * 0.36) / CGFloat(FW))
        let sH = Int((vf.height * 0.50) / CGFloat(FH))
        game.renderScale = max(3, min(11, min(sW, sH)))
        gameFullFrame = fullPlayFrame(from: savedFrame, in: vf, scale: game.renderScale)

        hostingView.rootView = AnyView(
            SessionRoot(game: game, palette: honey.sheet.palette)
        )
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        isProgrammaticMove = true
        window.setFrame(gameFullFrame, display: true, animate: true)   // fast grow (0.3s)
        isProgrammaticMove = false
    }

    /// The fully-grown play area, anchored to the widget's bottom-center: the
    /// bottom edge stays put while the area expands symmetrically left/right and
    /// upward, so the sprite stays centered at the bottom as it grows. Clamped
    /// on-screen (which may nudge the anchor near an edge).
    private func fullPlayFrame(from saved: NSRect, in vf: NSRect, scale: Int) -> NSRect {
        let w = CGFloat(FW * scale), h = CGFloat(FH * scale)
        var x = saved.midX - w / 2
        var y = saved.minY
        x = min(max(x, vf.minX), vf.maxX - w)
        y = min(max(y, vf.minY), vf.maxY - h)
        return NSRect(x: x, y: y, width: w, height: h)
    }

    /// Restore the ambient widget after a game session ends (or an arm cancel).
    /// An arm cancel never took over the window — it only paused the ambient
    /// animation — so resume + relayout always run; the full restore only when
    /// a game actually grew the window.
    private func hideGameOverlay() {
        if gameOwnsWindow {
            gameOwnsWindow = false
            hostingView.interceptInput = false
            hostingView.rootView = AnyView(ContentView(game: game).environmentObject(honey))
            window.isMovableByWindowBackground = savedMovable
            layer = savedLayer
            applyLayer()
        }
        honey.resumeAmbient()
        DispatchQueue.main.async { self.layoutWindow() }
    }

    /// Called when the scene/cast changes: resize the window (solo↔together widths)
    /// after SwiftUI relayouts, and refresh the menu-bar icon.
    private func relayout() {
        if gameOwnsWindow { return }
        DispatchQueue.main.async { self.layoutWindow() }
        updateMenuBarIcon()
    }

    private func layoutWindow() {
        if gameOwnsWindow { return }
        var frame = window.frame
        frame.size = hostingView.fittingSize
        isProgrammaticMove = true
        defer { isProgrammaticMove = false }
        window.setFrame(frame, display: true)
        if let corner {
            pin(to: corner)
        } else if let o = freeOrigin {
            window.setFrameOrigin(o)
        }
    }

    /// The user dragged the window: drop the corner pin and remember the position.
    func windowDidMove(_ notification: Notification) {
        guard !isProgrammaticMove, !gameOwnsWindow else { return }
        corner = nil
        freeOrigin = window.frame.origin
        saveSettings()
    }

    private func pin(to corner: Corner) {
        self.corner = corner
        guard let screen = window.screen ?? NSScreen.main else { return }
        let vf = screen.visibleFrame
        let s = window.frame.size
        let m: CGFloat = 24
        let x: CGFloat, y: CGFloat
        switch corner {
        case .bottomRight: x = vf.maxX - s.width - m; y = vf.minY + m
        case .bottomLeft:  x = vf.minX + m;           y = vf.minY + m
        case .topRight:    x = vf.maxX - s.width - m; y = vf.maxY - s.height - m
        case .topLeft:     x = vf.minX + m;           y = vf.maxY - s.height - m
        }
        window.setFrameOrigin(CGPoint(x: x, y: y))
    }

    private func applyLayer() {
        switch layer {
        case .onTop:  window.level = .floating
        case .behind: window.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)
        }
    }

    // MARK: - Animated menu-bar icon

    private func updateMenuBarIcon() {
        guard let button = statusItem?.button else { return }
        button.image = Self.renderIcon(pixels: honey.currentPixels, bounds: honey.scene.bounds)
    }

    private static func renderIcon(pixels: [Pixel], bounds: PixelBounds) -> NSImage {
        let contentHeight: CGFloat = 20
        let s = contentHeight / CGFloat(bounds.height)
        let size = NSSize(width: max(1, s * CGFloat(bounds.width)), height: contentHeight)

        let image = NSImage(size: size)
        image.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.interpolationQuality = .none
            ctx.setShouldAntialias(false)
            for p in pixels {
                ctx.setFillColor(p.cg)
                // floor each edge so the fractional cell size tiles seamlessly (no grid lines)
                let x0 = (CGFloat(p.x - bounds.minX) * s).rounded(.down)
                let y0 = (size.height - CGFloat(p.y - bounds.minY + 1) * s).rounded(.down)
                let x1 = (CGFloat(p.x - bounds.minX + 1) * s).rounded(.down)
                let y1 = (size.height - CGFloat(p.y - bounds.minY) * s).rounded(.down)
                ctx.fill(CGRect(x: x0, y: y0, width: max(1, x1 - x0), height: max(1, y1 - y0)))
            }
        }
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    // MARK: - Menu bar

    private func makeStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu(menu)
    }

    func menuNeedsUpdate(_ menu: NSMenu) { rebuildMenu(menu) }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let header = NSMenuItem(title: "\(honey.cast.name) — \(honey.scene.label)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        // Cast: Auto, or force a specific cast.
        var castItems = [item("Auto (rotate)", selector: #selector(setCast(_:)),
                              represented: "auto", checked: honey.forcedCastID == nil)]
        castItems += honey.sheet.casts.map { c in
            item(c.name, selector: #selector(setCast(_:)), represented: c.id,
                 checked: honey.forcedCastID == c.id)
        }
        menu.addItem(submenu("Cast", items: castItems))

        // In the rotation: which casts the Auto loop may visit.
        menu.addItem(submenu("In the rotation", items: honey.sheet.casts.map { c in
            item(c.name, selector: #selector(toggleRotation(_:)), represented: c.id,
                 checked: honey.enabledCasts.contains(c.id))
        }))

        // Scene: the current cast's scenes.
        menu.addItem(submenu("Scene", items: honey.cast.scenes.map { s in
            item(s.label, selector: #selector(selectScene(_:)), represented: s.id,
                 checked: s.id == honey.scene.id)
        }))

        menu.addItem(.separator())

        let show = NSMenuItem(title: "Show on Desktop", action: #selector(toggleDesktop), keyEquivalent: "")
        show.target = self
        show.state = showOnDesktop ? .on : .off
        menu.addItem(show)

        menu.addItem(submenu("Size", items: sizes.map { sz in
            item(sz.name, selector: #selector(setSize(_:)), represented: sz.scale,
                 checked: honey.scale == sz.scale)
        }))
        menu.addItem(submenu("Pin to Corner", items: Corner.allCases.map { c in
            item(c.rawValue, selector: #selector(setCorner(_:)), represented: c.rawValue, checked: corner == c)
        }))
        menu.addItem(submenu("Layer", items: Layer.allCases.map { l in
            item(l.rawValue, selector: #selector(setLayer(_:)), represented: l.rawValue, checked: layer == l)
        }))

        menu.addItem(.separator())
        menu.addItem(buildBreakGameMenu())

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Honey & Bagel", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func item(_ title: String, selector: Selector, represented: Any, checked: Bool) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        mi.target = self
        mi.representedObject = represented
        mi.state = checked ? .on : .off
        return mi
    }

    private func submenu(_ title: String, items: [NSMenuItem]) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        items.forEach { sub.addItem($0) }
        parent.submenu = sub
        return parent
    }

    // MARK: - Actions

    @objc private func setCast(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        honey.setForcedCast(id == "auto" ? nil : id)
        saveSettings()
    }

    @objc private func toggleRotation(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        honey.toggleCastInRotation(id)
        saveSettings()
    }

    @objc private func selectScene(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        honey.selectScene(id)
    }

    @objc private func setSize(_ sender: NSMenuItem) {
        guard let scale = sender.representedObject as? Int else { return }
        honey.scale = scale
        DispatchQueue.main.async { self.layoutWindow() }
        saveSettings()
    }

    @objc private func setCorner(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let c = Corner(rawValue: raw) else { return }
        pin(to: c)
        saveSettings()
    }

    @objc private func setLayer(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let l = Layer(rawValue: raw) else { return }
        layer = l
        applyLayer()
        saveSettings()
    }

    @objc private func toggleDesktop() {
        showOnDesktop.toggle()
        if showOnDesktop {
            layoutWindow()
            window.orderFrontRegardless()
        } else {
            window.orderOut(nil)
        }
        saveSettings()
    }

    // MARK: - Break-game menu

    private func buildBreakGameMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Break Game", action: nil, keyEquivalent: "")
        let sub = NSMenu()

        let hover = NSMenuItem(title: "Hover to Play", action: #selector(toggleBreakGame), keyEquivalent: "")
        hover.target = self
        hover.state = breakEnabled ? .on : .off
        sub.addItem(hover)
        sub.addItem(.separator())

        var gameItems = [item("Random (rotate)", selector: #selector(setForcedGame(_:)),
                              represented: "random", checked: forcedGame == nil)]
        gameItems += games.map { g in
            item(g.name, selector: #selector(setForcedGame(_:)), represented: g.id, checked: forcedGame == g.id)
        }
        sub.addItem(submenu("Game", items: gameItems))

        sub.addItem(submenu("Games in rotation", items: games.map { g in
            item(g.name, selector: #selector(toggleGameInRotation(_:)), represented: g.id,
                 checked: enabledGames.contains(g.id))
        }))

        sub.addItem(submenu("Hover Delay", items: [("3 seconds", 3000), ("5 seconds", 5000), ("8 seconds", 8000)].map { (label, ms) in
            item(label, selector: #selector(setHoverDelay(_:)), represented: ms, checked: hoverMs == ms)
        }))

        parent.submenu = sub
        return parent
    }

    @objc private func toggleBreakGame() {
        breakEnabled.toggle()
        if !breakEnabled { game.abort() }
        saveSettings()
    }

    @objc private func setForcedGame(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        forcedGame = (id == "random") ? nil : id
        saveSettings()
    }

    @objc private func toggleGameInRotation(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        if enabledGames.contains(id) {
            guard enabledGames.count > 1 else { return }   // never disable the last one
            enabledGames.remove(id)
        } else {
            enabledGames.insert(id)
        }
        saveSettings()
    }

    @objc private func setHoverDelay(_ sender: NSMenuItem) {
        guard let ms = sender.representedObject as? Int else { return }
        hoverMs = ms
        game.armMs = Double(ms)
        saveSettings()
    }
}
