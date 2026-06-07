import Foundation

/// Treat props + character pose builders for the break minigame.
/// Props are a port of the five collectibles used by the game (`sprites.js`);
/// the pose builders are a port of `minigame.js`.

// MARK: - Treat / FX props (mutate the grid, like the JS prop helpers)

func pMug(_ g: inout PixelGrid, _ x: Int, _ y: Int) {
    g.rect(x, y, 5, 5, "blue")
    for i in 0..<5 { g.put(x + i, y + 4, "OL") }
    for j in 0..<5 { g.put(x, y + j, "OL"); g.put(x + 4, y + j, "OL") }
    g.put(x, y, "OL"); g.put(x + 4, y, "OL")
    g.rect(x + 1, y + 1, 3, 1, "brownD")     // coffee surface
    g.rect(x + 1, y + 2, 3, 2, "blueD")
    g.put(x + 5, y + 1, "OL"); g.put(x + 6, y + 2, "OL"); g.put(x + 5, y + 3, "OL")  // handle
}

func pCookie(_ g: inout PixelGrid, _ x: Int, _ y: Int, _ bite: Bool) {
    g.rect(x, y, 5, 5, "brown")
    g.clear(x, y); g.clear(x + 4, y); g.clear(x, y + 4); g.clear(x + 4, y + 4)  // round corners
    g.put(x + 2, y, "OL")
    g.put(x + 1, y + 1, "brownD"); g.put(x + 3, y + 2, "brownD"); g.put(x + 2, y + 3, "brownD")  // chips
    if bite { g.clear(x + 3, y); g.clear(x + 4, y + 1); g.clear(x + 3, y + 1) }
}

func pNote(_ g: inout PixelGrid, _ x: Int, _ y: Int, _ kind: Int) {
    g.put(x, y + 2, "lavD"); g.put(x + 1, y + 2, "lavD"); g.put(x, y + 3, "lavD"); g.put(x + 1, y + 3, "lavD")
    g.put(x + 2, y, "lavD"); g.put(x + 2, y + 1, "lavD"); g.put(x + 2, y + 2, "lavD")
    if kind != 0 { g.put(x + 3, y, "lavD") }
}

func pHeart(_ g: inout PixelGrid, _ x: Int, _ y: Int, _ c: String = "pink") {
    g.put(x, y, c); g.put(x + 2, y, c)
    g.put(x - 1, y + 1, c); g.put(x, y + 1, c); g.put(x + 1, y + 1, c); g.put(x + 2, y + 1, c); g.put(x + 3, y + 1, c)
    g.put(x, y + 2, c); g.put(x + 1, y + 2, c); g.put(x + 2, y + 2, c)
    g.put(x + 1, y + 3, c)
}

func pSparkle(_ g: inout PixelGrid, _ x: Int, _ y: Int) {
    g.put(x, y, "gold"); g.put(x - 1, y, "goldD"); g.put(x + 1, y, "goldD")
    g.put(x, y - 1, "goldD"); g.put(x, y + 1, "goldD")
}

/// Gold "!" excitement mark.
func bang(_ g: inout PixelGrid, _ x: Int, _ y: Int) {
    for j in 0..<3 { g.put(x, y + j, "gold") }
    g.put(x, y + 4, "gold")
}

func gridProp(_ w: Int, _ h: Int, _ build: (inout PixelGrid) -> Void) -> PixelGrid {
    var g = PixelGrid(w, h)
    build(&g)
    return g
}

// MARK: - Character pose builders (port of minigame.js)

struct PerkFrames {
    let frames: [PixelGrid]
    let w: Int
    let h: Int
    let fps: Double
}

enum Pose {

    static func solo(_ k: String, _ o: Opts) -> PixelGrid {
        k == "bagel" ? Engine.bagel(o) : Engine.honey(o)
    }

    /// Honey perched on Bagel — a stacked "together" sprite (32×44).
    /// Bagel sits at the base; Honey rests on the croissant with feet dangling.
    /// Callers override eyes/mouth/bob per game state.
    static func stackPair(hEyes: String = "happy", hMouth: String = "open", hBob: Int = 0,
                          bEyes: String = "happy", bMouth: String = "smile", bBob: Int = 0) -> PixelGrid {
        var g = PixelGrid(32, 44)
        g.blit(Engine.bagel(Opts(bob: bBob, eyes: bEyes, mouth: bMouth, feet: "apart")), 0, 13)
        g.blit(Engine.honey(Opts(bob: hBob, eyes: hEyes, mouth: hMouth, feet: "dangle")), 0, -2)
        return g
    }

    /// A catcher: arms-open, happy, mouth ready.
    static func catcherFrames(_ k: String) -> [PixelGrid] {
        if k == "both" {
            return [stackPair(hBob: 0), stackPair(hBob: -2)]  // Honey bounces on Bagel
        }
        return [solo(k, Opts(bob: 0, eyes: "happy", mouth: "open", feet: "apart")),
                solo(k, Opts(bob: -1, eyes: "happy", mouth: "open", feet: "apart"))]
    }

    /// A calm watcher (tap mode) — idle smile.
    static func watchFrames(_ k: String) -> [PixelGrid] {
        if k == "both" {
            return [stackPair(hEyes: "open", hMouth: "smile", hBob: 0, bEyes: "open", bMouth: "smile"),
                    stackPair(hEyes: "open", hMouth: "smile", hBob: -1, bEyes: "open", bMouth: "smile")]
        }
        return [solo(k, Opts(bob: 0, eyes: "open", mouth: "smile", feet: "sit")),
                solo(k, Opts(bob: -1, eyes: "open", mouth: "smile", feet: "sit"))]
    }

    /// A happy reaction pop (eyes wide, grin, sparkles).
    static func popFrames(_ k: String) -> [PixelGrid] {
        if k == "both" {
            var a = stackPair(hEyes: "happy", hMouth: "grin", hBob: -2, bEyes: "happy", bMouth: "grin")
            pSparkle(&a, 4, 5); pSparkle(&a, 28, 4); bang(&a, 26, 0)
            var b = stackPair(hEyes: "happy", hMouth: "grin", hBob: 0, bEyes: "happy", bMouth: "grin")
            pSparkle(&b, 6, 9); pSparkle(&b, 27, 11); bang(&b, 26, 1)
            return [a, b]
        }
        var a = solo(k, Opts(bob: -2, eyes: "happy", mouth: "grin", feet: "apart")); pSparkle(&a, 6, 6); bang(&a, 24, 1)
        var b = solo(k, Opts(bob: 0, eyes: "happy", mouth: "grin", feet: "apart")); pSparkle(&b, 25, 8); bang(&b, 24, 2)
        return [a, b]
    }

    /// The "perking up" arm animation — a little hop + sparkles building.
    static func perkFrames(_ k: String) -> PerkFrames {
        if k == "both" {
            var a = stackPair(hEyes: "happy", hMouth: "grin", hBob: 0, bEyes: "happy", bMouth: "grin")
            bang(&a, 26, 0); pSparkle(&a, 5, 5)
            var b = stackPair(hEyes: "wide", hMouth: "o", hBob: -2, bEyes: "wide", bMouth: "o")
            bang(&b, 26, 0); pSparkle(&b, 28, 7); pSparkle(&b, 4, 3)
            return PerkFrames(frames: [a, b], w: 32, h: 44, fps: 5)
        }
        var a = solo(k, Opts(bob: 0, eyes: "happy", mouth: "grin", feet: "apart")); bang(&a, 24, 2); pSparkle(&a, 6, 7)
        var b = solo(k, Opts(bob: -2, eyes: "wide", mouth: "o", feet: "apart")); bang(&b, 24, 1); pSparkle(&b, 25, 9)
        return PerkFrames(frames: [a, b], w: ENGINE_GRID, h: ENGINE_GRID, fps: 5)
    }

    /// Reaction: waiting, calm.
    static func readyFrames(_ k: String) -> [PixelGrid] {
        if k == "both" {
            return [stackPair(hEyes: "open", hMouth: "flat", bEyes: "open", bMouth: "flat")]
        }
        return [solo(k, Opts(eyes: "open", mouth: "flat", feet: "sit"))]
    }
}
