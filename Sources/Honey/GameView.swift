import SwiftUI

/// The full-window session view: an outlined border that hugs the (growing)
/// play area plus the live field. The field is pinned to the window's
/// bottom-center, so while the area grows the sprite stays centered at the
/// bottom; the border fades in as it opens, then stays for the round.
struct SessionRoot: View {
    @ObservedObject var game: BreakGame
    let palette: Palette

    var body: some View {
        ZStack {
            GameView(game: game, palette: palette)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            GameBorder(scale: CGFloat(game.renderScale))
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The play-area outline. Fills the window (so it grows with the window) and
/// fades in once the play area opens.
struct GameBorder: View {
    let scale: CGFloat
    @State private var shown = false
    var body: some View {
        RoundedRectangle(cornerRadius: max(4, scale))
            .strokeBorder(
                LinearGradient(colors: [Color(red: 0.949, green: 0.765, blue: 0.612),
                                        Color(red: 0.902, green: 0.769, blue: 0.471)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: max(2, scale * 0.7))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(shown ? 1 : 0)
            .onAppear { withAnimation(.easeIn(duration: 0.5)) { shown = true } }
    }
}

/// Renders the minigame field for the play/paused/countdown/over phases — a
/// port of `minigame.js`'s `render()`/`drawGrid` using the existing crisp-pixel
/// approach. The arming perk-up is drawn by the widget (ContentView); this view
/// owns the grown overlay window.
struct GameView: View {
    @ObservedObject var game: BreakGame
    let palette: Palette

    private var scale: CGFloat { CGFloat(game.renderScale) }
    private var W: CGFloat { CGFloat(FW) * scale }
    private var H: CGFloat { CGFloat(FH) * scale }

    var body: some View {
        ZStack {
            Canvas { ctx, _ in drawScene(&ctx) }
                .frame(width: W, height: H)

            hud

            if game.phase == .paused { overlayScrim { pausedText } }
            if game.phase == .countdown { overlayScrim { countdownText } }
            if game.phase == .over { resultCard }

            stopButton.allowsHitTesting(false)   // always on top of any overlay
        }
        .frame(width: W, height: H)
    }

    // MARK: - Field

    private func drawScene(_ ctx: inout GraphicsContext) {
        var ox = 0.0, oy = 0.0
        if game.shake > 0 { ox = Double.random(in: -1.2...1.2); oy = Double.random(in: -1.2...1.2) }

        // treats
        for t in game.treats {
            let d = BreakGame.TREATS[t.type]!
            drawGrid(&ctx, d.grid, x: t.x + ox, y: t.y + oy, f: 1)
        }
        // character (downscaled)
        let c = game.renderCharacter()
        drawGrid(&ctx, c.grid, x: c.x + ox, y: c.y + oy, f: CHAR_SCALE)
        // lives (catch/tap)
        if game.mode != "react" {
            for i in 0..<3 {
                drawGrid(&ctx, i < game.lives ? BreakGame.heartGrid : BreakGame.heartGray,
                         x: Double(3 + i * 6), y: 3, f: 1)
            }
        }
        // particles
        for p in game.parts { drawGrid(&ctx, p.grid, x: p.x, y: p.y, f: 1) }
        // floating +pts
        for p in game.pops {
            let a = max(0, min(1, 1 - p.t / 0.7))
            ctx.draw(Text("+\(p.pts)").font(.custom("Menlo-Bold", size: 8 * scale / 4))
                        .foregroundColor(.white.opacity(a)),
                     at: CGPoint(x: p.x * scale, y: (p.y - p.t * 14) * scale))
        }
        // flash
        if game.flash > 0 {
            ctx.fill(Path(CGRect(x: 0, y: 0, width: W, height: H)),
                     with: .color(.white.opacity(min(1, game.flash * 1.4))))
        }
    }

    /// Draw a pixel grid at field-cell origin (x,y); `f` scales each grid cell
    /// in field cells (1 = treats, 0.5 = characters). Tiles with floor/ceil so
    /// half-size cells leave no seams.
    private func drawGrid(_ ctx: inout GraphicsContext, _ g: PixelGrid, x: Double, y: Double, f: Double) {
        let s = Double(scale)
        for r in 0..<g.height {
            for col in 0..<g.width {
                guard let k = g.get(col, r) else { continue }
                let px0 = (x + Double(col) * f) * s
                let py0 = (y + Double(r) * f) * s
                let px1 = (x + Double(col + 1) * f) * s
                let py1 = (y + Double(r + 1) * f) * s
                let rx = floor(px0), ry = floor(py0)
                let rw = max(1, floor(px1) - rx), rh = max(1, floor(py1) - ry)
                ctx.fill(Path(CGRect(x: rx, y: ry, width: rw, height: rh)), with: .color(palette.color(k)))
            }
        }
    }

    // MARK: - HUD

    private var hud: some View {
        ZStack {
            // score + combo, top-center
            VStack(spacing: 2 * scale / 4) {
                if game.phase == .play && game.mode != "react" {
                    pixelText("\(game.score)", size: 10)
                    if game.mode == "tap" && game.combo > 1 {
                        pixelText("×\(game.combo)", size: 8).foregroundColor(palette.color("gold"))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 5 * scale / 4)

            // reaction prompt, centered upper
            if !game.reactionPrompt.isEmpty {
                pixelText(game.reactionPrompt, size: 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .offset(y: -H * 0.18)
            }

            // brief how-to hint at the start of a round
            if game.showIntro {
                pixelText(game.instructions, size: 9)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 8 * scale / 4)
            }
        }
        .allowsHitTesting(false)
    }

    /// Always-visible quit control (hit-tested in BreakGame via field coords).
    private var stopButton: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2 * scale)
                .fill(Color.black.opacity(0.35))
            Text("✕").font(.custom("Menlo-Bold", size: 9 * scale / 4)).foregroundColor(.white)
        }
        .frame(width: 7 * scale, height: 7 * scale)
        .position(x: (CGFloat(FW) - 5.5) * scale, y: 5.5 * scale)
    }

    private func pixelText(_ s: String, size: CGFloat) -> Text {
        Text(s).font(.custom("Menlo-Bold", size: size * scale / 4)).foregroundColor(.white)
    }

    // MARK: - Overlays

    private func overlayScrim<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        ZStack {
            Color.black.opacity(0.32)
            content()
        }
        .frame(width: W, height: H)
        .allowsHitTesting(false)
    }

    private var pausedText: some View {
        VStack(spacing: 4 * scale / 4) {
            pixelText("paused", size: 12).foregroundColor(.white)
            pixelText(game.instructions, size: 8).foregroundColor(.white.opacity(0.85))
        }
    }

    private var countdownText: some View {
        Text("\(game.countdownValue)")
            .font(.custom("Menlo-Bold", size: 28 * scale / 4))
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
    }

    private var resultCard: some View {
        ZStack {
            Color(red: 64/255, green: 52/255, blue: 37/255).opacity(0.46)
            VStack(spacing: 6 * scale / 4) {
                pixelText(game.resultBestText, size: 8).foregroundColor(.white.opacity(0.85))
                pixelText(game.resultScoreText, size: 22).foregroundColor(.white)
                pixelText(game.resultLabel, size: 10)
                    .foregroundColor(game.resultCelebrate ? palette.color("gold") : .white)
                pixelText("click to play again", size: 7).foregroundColor(.white.opacity(0.7))
            }
        }
        .frame(width: W, height: H)
    }
}
