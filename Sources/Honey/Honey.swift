import SwiftUI
import Combine

/// Drives Honey: advances animation frames at each activity's fps and rotates
/// to a new activity every 3–8 minutes (weighted by time of day).
/// All mutation happens on the main thread (Timer on RunLoop.main, AppKit callbacks).
final class Honey: ObservableObject {
    let sheet: SpriteSheet

    @Published private(set) var activityIndex: Int
    @Published private(set) var frameIndex = 0
    @Published var scale: Int = 3   // pixels-per-cell: ×3 = 96pt, ×4 = 128, ×5 = 160

    /// Called whenever the visible frame changes, so the menu-bar icon can redraw.
    var onVisualChange: (() -> Void)?

    private var frameAccumulator: Double = 0
    private var timeUntilSwitch: Double = 0
    private var ticker: Timer?
    private var lastTick = Date()

    var activity: Activity { sheet.activities[activityIndex] }

    var currentPixels: [Pixel] {
        let frames = activity.frames
        return frames[min(frameIndex, frames.count - 1)]
    }

    init(sheet: SpriteSheet) {
        self.sheet = sheet
        self.activityIndex = Self.preferredStartIndex(in: sheet)
        self.timeUntilSwitch = Self.randomInterval()
    }

    func start() {
        lastTick = Date()
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

        var changed = false
        let frames = activity.frames
        if frames.count > 1 {
            frameAccumulator += dt
            let secondsPerFrame = 1.0 / activity.fps
            if frameAccumulator >= secondsPerFrame {
                frameAccumulator -= secondsPerFrame
                frameIndex = (frameIndex + 1) % frames.count
                changed = true
            }
        }

        timeUntilSwitch -= dt
        if timeUntilSwitch <= 0 {
            switchTo(Self.weightedRandomIndex(in: sheet))
            changed = true
        }

        if changed { onVisualChange?() }
    }

    /// Manually choose an activity; keeps auto-rotation alive but grants a full
    /// fresh interval before the next automatic switch.
    func select(id: String) {
        guard let idx = sheet.activities.firstIndex(where: { $0.id == id }) else { return }
        switchTo(idx)
        onVisualChange?()
    }

    private func switchTo(_ index: Int) {
        activityIndex = index
        frameIndex = 0
        frameAccumulator = 0
        timeUntilSwitch = Self.randomInterval()
    }

    // MARK: - Scheduling

    private static func randomInterval() -> Double {
        Double.random(in: 180...480)   // 3–8 minutes
    }

    private static func preferredStartIndex(in sheet: SpriteSheet) -> Int {
        let id = isNight() ? "sleeping" : (isMorning() ? "coffee" : "idle")
        return sheet.activities.firstIndex { $0.id == id } ?? 0
    }

    /// Picks a random activity, nudging idle/sleeping up at night and coffee in
    /// the morning, so Honey's day loosely tracks yours.
    private static func weightedRandomIndex(in sheet: SpriteSheet) -> Int {
        let night = isNight()
        let morning = isMorning()
        let weights = sheet.activities.map { activity -> Double in
            switch activity.id {
            case "sleeping", "idle": return night ? 4.0 : 1.0
            case "coffee":           return morning ? 4.0 : 1.0
            default:                 return night ? 0.4 : 1.0
            }
        }
        let total = weights.reduce(0, +)
        var roll = Double.random(in: 0..<total)
        for (i, w) in weights.enumerated() {
            roll -= w
            if roll < 0 { return i }
        }
        return weights.count - 1
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
