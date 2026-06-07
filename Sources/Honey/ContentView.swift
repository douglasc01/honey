import SwiftUI

/// Renders the current frame: one filled rect per non-transparent pixel,
/// integer-scaled, no smoothing — pixels stay crisp. Sized to the scene's own
/// grid (32×32 for a solo friend, 56×32 when both are together).
struct SpriteCanvas: View {
    @EnvironmentObject var honey: Honey

    var body: some View {
        let scene = honey.scene
        let w = CGFloat(scene.width * honey.scale)
        let h = CGFloat(scene.height * honey.scale)
        Canvas { ctx, size in
            let s = size.height / CGFloat(scene.height)
            for p in honey.currentPixels {
                let rect = CGRect(x: CGFloat(p.x) * s, y: CGFloat(p.y) * s, width: s, height: s)
                ctx.fill(Path(rect), with: .color(p.color))
            }
        }
        .frame(width: w, height: h)
    }
}

/// Pixel-style label: white with a soft shadow so it reads on any wallpaper.
struct TaskLabel: View {
    let text: String
    let fontSize: CGFloat

    var body: some View {
        Text(text)
            .font(.custom("Menlo-Bold", size: fontSize))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .shadow(color: .black.opacity(0.55), radius: 2, x: 0, y: 1)
    }
}

/// During the 5s hover arm, the pet "perks up" (the procedural perk frames) over
/// a peach→gold meter that fills as `armProgress` climbs.
struct PerkView: View {
    @EnvironmentObject var honey: Honey
    @ObservedObject var game: BreakGame

    var body: some View {
        let s = CGFloat(honey.scale)
        // Use the ambient sprite's box so the perk-up sits in the same spot for
        // every cast — the duo scene (56×32) is wider/shorter than the stacked
        // perk pose (32×44), so fit the pose into the box rather than resize.
        let boxW = CGFloat(honey.scene.width) * s
        let boxH = CGFloat(honey.scene.height) * s
        let frames = game.perk.frames
        let grid = frames.isEmpty ? PixelGrid(game.perk.w, game.perk.h) : frames[game.fi % frames.count]
        let cell = min(boxW / CGFloat(grid.width), boxH / CGFloat(grid.height))

        VStack(spacing: honey.scale >= 4 ? 8 : 6) {
            Canvas { ctx, _ in
                let pal = honey.sheet.palette
                let ox = (boxW - CGFloat(grid.width) * cell) / 2   // center horizontally
                let oy = boxH - CGFloat(grid.height) * cell        // sit at the bottom
                for r in 0..<grid.height {
                    for c in 0..<grid.width {
                        guard let k = grid.get(c, r) else { continue }
                        // floor each edge so fractional cells tile seamlessly (no grid lines)
                        let x0 = (ox + CGFloat(c) * cell).rounded(.down)
                        let y0 = (oy + CGFloat(r) * cell).rounded(.down)
                        let x1 = (ox + CGFloat(c + 1) * cell).rounded(.down)
                        let y1 = (oy + CGFloat(r + 1) * cell).rounded(.down)
                        ctx.fill(Path(CGRect(x: x0, y: y0, width: max(1, x1 - x0), height: max(1, y1 - y0))),
                                 with: .color(pal.color(k)))
                    }
                }
            }
            .frame(width: boxW, height: boxH)

            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.25))
                Capsule()
                    .fill(LinearGradient(colors: [Color(red: 0.949, green: 0.765, blue: 0.612),
                                                  Color(red: 0.902, green: 0.769, blue: 0.471)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(2, CGFloat(game.armProgress) * boxW))
            }
            .frame(width: boxW, height: 5)
        }
        .padding(honey.scale >= 4 ? 14 : 10)
        .fixedSize()
    }
}

struct ContentView: View {
    @EnvironmentObject var honey: Honey
    @ObservedObject var game: BreakGame

    var body: some View {
        Group {
            if game.phase == .arm {
                PerkView(game: game)
            } else {
                VStack(spacing: honey.scale >= 4 ? 8 : 6) {
                    SpriteCanvas()
                    TaskLabel(text: honey.displayLabel, fontSize: honey.scale >= 4 ? 12 : 10)
                }
                .padding(honey.scale >= 4 ? 14 : 10)
                .fixedSize()
            }
        }
    }
}
