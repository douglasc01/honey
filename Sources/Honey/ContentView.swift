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

struct ContentView: View {
    @EnvironmentObject var honey: Honey

    var body: some View {
        VStack(spacing: honey.scale >= 4 ? 8 : 6) {
            SpriteCanvas()
            TaskLabel(text: honey.displayLabel, fontSize: honey.scale >= 4 ? 12 : 10)
        }
        .padding(honey.scale >= 4 ? 14 : 10)
        .fixedSize()
    }
}
