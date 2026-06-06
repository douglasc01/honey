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
    private var statusItem: NSStatusItem!
    private var window: NSWindow!
    private var hostingView: NSHostingView<AnyView>!

    private var corner: Corner? = .bottomRight
    private var freeOrigin: CGPoint?
    private var isProgrammaticMove = false
    private var layer: Layer = .behind
    private var showOnDesktop = true

    private let sizes: [(name: String, scale: Int)] = [
        ("Small", 3), ("Medium", 4), ("Large", 5)
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadSettings()
        honey.onFrameChange = { [weak self] in self?.updateMenuBarIcon() }
        honey.onLayoutChange = { [weak self] in self?.relayout() }
        honey.start()
        makeWindow()
        makeStatusItem()
        updateMenuBarIcon()
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
    }

    // MARK: - Floating companion window

    private func makeWindow() {
        hostingView = NSHostingView(
            rootView: AnyView(ContentView().environmentObject(honey))
        )
        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        win.contentView = hostingView
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.isMovableByWindowBackground = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        win.tabbingMode = .disallowed
        win.delegate = self
        self.window = win

        applyLayer()
        layoutWindow()
        if showOnDesktop { win.orderFrontRegardless() }
    }

    /// Called when the scene/cast changes: resize the window (solo↔together widths)
    /// after SwiftUI relayouts, and refresh the menu-bar icon.
    private func relayout() {
        DispatchQueue.main.async { self.layoutWindow() }
        updateMenuBarIcon()
    }

    private func layoutWindow() {
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
        guard !isProgrammaticMove else { return }
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
            for p in pixels {
                ctx.setFillColor(p.cg)
                let rect = CGRect(x: CGFloat(p.x - bounds.minX) * s,
                                  y: size.height - CGFloat(p.y - bounds.minY + 1) * s,
                                  width: s, height: s)
                ctx.fill(rect)
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
}
