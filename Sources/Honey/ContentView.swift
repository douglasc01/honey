import SwiftUI

/// Renders the current frame: one filled rect per non-transparent pixel,
/// integer-scaled, no smoothing — pixels stay crisp.
struct SpriteCanvas: View {
    @EnvironmentObject var honey: Honey

    var body: some View {
        let side = CGFloat(honey.sheet.grid * honey.scale)
        Canvas { ctx, size in
            let scale = size.width / CGFloat(honey.sheet.grid)
            for p in honey.currentPixels {
                let rect = CGRect(
                    x: CGFloat(p.x) * scale,
                    y: CGFloat(p.y) * scale,
                    width: scale,
                    height: scale
                )
                ctx.fill(Path(rect), with: .color(p.color))
            }
        }
        .frame(width: side, height: side)
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
            TaskLabel(text: honey.activity.label, fontSize: honey.scale >= 4 ? 12 : 10)
        }
        .padding(honey.scale >= 4 ? 14 : 10)
        .fixedSize()
    }
}
