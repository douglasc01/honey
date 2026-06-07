import Foundation

/// Procedural 8-bit pixel engine — a Swift port of the prototype's `engine.js`.
/// `honey()` / `bagel()` build a 32×32 grid of palette keys on the fly so the
/// minigame can pose the characters (wide eyes, dangling feet, arms apart, …)
/// in ways the pre-baked JSON frames can't. Colors are resolved later, at draw
/// time, against the palette already loaded from honey-and-bagel.json.

let ENGINE_GRID = 32

/// JS `Math.round` rounds half toward +∞ (-0.5 → 0); Swift's `.rounded()` rounds
/// half away from zero (-0.5 → -1). The pose math relies on the JS behavior, so
/// every `Math.round` in the prototype maps to this.
@inline(__always) func jsRound(_ x: Double) -> Int { Int(floor(x + 0.5)) }

/// A grid of palette keys (row-major). `nil` is transparent (the JS `0`/`""`).
struct PixelGrid {
    let width: Int
    let height: Int
    var cells: [String?]

    init(_ width: Int, _ height: Int) {
        self.width = width
        self.height = height
        self.cells = Array(repeating: nil, count: width * height)
    }

    @inline(__always) func get(_ x: Int, _ y: Int) -> String? {
        if x < 0 || x >= width || y < 0 || y >= height { return nil }
        return cells[y * width + x]
    }
    /// True where a cell is drawn — mirrors JS truthiness (`if (g[r][c])`).
    @inline(__always) func filled(_ x: Int, _ y: Int) -> Bool { get(x, y) != nil }

    /// JS `put(g,x,y,key)` — bounds-checked; passing `nil` clears the cell.
    @inline(__always) mutating func put(_ x: Int, _ y: Int, _ key: String?) {
        if x < 0 || x >= width || y < 0 || y >= height { return }
        cells[y * width + x] = key
    }
    @inline(__always) mutating func clear(_ x: Int, _ y: Int) { put(x, y, nil) }

    mutating func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ key: String) {
        for j in 0..<h { for i in 0..<w { put(x + i, y + j, key) } }
    }

    /// Blit another grid onto this one at (ox,oy); transparent cells skipped.
    mutating func blit(_ src: PixelGrid, _ ox: Int, _ oy: Int) {
        for r in 0..<src.height {
            for c in 0..<src.width {
                if let k = src.get(c, r) { put(ox + c, oy + r, k) }
            }
        }
    }

    /// Reverse each row (JS `g.map(row => row.reverse())`) — bagel's `flip`.
    func flipped() -> PixelGrid {
        var out = PixelGrid(width, height)
        for r in 0..<height {
            for c in 0..<width {
                out.cells[r * width + (width - 1 - c)] = cells[r * width + c]
            }
        }
        return out
    }
}

/// Mirrors the JS `opts` object. String-typed to keep the port literal — the
/// prototype string-compares these everywhere.
struct Opts {
    var bob: Int = 0
    var eyes: String = "open"     // open|closed|happy|half|wide|wink
    var mouth: String = "smile"   // smile|grin|open|flat|o
    var cheeks: Bool = true
    var lean: Int = 0
    var feet: String = "sit"      // sit|apart|tuck|dangle|waveL|kickR
    var look: Int = 0
    var glint: Bool = true
    var flip: Bool = false
}

enum Engine {

    // MARK: - Honey (heart plush)

    /// Classic implicit heart, tuned to a chubby plush shape.
    private static func heartInside(_ c: Double, _ r: Double, _ cx: Double, _ cy: Double, _ s: Double) -> Bool {
        let nx = (c + 0.5 - cx) / (s * 1.06)
        let ny = (cy - (r + 0.5)) / s + 0.34
        let a = nx * nx + ny * ny - 1
        return a * a * a - nx * nx * ny * ny * ny < 0
    }

    static func honey(_ o: Opts = Opts()) -> PixelGrid {
        var g = PixelGrid(ENGINE_GRID, ENGINE_GRID)
        let cx = 16, cyBase = 12.4, s = 9.9
        let bob = o.bob

        // 1) fill body
        for r in 0..<ENGINE_GRID {
            for c in 0..<ENGINE_GRID {
                var cc = Double(c)
                if o.lean != 0 {
                    let t = Double(max(0, 14 - r)) / 14
                    cc = Double(c) - Double(o.lean) * t * 2.2
                }
                let depth = Double(max(0, (r - bob) - 14)) / 12
                let pinch = 1 + depth * 0.32
                cc = Double(cx) + (cc - Double(cx)) * pinch
                if heartInside(cc, Double(r - bob), Double(cx), cyBase, s) {
                    g.put(c, r, "CR")
                }
            }
        }

        // 1b) soften the pointy bottom into a rounded plush base
        softenBottom(&g)

        // 2) shading — highlight upper-left lobe, shadow lower-right + bottom
        for r in 0..<ENGINE_GRID {
            for c in 0..<ENGINE_GRID {
                if g.get(c, r) != "CR" { continue }
                let dx = c - cx
                let dy = Double(r) - (cyBase + Double(bob))
                if dx < -2 && dy < 1 && (Double(dx) + dy) < -6 { g.put(c, r, "HI") }
                else if dx > 3 && dy > -1 { g.put(c, r, "SH") }
                if dy > 8 && dx > 2 { g.put(c, r, "S2") }
            }
        }

        // 3) outline — any body pixel touching transparent
        let body = g
        for r in 0..<ENGINE_GRID {
            for c in 0..<ENGINE_GRID {
                if !body.filled(c, r) { continue }
                let edge = !body.filled(c, r - 1) || !body.filled(c, r + 1)
                        || !body.filled(c - 1, r) || !body.filled(c + 1, r)
                if edge { g.put(c, r, "OL") }
            }
        }

        let fy = 13 + bob

        // 4) legs + feet (silver), anchored to the rounded base
        var maxR = 0
        for r in 0..<ENGINE_GRID { for c in 0..<ENGINE_GRID where g.filled(c, r) { if r > maxR { maxR = r } } }
        var lo = ENGINE_GRID, hi = 0
        let rr = max(0, maxR - 2)
        for c in 0..<ENGINE_GRID where g.filled(c, rr) { if c < lo { lo = c }; if c > hi { hi = c } }
        let ax = lo <= hi ? jsRound(Double(lo + hi) / 2) : 16
        drawLegs(&g, o.feet, ax, maxR)

        // 5) face
        drawEyes(&g, o.eyes, o.look, o.glint, bob)
        drawMouth(&g, o.mouth, bob)
        if o.cheeks {
            g.put(10, fy + 2, "BL"); g.put(11, fy + 2, "BL")
            g.put(22, fy + 2, "BL"); g.put(21, fy + 2, "BL")
        }
        return g
    }

    private static func rowSpan(_ g: PixelGrid, _ r: Int) -> (w: Int, l: Int, rt: Int) {
        var l = -1, rt = -1
        for c in 0..<ENGINE_GRID where g.filled(c, r) { if l < 0 { l = c }; rt = c }
        return l < 0 ? (0, -1, -1) : (rt - l + 1, l, rt)
    }

    /// Chop the heart's narrow spike and round the base corners.
    private static func softenBottom(_ g: inout PixelGrid) {
        var maxR = 0
        for r in 0..<ENGINE_GRID where rowSpan(g, r).w > 0 { maxR = r }
        var r = maxR
        while r > 1, rowSpan(g, r).w > 0, rowSpan(g, r).w < 6 {
            for c in 0..<ENGINE_GRID { g.clear(c, r) }
            r -= 1
        }
        let (bw, bl, br) = rowSpan(g, r)
        if bw >= 3 { g.clear(bl, r); g.clear(br, r) }
        // row above is left as-is (matches the prototype)
    }

    /// A soft silver foot (~5 wide). fx,fy = top-left of the bean.
    private static func footBean(_ g: inout PixelGrid, _ fx: Int, _ fy: Int) {
        for i in 1..<4 { g.put(fx + i, fy, "FH") }
        for i in 0..<5 { g.put(fx + i, fy + 1, "FT") }
        for i in 0..<5 { g.put(fx + i, fy + 2, "FS") }
        for i in 0..<5 { g.put(fx + i, fy + 3, "OL") }
        for i in 1..<4 { g.put(fx + i, fy - 1, "OL") }
        g.put(fx - 1, fy + 1, "OL"); g.put(fx - 1, fy + 2, "OL")
        g.put(fx + 5, fy + 1, "OL"); g.put(fx + 5, fy + 2, "OL")
    }

    private static func legStub(_ g: inout PixelGrid, _ x: Int, _ y: Int, _ h: Int) {
        for j in 0..<h { g.put(x, y + j, "FT"); g.put(x + 1, y + j, "FT") }
        g.put(x - 1, y, "OL"); g.put(x + 2, y, "OL")
    }

    private static func drawLegs(_ g: inout PixelGrid, _ mode: String, _ ax: Int, _ ay: Int) {
        let y = ay
        switch mode {
        case "apart": footBean(&g, ax - 9, y - 1); footBean(&g, ax + 4, y - 1)
        case "tuck":  footBean(&g, ax - 5, y);     footBean(&g, ax, y)
        case "dangle":
            legStub(&g, ax - 5, y - 2, 3); legStub(&g, ax + 3, y - 2, 3)
            footBean(&g, ax - 7, y + 1); footBean(&g, ax + 2, y + 1)
        case "waveL":
            footBean(&g, ax - 6, y - 1)
            g.put(ax + 4, y - 2, "FT"); g.put(ax + 5, y - 3, "FT")
            g.put(ax + 6, y - 4, "FT"); g.put(ax + 6, y - 5, "FT")
            footBean(&g, ax + 5, y - 8)
        case "kickR":
            footBean(&g, ax - 6, y - 1)
            g.put(ax + 4, y - 2, "FT"); g.put(ax + 5, y - 3, "FT"); g.put(ax + 6, y - 4, "FT")
            footBean(&g, ax + 5, y - 6)
        default:
            footBean(&g, ax - 5, y - 1); footBean(&g, ax + 1, y - 1)  // sit
        }
    }

    private static func drawEyes(_ g: inout PixelGrid, _ mode: String, _ look: Int, _ glint: Bool, _ bob: Int) {
        let y = 13 + bob
        let lx = 12, rx = 18
        let dx = look
        switch mode {
        case "closed":
            for i in 0..<3 { g.put(lx + i, y + 1, "EY"); g.put(rx + i, y + 1, "EY") }
        case "happy":
            g.put(lx, y + 1, "EY"); g.put(lx + 1, y, "EY"); g.put(lx + 2, y + 1, "EY")
            g.put(rx, y + 1, "EY"); g.put(rx + 1, y, "EY"); g.put(rx + 2, y + 1, "EY")
        case "wink":
            g.put(lx, y + 1, "EY"); g.put(lx + 1, y, "EY"); g.put(lx + 2, y + 1, "EY")
            eyeDot(&g, rx, y, dx, glint)
        default:
            let h = mode == "half" ? 1 : 2
            let w = 2
            eyeDot(&g, lx, y, dx, glint, h, w)
            eyeDot(&g, rx, y, dx, glint, h, w)
        }
    }

    private static func eyeDot(_ g: inout PixelGrid, _ x: Int, _ y: Int, _ dx: Int, _ glint: Bool, _ h: Int = 2, _ w: Int = 2) {
        g.rect(x, y, w, h, "EY")
        if dx != 0 { g.rect(x + dx, y, w, h, "EY") }
        if glint && h > 1 { g.put(x + (dx > 0 ? 1 : 0), y, "EW") }
    }

    private static func drawMouth(_ g: inout PixelGrid, _ mode: String, _ bob: Int) {
        let y = 17 + bob, cx = 16
        switch mode {
        case "o":
            g.put(cx - 1, y, "EY"); g.put(cx, y, "EY")
            g.put(cx - 1, y + 1, "EY"); g.put(cx, y + 1, "EY")
        case "open":
            g.rect(cx - 2, y, 5, 2, "EY")
            g.put(cx - 1, y + 1, "pink"); g.put(cx, y + 1, "pink")
        case "flat":
            for i in -2...2 { g.put(cx + i, y, "EY") }
        default: // smile / grin arc
            let span = 3
            for i in -span...span {
                let yy = y - jsRound(Double(i * i) / (Double(span) * 1.7))
                g.put(cx + i, yy, "EY")
            }
            if mode == "grin" {
                g.put(cx - 1, y - 1, "pink"); g.put(cx, y - 1, "pink"); g.put(cx + 1, y - 1, "pink")
                g.put(cx - 1, y, "EY"); g.put(cx, y, "EY"); g.put(cx + 1, y, "EY")
            }
        }
    }

    // MARK: - Bagel (croissant)

    static func bagel(_ o: Opts = Opts()) -> PixelGrid {
        var g = PixelGrid(ENGINE_GRID, ENGINE_GRID)
        let bob = o.bob
        let cx = 16, cy = 14 + bob

        // 1) crescent body
        for c in 1...31 {
            let t = Double(c - cx) / 15.5
            if abs(t) > 1.02 { continue }
            let mid = cy + 1 - jsRound((1 - t * t) * 1.4) + jsRound(t * t * 3)
            let half = 4.4 * (max(0, 1 - t * t * 0.9)).squareRoot() + 1.7
            let top = jsRound(Double(mid) - half)
            let edge = max(0, abs(t) - 0.58) / 0.46
            let flatBot = cy + 5 - jsRound(edge * edge * 4.2)
            let bot = min(jsRound(Double(mid) + half), flatBot)
            if top <= bot { for r in top...bot { g.put(c, r, "BC") } }
        }

        // 2) shading + segment ridges
        for r in 0..<ENGINE_GRID {
            for c in 0..<ENGINE_GRID {
                if g.get(c, r) != "BC" { continue }
                var tp = r; while tp > 0 && g.get(c, tp - 1) == "BC" { tp -= 1 }
                var bt = r; while bt < ENGINE_GRID - 1 && g.get(c, bt + 1) == "BC" { bt += 1 }
                if r <= tp + 1 { g.put(c, r, "BH") }
                else if r >= bt - 1 { g.put(c, r, "BS") }
            }
        }
        for sx in [9, 14, 19, 23] {
            for r in 0..<ENGINE_GRID {
                let k = g.get(sx, r)
                if k == "BC" || k == "BH" || k == "BS" {
                    if g.filled(sx, r - 1) && g.filled(sx, r + 1) { g.put(sx, r, "B2") }
                }
            }
        }

        // 3) outline
        let body = g
        for r in 0..<ENGINE_GRID {
            for c in 0..<ENGINE_GRID {
                if !body.filled(c, r) { continue }
                if !body.filled(c, r - 1) || !body.filled(c, r + 1)
                    || !body.filled(c - 1, r) || !body.filled(c + 1, r) {
                    g.put(c, r, "BO")
                }
            }
        }

        // 4) legs (brown), poke out the bottom-middle
        var baseR = 0
        for r in 0..<ENGINE_GRID { for c in 12...20 where g.filled(c, r) { baseR = max(baseR, r) } }
        bagelLegs(&g, o.feet, cx, baseR)

        // 5) face
        let fcx = 16, fy = cy - 1
        bagelEyes(&g, o.eyes, o.look, fcx, fy)
        bagelMouth(&g, o.mouth, fcx, fy + 4)
        if o.cheeks {
            g.put(fcx - 5, fy + 3, "pink"); g.put(fcx - 4, fy + 3, "pink")
            g.put(fcx + 4, fy + 3, "pink"); g.put(fcx + 5, fy + 3, "pink")
        }

        return o.flip ? g.flipped() : g
    }

    private static func bagelFoot(_ g: inout PixelGrid, _ fx: Int, _ fy: Int) {
        for i in 1..<3 { g.put(fx + i, fy, "BGH") }
        for i in 0..<4 { g.put(fx + i, fy + 1, "BG") }
        for i in 0..<4 { g.put(fx + i, fy + 2, "BGS") }
        for i in 0..<4 { g.put(fx + i, fy + 3, "BO") }
        for i in 1..<3 { g.put(fx + i, fy - 1, "BO") }
        g.put(fx - 1, fy + 1, "BO"); g.put(fx - 1, fy + 2, "BO")
        g.put(fx + 4, fy + 1, "BO"); g.put(fx + 4, fy + 2, "BO")
    }

    private static func bagelLegStub(_ g: inout PixelGrid, _ x: Int, _ y: Int, _ h: Int) {
        for j in 0..<h { g.put(x, y + j, "BG"); g.put(x + 1, y + j, "BG") }
        g.put(x - 1, y, "BO"); g.put(x + 2, y, "BO")
    }

    private static func bagelLegs(_ g: inout PixelGrid, _ mode: String, _ ax: Int, _ ay: Int) {
        let y = ay
        switch mode {
        case "apart": bagelFoot(&g, ax - 8, y); bagelFoot(&g, ax + 4, y)
        case "tuck":  bagelFoot(&g, ax - 4, y); bagelFoot(&g, ax + 1, y)
        case "dangle":
            bagelLegStub(&g, ax - 4, y - 1, 3); bagelLegStub(&g, ax + 3, y - 1, 3)
            bagelFoot(&g, ax - 5, y + 2); bagelFoot(&g, ax + 2, y + 2)
        case "kickR":
            bagelFoot(&g, ax - 5, y)
            g.put(ax + 3, y - 1, "BG"); g.put(ax + 4, y - 2, "BG"); g.put(ax + 5, y - 3, "BG")
            bagelFoot(&g, ax + 4, y - 5)
        case "waveL":
            bagelFoot(&g, ax - 5, y)
            g.put(ax + 3, y - 1, "BG"); g.put(ax + 4, y - 2, "BG")
            g.put(ax + 5, y - 3, "BG"); g.put(ax + 5, y - 4, "BG")
            bagelFoot(&g, ax + 4, y - 7)
        default:
            bagelFoot(&g, ax - 5, y); bagelFoot(&g, ax + 1, y)  // sit
        }
    }

    private static func bagelEyes(_ g: inout PixelGrid, _ mode: String, _ look: Int, _ cx: Int, _ y: Int) {
        let lx = cx - 3, rx = cx + 2, dx = look
        switch mode {
        case "closed":
            for i in 0..<3 { g.put(lx + i, y, "BO"); g.put(rx + i, y, "BO") }
        case "happy":
            g.put(lx, y, "BO"); g.put(lx + 1, y - 1, "BO"); g.put(lx + 2, y, "BO")
            g.put(rx, y, "BO"); g.put(rx + 1, y - 1, "BO"); g.put(rx + 2, y, "BO")
        case "wink":
            g.put(lx, y, "BO"); g.put(lx + 1, y - 1, "BO"); g.put(lx + 2, y, "BO")
            bagelEyeDot(&g, rx, y, dx)
        default:
            let h = mode == "half" ? 1 : 2
            bagelEyeDot(&g, lx, y, dx, h)
            bagelEyeDot(&g, rx, y, dx, h)
        }
    }

    private static func bagelEyeDot(_ g: inout PixelGrid, _ x: Int, _ y: Int, _ dx: Int, _ h: Int = 2) {
        g.rect(x + dx, y, 2, h, "EY")
        if h > 1 { g.put(x + dx, y, "EW") }
    }

    private static func bagelMouth(_ g: inout PixelGrid, _ mode: String, _ cx: Int, _ y: Int) {
        switch mode {
        case "o":
            g.put(cx - 1, y, "EY"); g.put(cx, y, "EY")
            g.put(cx - 1, y + 1, "EY"); g.put(cx, y + 1, "EY")
        case "open":
            g.rect(cx - 2, y, 5, 2, "EY")
            g.put(cx - 1, y + 1, "pink"); g.put(cx, y + 1, "pink")
        case "flat":
            for i in -2...2 { g.put(cx + i, y, "EY") }
        default:
            let span = 3
            for i in -span...span {
                let yy = y - jsRound(Double(i * i) / (Double(span) * 1.7))
                g.put(cx + i, yy, "EY")
            }
            if mode == "grin" {
                g.put(cx - 1, y - 1, "pink"); g.put(cx, y - 1, "pink"); g.put(cx + 1, y - 1, "pink")
            }
        }
    }
}
