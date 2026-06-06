import SwiftUI
import Combine

/// Drives Honey & Bagel: advances animation frames, switches scenes within a cast
/// every 30–90 s, and rotates the cast (honey → both → bagel → both) every few
/// minutes — restricted to the casts the user has enabled in the rotation.
/// All mutation happens on the main thread (Timer on RunLoop.main, AppKit callbacks).
final class Honey: ObservableObject {
    let sheet: SpriteSheet

    @Published private(set) var castIndex: Int
    @Published private(set) var sceneIndex: Int = 0
    @Published private(set) var frameIndex: Int = 0
    @Published private(set) var greeting: String? = nil
    @Published var scale: Int = 3

    /// Casts allowed in the auto rotation. Toggled from the menu.
    var enabledCasts: Set<String>
    /// When set, auto cast-rotation is paused and only this cast is shown.
    var forcedCastID: String?

    var onFrameChange: (() -> Void)?    // same scene, next frame → redraw icon only
    var onLayoutChange: (() -> Void)?   // scene/cast/greeting changed → resize + redraw

    private var frameAccumulator: Double = 0
    private var sceneCountdown: Double = 0
    private var castCountdown: Double = 0
    private var greetingCountdown: Double = 0
    private var ticker: Timer?
    private var lastTick = Date()

    var cast: Cast { sheet.casts[castIndex] }
    var scene: Scene { cast.scenes[min(sceneIndex, cast.scenes.count - 1)] }

    var currentPixels: [Pixel] {
        let frames = scene.frames
        return frames[min(frameIndex, frames.count - 1)]
    }

    /// Greeting if one is showing, otherwise the current scene's label.
    var displayLabel: String { greeting ?? scene.label }

    init(sheet: SpriteSheet) {
        self.sheet = sheet
        self.enabledCasts = Set(sheet.casts.map { $0.id })
        self.forcedCastID = nil
        self.castIndex = sheet.index(of: "honey") ?? 0
        self.sceneIndex = Self.weightedSceneIndex(in: sheet.casts[castIndex])
        self.castCountdown = Self.randomCastInterval()
        self.sceneCountdown = Self.randomSceneInterval()
    }

    func start() {
        lastTick = Date()
        showGreeting(forEnteringCast: cast)
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        let now = Date()
        let dt = min(0.1, now.timeIntervalSince(lastTick))
        lastTick = now

        var frameChanged = false
        var layoutChanged = false

        let frames = scene.frames
        if frames.count > 1 {
            frameAccumulator += dt
            let secondsPerFrame = 1.0 / scene.fps
            if frameAccumulator >= secondsPerFrame {
                frameAccumulator -= secondsPerFrame
                frameIndex = (frameIndex + 1) % frames.count
                frameChanged = true
            }
        }

        if greeting != nil {
            greetingCountdown -= dt
            if greetingCountdown <= 0 { greeting = nil; layoutChanged = true }
        }

        if forcedCastID == nil {
            castCountdown -= dt
            if castCountdown <= 0 {
                rotateCast()
                if frameChanged { onFrameChange?() }   // flush pending frame redraw
                onLayoutChange?()
                return
            }
        }

        sceneCountdown -= dt
        if sceneCountdown <= 0 {
            switchScene(to: Self.weightedSceneIndex(in: cast))
            layoutChanged = true
        }

        if layoutChanged { onLayoutChange?() }
        else if frameChanged { onFrameChange?() }
    }

    // MARK: - Manual controls (menu)

    /// Force a specific cast (pauses auto-rotation), or pass nil to resume Auto.
    func setForcedCast(_ id: String?) {
        forcedCastID = id
        if let id, let idx = sheet.index(of: id) {
            enterCast(idx)
        } else {
            castCountdown = Self.randomCastInterval()
        }
        onLayoutChange?()
    }

    func toggleCastInRotation(_ id: String) {
        if enabledCasts.contains(id) {
            guard enabledCasts.count > 1 else { return }   // never disable the last one
            enabledCasts.remove(id)
        } else {
            enabledCasts.insert(id)
        }
    }

    func selectScene(_ id: String) {
        guard let idx = cast.scenes.firstIndex(where: { $0.id == id }) else { return }
        switchScene(to: idx)
        onLayoutChange?()
    }

    // MARK: - Rotation internals

    private func rotateCast() {
        let list = rotationOrder()
        let current = list.firstIndex(of: cast.id) ?? -1
        let nextID = list[(current + 1) % list.count]
        enterCast(sheet.index(of: nextID) ?? castIndex)
    }

    /// castOrder filtered to enabled casts, with consecutive (and wrap-around) duplicates collapsed.
    private func rotationOrder() -> [String] {
        var list = sheet.castOrder.filter { enabledCasts.contains($0) }
        if list.isEmpty { list = sheet.casts.map { $0.id }.filter { enabledCasts.contains($0) } }
        var out: [String] = []
        for c in list where out.last != c { out.append(c) }
        if out.count > 1, out.first == out.last { out.removeLast() }
        return out.isEmpty ? [cast.id] : out
    }

    private func enterCast(_ index: Int) {
        castIndex = index
        switchScene(to: Self.weightedSceneIndex(in: cast))
        castCountdown = Self.randomCastInterval()
        showGreeting(forEnteringCast: cast)
    }

    private func switchScene(to index: Int) {
        sceneIndex = index
        frameIndex = 0
        frameAccumulator = 0
        sceneCountdown = Self.randomSceneInterval()
    }

    private func showGreeting(forEnteringCast cast: Cast) {
        greeting = cast.solo ? "\(cast.name) is here!" : "someone's visiting!"
        greetingCountdown = 3.5
    }

    // MARK: - Scheduling

    private static func randomSceneInterval() -> Double { Double.random(in: 30...90) }
    private static func randomCastInterval() -> Double { Double.random(in: 180...360) }

    /// Picks a scene, nudging restful scenes up at night and coffee in the morning.
    private static func weightedSceneIndex(in cast: Cast) -> Int {
        let night = isNight(), morning = isMorning()
        let weights = cast.scenes.map { scene -> Double in
            let id = scene.id
            if id.contains("sleep") || id.contains("nap") || id == "idle" { return night ? 4.0 : 1.0 }
            if id.contains("coffee") { return morning ? 4.0 : 1.0 }
            return night ? 0.5 : 1.0
        }
        let total = weights.reduce(0, +)
        var roll = Double.random(in: 0..<total)
        for (i, w) in weights.enumerated() {
            roll -= w
            if roll < 0 { return i }
        }
        return 0
    }

    private static func isNight() -> Bool {
        let h = Calendar.current.component(.hour, from: Date())
        return h >= 22 || h < 6
    }

    private static func isMorning() -> Bool {
        let h = Calendar.current.component(.hour, from: Date())
        return h >= 6 && h < 11
    }
}
