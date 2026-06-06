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

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let honey = Honey(sheet: SpriteSheet.load())
    private var statusItem: NSStatusItem!
    private var window: NSWindow!
    private var hostingView: NSHostingView<AnyView>!

    private var corner: Corner = .bottomRight
    private var layer: Layer = .behind
    private var showOnDesktop = true

    private let sizes: [(name: String, scale: Int)] = [
        ("Small", 3), ("Medium", 4), ("Large", 5)
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadSettings()
        honey.start()
        makeWindow()
        makeStatusItem()
        honey.onVisualChange = { [weak self] in self?.updateMenuBarIcon() }
        updateMenuBarIcon()
    }

    // MARK: - Persistence

    private func loadSettings() {
        let d = UserDefaults.standard
        if d.object(forKey: "scale") != nil { honey.scale = d.integer(forKey: "scale") }
        if let raw = d.string(forKey: "corner"), let c = Corner(rawValue: raw) { corner = c }
        if let raw = d.string(forKey: "layer"), let l = Layer(rawValue: raw) { layer = l }
        if d.object(forKey: "showOnDesktop") != nil { showOnDesktop = d.bool(forKey: "showOnDesktop") }
    }

    private func saveSettings() {
        let d = UserDefaults.standard
        d.set(honey.scale, forKey: "scale")
        d.set(corner.rawValue, forKey: "corner")
        d.set(layer.rawValue, forKey: "layer")
        d.set(showOnDesktop, forKey: "showOnDesktop")
    }

    // MARK: - Floating companion window

    private func makeWindow() {
        hostingView = NSHostingView(
            rootView: AnyView(ContentView().environmentObject(honey))
        )

        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.contentView = hostingView
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.isMovableByWindowBackground = true   // drag Honey anywhere
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        win.tabbingMode = .disallowed
        self.window = win

        applyLayer()
        layoutWindow()
        if showOnDesktop { win.orderFrontRegardless() }
    }

    /// Sizes the window to its content and re-pins it to the active corner.
    private func layoutWindow() {
        var frame = window.frame
        frame.size = hostingView.fittingSize
        window.setFrame(frame, display: true)
        pin(to: corner)
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
        case .onTop:
            window.level = .floating
        case .behind:
            // Just below normal app windows: covered while you work, visible on the desktop.
            window.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)
        }
    }

    // MARK: - Animated menu-bar icon

    private func updateMenuBarIcon() {
        guard let button = statusItem?.button else { return }
        button.image = Self.renderIcon(pixels: honey.currentPixels, bounds: honey.sheet.bounds)
    }

    /// Draws the current frame into a menu-bar NSImage, cropped to the content's
    /// bounding box so it's vertically centered (not biased high by empty rows).
    private static func renderIcon(pixels: [Pixel], bounds: PixelBounds) -> NSImage {
        let contentHeight: CGFloat = 20   // points of drawn content; ~fills the menu bar
        let s = contentHeight / CGFloat(bounds.height)
        let size = NSSize(width: s * CGFloat(bounds.width), height: contentHeight)

        let image = NSImage(size: size)
        image.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.interpolationQuality = .none
            for p in pixels {
                ctx.setFillColor(p.cg)
                // Offset into the crop box; flip y (AppKit origin is bottom-left).
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
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu(menu)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu(menu)
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let header = NSMenuItem(title: "honey is \(honey.activity.label)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let show = NSMenuItem(title: "Show on Desktop", action: #selector(toggleDesktop), keyEquivalent: "")
        show.target = self
        show.state = showOnDesktop ? .on : .off
        menu.addItem(show)

        menu.addItem(submenu("Size", items: sizes.map { size in
            item(size.name, selector: #selector(setSize(_:)), represented: size.scale,
                 checked: honey.scale == size.scale)
        }))

        menu.addItem(submenu("Pin to Corner", items: Corner.allCases.map { c in
            item(c.rawValue, selector: #selector(setCorner(_:)), represented: c.rawValue,
                 checked: corner == c)
        }))

        menu.addItem(submenu("Layer", items: Layer.allCases.map { l in
            item(l.rawValue, selector: #selector(setLayer(_:)), represented: l.rawValue,
                 checked: layer == l)
        }))

        menu.addItem(submenu("Activity", items: honey.sheet.activities.map { a in
            item(a.label, selector: #selector(selectActivity(_:)), represented: a.id,
                 checked: a.id == honey.activity.id)
        }))

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Honey", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
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

    @objc private func selectActivity(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        honey.select(id: id)
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
