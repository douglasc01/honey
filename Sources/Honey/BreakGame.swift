import Foundation
import Combine

/// The "take a break" minigame — a Swift port of the prototype's `GameStation`
/// (`minigame.js`), extended with: pause-on-leave + 3-2-1 countdown resume, a
/// 0.5× in-game character downscale (so there's more room to move), and a
/// pause-correct reaction timer. Pure game logic in field-cell coordinates;
/// rendering lives in GameView, windowing in BreakGameController.

/// Logical playfield, in cells.
let FW = 80
let FH = 58
private let FLOOR = Double(FH)

/// Characters render at half size in-game (user choice) for more room.
let CHAR_SCALE = 0.5

private func clampD(_ v: Double, _ a: Double, _ b: Double) -> Double { v < a ? a : (v > b ? b : v) }
private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
private func rnd(_ a: Double, _ b: Double) -> Double { Double.random(in: a...b) }

struct TreatDef { let pts: Int; let w: Int; let h: Int; let grid: PixelGrid }
struct Treat { let type: String; var x: Double; var y: Double; let vy: Double }
struct Particle { var x, y, vx, vy, life: Double; let grid: PixelGrid }
struct Pop { let x: Double; var y: Double; var t: Double; let pts: Int }

final class BreakGame: ObservableObject {

    enum Phase { case idle, arm, play, paused, countdown, over }

    // Observed by the views; bumped every logic frame so SwiftUI redraws.
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var renderTick: Int = 0

    // Set by the controller.
    var getChar: () -> String = { "honey" }
    var getMode: () -> String = { "catch" }
    var armMs: Double = 5000
    var renderScale: Int = 6
    var onArmBegin: (() -> Void)?            // meter starts filling in the (still-draggable) widget
    var onGameShown: (() -> Void)?           // meter full → grow the play area + take input
    var onGameHidden: (() -> Void)?          // restore the ambient widget

    // Session state
    private(set) var mode = "catch"
    private(set) var charK = "honey"
    private(set) var score = 0
    private(set) var lives = 3
    private(set) var combo = 1
    private(set) var newBest = false

    private(set) var treats: [Treat] = []
    private(set) var parts: [Particle] = []
    private(set) var pops: [Pop] = []

    private(set) var catcherX = 0.0
    private var catcherTX = 0.0
    private(set) var cw = 16.0      // character footprint (field cells)
    private(set) var ch = 16.0
    private(set) var fi = 0         // character frame index
    private var facc = 0.0
    private(set) var flash = 0.0
    private(set) var happy = 0.0
    private(set) var shake = 0.0
    private var mx: Double?
    private var spawnT = 0.0
    private(set) var elapsed = 0.0

    // arming
    private(set) var armProgress = 0.0
    private(set) var perk = PerkFrames(frames: [], w: 32, h: 32, fps: 5)

    // reaction
    private(set) var rPhase = "ready"
    private var rTimer = 0.0        // ms
    private var goElapsed = 0.0     // accumulated *game* time since "go" (pause-safe)
    private(set) var rLast: Int?

    // countdown
    private(set) var countdownRemaining = 0.0
    var countdownValue: Int { max(1, Int(ceil(countdownRemaining))) }

    // brief "how to play" hint shown at the start of a round
    private(set) var introT = 0.0
    var showIntro: Bool { phase == .play && introT > 0 }
    var instructions: String {
        switch mode {
        case "tap":   return "Click the falling treats!"
        case "react": return "Wait for NOW, then click!"
        default:      return "Move to catch the treats!"
        }
    }

    // Always-visible quit control, as a hit region in field cells (top-right).
    static let stopBox = (x0: Double(FW) - 9, y0: 2.0, x1: Double(FW) - 2, y1: 9.0)
    private func hitStop(_ gx: Double, _ gy: Double) -> Bool {
        gx >= Self.stopBox.x0 && gx <= Self.stopBox.x1 && gy >= Self.stopBox.y0 && gy <= Self.stopBox.y1
    }

    // result card
    private(set) var resultScoreText = ""
    private(set) var resultBestText = ""
    private(set) var resultLabel = ""
    private(set) var resultCelebrate = false

    // cached pose frames for the round
    private var cf: [PixelGrid] = []
    private var popCache: [PixelGrid] = []
    private var readyCache: [PixelGrid] = []

    private var shown = false
    private var ticker: Timer?
    private var lastTick = Date()

    let honey: Honey
    init(honey: Honey) { self.honey = honey }

    // MARK: - Treats (built once)

    static let TREATS: [String: TreatDef] = [
        "cookie": TreatDef(pts: 1, w: 6, h: 6, grid: gridProp(6, 6) { pCookie(&$0, 0, 0, false) }),
        "coffee": TreatDef(pts: 2, w: 8, h: 7, grid: gridProp(8, 7) { pMug(&$0, 0, 1) }),
        "note":   TreatDef(pts: 2, w: 5, h: 5, grid: gridProp(5, 5) { pNote(&$0, 1, 0, 1) }),
        "heart":  TreatDef(pts: 3, w: 5, h: 5, grid: gridProp(5, 5) { pHeart(&$0, 1, 0, "pink") }),
        "star":   TreatDef(pts: 5, w: 5, h: 5, grid: gridProp(5, 5) { pSparkle(&$0, 2, 2) }),
    ]
    private static let BAG = ["cookie", "cookie", "cookie", "cookie", "coffee", "coffee",
                              "note", "note", "heart", "heart", "star"]
    static let heartGrid = gridProp(5, 5) { pHeart(&$0, 1, 0, "pink") }
    static let heartGray = gridProp(5, 5) { pHeart(&$0, 1, 0, "S2") }
    private static func pickTreat() -> String { BAG[Int.random(in: 0..<BAG.count)] }

    // MARK: - Timer

    private func startTicker() {
        guard ticker == nil else { return }
        lastTick = Date()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }
    private func stopTicker() { ticker?.invalidate(); ticker = nil }

    private func tick() {
        let now = Date()
        let dt = min(0.05, now.timeIntervalSince(lastTick))
        lastTick = now
        update(dt)
        renderTick &+= 1
    }

    private func setPhase(_ p: Phase) { phase = p }

    // MARK: - Input from the controller

    func setMouse(_ gx: Double, _ gy: Double) { mx = gx }

    /// pointerenter on the widget/overlay.
    func mouseEntered() {
        switch phase {
        case .idle: beginArm()
        case .paused: countdownRemaining = 3.0; setPhase(.countdown)
        default: break
        }
    }

    /// pointerexit.
    func mouseExited() {
        switch phase {
        case .arm: endSession()                 // cancel — game never launched
        case .play: setPhase(.paused)
        case .countdown: setPhase(.paused)
        case .over: endSession()                // dismiss the result card
        default: break
        }
    }

    /// pointerdown.
    func pointerDown(_ gx: Double, _ gy: Double) {
        if phase != .arm && hitStop(gx, gy) { endSession(); return }  // always-visible quit
        if phase == .over { launch(); return }  // click result → play again
        guard phase == .play else { return }
        if mode == "tap" {
            for i in treats.indices.reversed() {
                let t = treats[i], d = BreakGame.TREATS[t.type]!
                if gx >= t.x - 1 && gx <= t.x + Double(d.w) + 1 && gy >= t.y - 1 && gy <= t.y + Double(d.h) + 1 {
                    score += d.pts * combo
                    combo = min(combo + 1, 9)
                    pops.append(Pop(x: t.x + Double(d.w) / 2, y: t.y + Double(d.h) / 2, t: 0, pts: d.pts * combo))
                    burst(t.x + Double(d.w) / 2, t.y + Double(d.h) / 2, 4)
                    flash = 0.12; happy = 0.4
                    treats.remove(at: i)
                    return
                }
            }
        } else if mode == "react" {
            if rPhase == "ready" { rPhase = "early"; rTimer = 900 }
            else if rPhase == "go" {
                let ms = jsRound(goElapsed * 1000)
                rLast = ms
                newBest = isNewBest("react", Double(ms))
                if newBest { setBest("react", Double(ms)) }
                rPhase = "result"; rTimer = 1500
                burst(Double(FW) / 2, Double(FH) / 2 - 6, newBest ? 14 : 5)
                happy = 0.8
            }
        }
    }

    /// Feature turned off mid-session.
    func abort() { if phase != .idle { endSession() } }

    // MARK: - Phase transitions

    private func beginArm() {
        guard phase == .idle else { return }
        charK = getChar()
        mode = getMode()
        perk = Pose.perkFrames(charK)
        armProgress = 0; armT = 0; fi = 0; facc = 0
        startTicker()
        setPhase(.arm)
        onArmBegin?()
    }
    private var armT = 0.0

    private func launch() {
        charK = getChar()                       // freeze the cast for the round
        mode = getMode()
        switch mode {
        case "tap":   cf = Pose.watchFrames(charK)
        case "react": cf = Pose.readyFrames(charK)
        default:      cf = Pose.catcherFrames(charK)
        }
        popCache = Pose.popFrames(charK)
        readyCache = Pose.readyFrames(charK)
        cw = Double(cf[0].width) * CHAR_SCALE
        ch = Double(cf[0].height) * CHAR_SCALE
        fi = 0; facc = 0
        treats = []; parts = []; pops = []
        score = 0; lives = 3; combo = 1; newBest = false
        spawnT = 0; elapsed = 0
        catcherX = (Double(FW) - cw) / 2; catcherTX = catcherX
        flash = 0; shake = 0; happy = 0; introT = 2.5
        rPhase = "ready"; rTimer = rnd(1200, 3200); goElapsed = 0; rLast = nil
        startTicker()
        setPhase(.play)
        if !shown { shown = true; onGameShown?() }
    }

    private func endGame() {
        guard phase == .play else { return }
        let finalVal: Double? = mode == "react" ? rLast.map(Double.init) : Double(score)
        if let v = finalVal, isNewBest(mode, v) { setBest(mode, v); newBest = true }
        burst(Double(FW) / 2, Double(FH) / 2, newBest ? 16 : 7)
        resultScoreText = fmtScore(mode, finalVal)
        resultBestText = "best · " + fmtScore(mode, getBest(mode))
        resultLabel = newBest ? "★ new best! ★" : modeName(mode)
        resultCelebrate = newBest
        setPhase(.over)
    }

    /// Fully end the session and return to the ambient widget.
    private func endSession() {
        setPhase(.idle)
        stopTicker()
        shown = false
        onGameHidden?()
    }

    // MARK: - Update loop

    private func update(_ dt: Double) {
        if phase == .countdown {
            countdownRemaining -= dt
            if countdownRemaining <= 0 { setPhase(.play) }
            return
        }

        if phase == .arm || phase == .play {
            facc += dt
            let cfps = phase == .arm ? perk.fps : 4
            if facc > 1 / cfps { facc = 0; fi ^= 1 }
        }

        if phase == .play || phase == .over {
            if flash > 0 { flash -= dt }
            if happy > 0 { happy -= dt }
            if shake > 0 { shake -= dt }
            for i in parts.indices {
                parts[i].vy += 60 * dt
                parts[i].x += parts[i].vx * dt
                parts[i].y += parts[i].vy * dt
                parts[i].life -= dt
            }
            parts.removeAll { $0.life <= 0 }
            for i in pops.indices { pops[i].t += dt }
            pops.removeAll { $0.t >= 0.7 }
        }

        if phase == .arm {
            armT += dt * 1000
            armProgress = clampD(armT / armMs, 0, 1)
            if armProgress >= 1 { launch() }
            return
        }

        guard phase == .play else { return }
        elapsed += dt
        if introT > 0 { introT -= dt }
        switch mode {
        case "tap":   updateTap(dt)
        case "react": updateReact(dt)
        default:      updateCatch(dt)
        }
    }

    private func spawn() {
        let type = BreakGame.pickTreat(), d = BreakGame.TREATS[type]!
        let x = rnd(3, Double(FW) - 3 - Double(d.w))
        let sp = mode == "catch"
            ? clampD(17 + Double(score) * 0.5, 17, 46) * rnd(0.9, 1.2)
            : clampD(13 + elapsed * 0.4, 13, 30) * rnd(0.9, 1.15)
        treats.append(Treat(type: type, x: x, y: -Double(d.h), vy: sp))
    }

    private func updateCatch(_ dt: Double) {
        if let mx {
            catcherTX = clampD(mx - cw / 2, 2, Double(FW) - cw - 2)
            catcherX = lerp(catcherX, catcherTX, clampD(dt * 16, 0, 1))
        }
        spawnT -= dt
        let every = clampD(1.25 - Double(score) * 0.02, 0.5, 1.25)
        if spawnT <= 0 { spawn(); spawnT = every }

        let topY = Double(FH) - ch
        let cl = catcherX + 2, cr = catcherX + cw - 2   // pad scaled with the 0.5 sprite
        for i in treats.indices.reversed() {
            let d = BreakGame.TREATS[treats[i].type]!
            treats[i].y += treats[i].vy * dt
            let t = treats[i]
            let cxp = t.x + Double(d.w) / 2
            // catch band, scaled from the prototype's +4 / +18 for the half-size sprite
            if t.y + Double(d.h) >= topY + 2 && t.y <= topY + 9 && cxp >= cl && cxp <= cr {
                score += d.pts; happy = 0.35; flash = 0.1
                pops.append(Pop(x: cxp, y: topY, t: 0, pts: d.pts))
                burst(cxp, topY, 3)
                treats.remove(at: i); continue
            }
            if t.y > FLOOR + 2 {
                treats.remove(at: i); lives -= 1; shake = 0.25
                if lives <= 0 { endGame(); return }
            }
        }
    }

    private func updateTap(_ dt: Double) {
        spawnT -= dt
        let every = clampD(1.0 - elapsed * 0.012, 0.55, 1.0)
        if spawnT <= 0 { spawn(); spawnT = every }
        for i in treats.indices.reversed() {
            treats[i].y += treats[i].vy * dt
            if treats[i].y > FLOOR + 2 {
                treats.remove(at: i); combo = 1; lives -= 1; shake = 0.25
                if lives <= 0 { endGame(); return }
            }
        }
    }

    private func updateReact(_ dt: Double) {
        rTimer -= dt * 1000
        if rPhase == "ready" && rTimer <= 0 { rPhase = "go" }
        else if rPhase == "early" && rTimer <= 0 { rPhase = "ready"; rTimer = rnd(1200, 3200) }
        else if rPhase == "result" && rTimer <= 0 { endGame() }
        if rPhase == "go" { goElapsed += dt }
    }

    private func burst(_ x: Double, _ y: Double, _ n: Int) {
        for _ in 0..<n {
            let a = rnd(0, .pi * 2), sp = rnd(8, 26)
            let which = Double.random(in: 0..<1) < 0.5 ? BreakGame.heartGrid : BreakGame.TREATS["star"]!.grid
            parts.append(Particle(x: x, y: y, vx: cos(a) * sp, vy: sin(a) * sp - 10,
                                  life: rnd(0.5, 1.0), grid: which))
        }
    }

    // MARK: - Character frame for rendering

    /// The pose grid + its top-left field-cell origin for the current state.
    /// Used by GameView for play/paused/countdown/over (arm renders in the widget).
    func renderCharacter() -> (grid: PixelGrid, x: Double, y: Double) {
        let topY = Double(FH) - ch
        switch mode {
        case "tap":
            let fr = happy > 0 ? popCache[fi % 2] : cf[fi % 2]
            return (fr, (Double(FW) - Double(fr.width) * CHAR_SCALE) / 2, Double(FH) - Double(fr.height) * CHAR_SCALE)
        case "react":
            let fr = (rPhase == "go" || rPhase == "result") ? popCache[fi % 2] : readyCache[0]
            return (fr, (Double(FW) - Double(fr.width) * CHAR_SCALE) / 2, Double(FH) - Double(fr.height) * CHAR_SCALE)
        default:
            let fr = cf[happy > 0 ? 0 : fi % 2]
            return (fr, catcherX, topY)
        }
    }

    /// HUD prompt for reaction mode (and "" otherwise).
    var reactionPrompt: String {
        guard mode == "react", phase == .play else { return "" }
        switch rPhase {
        case "ready": return "get ready…"
        case "go": return "NOW — click!"
        case "early": return "too soon!"
        default: return rLast.map { String(format: "%.3fs", Double($0) / 1000) } ?? ""
        }
    }

    // MARK: - Persistence

    private func key(_ mode: String) -> String { "hb_best_" + mode }
    func getBest(_ mode: String) -> Double? { UserDefaults.standard.object(forKey: key(mode)) as? Double }
    private func setBest(_ mode: String, _ v: Double) { UserDefaults.standard.set(v, forKey: key(mode)) }
    private func isNewBest(_ mode: String, _ val: Double) -> Bool {
        guard let b = getBest(mode) else { return true }
        return mode == "react" ? val < b : val > b
    }

    func modeName(_ m: String) -> String {
        switch m { case "tap": return "Quick Tap"; case "react": return "Reaction"; default: return "Snack Catch" }
    }
    func fmtScore(_ mode: String, _ v: Double?) -> String {
        guard let v else { return "—" }
        return mode == "react" ? String(format: "%.3fs", v / 1000) : String(Int(v))
    }
}
