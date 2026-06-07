import SwiftUI

/// One non-transparent cell of a frame, with its color resolved from the palette.
/// Carries both a SwiftUI `Color` (desktop Canvas) and a `CGColor` (menu-bar image).
struct Pixel {
    let x: Int
    let y: Int
    let color: Color
    let cg: CGColor
}

/// Tight bounding box (in grid cells) of drawn content — used to crop/center
/// the menu-bar icon without jitter.
struct PixelBounds {
    let minX: Int, minY: Int, width: Int, height: Int
}

/// A single scene a cast can perform: a looping set of pre-rendered frames.
/// `width`/`height` are the scene's own pixel grid (solo = 32×32, together = 56×32).
struct Scene: Identifiable {
    let id: String
    let label: String
    let fps: Double
    let width: Int
    let height: Int
    let frames: [[Pixel]]
    let bounds: PixelBounds
}

/// A cast: Honey (solo), Bagel (solo), or both together (wide scenes).
struct Cast: Identifiable {
    let id: String
    let name: String
    let solo: Bool
    let width: Int
    let scenes: [Scene]
}

/// Resolves palette keys (e.g. "OL", "gold") to colors. Built once from the
/// hex map in honey-and-bagel.json so the procedural game engine and the baked
/// scenes share one source of truth for color.
struct Palette {
    let rgb: [String: (r: Double, g: Double, b: Double)]

    func color(_ key: String) -> Color {
        guard let c = rgb[key] else { return .clear }
        return Color(red: c.r, green: c.g, blue: c.b)
    }
    func cg(_ key: String) -> CGColor {
        guard let c = rgb[key] else { return CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0) }
        return CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
    }
}

struct SpriteSheet {
    let grid: Int
    let casts: [Cast]
    let castOrder: [String]
    let palette: Palette

    func index(of castID: String) -> Int? { casts.firstIndex { $0.id == castID } }

    /// Loads `honey-and-bagel.json` and precomputes every frame into resolved-color
    /// pixel lists so rendering is a tight fill loop.
    static func load() -> SpriteSheet {
        guard let url = Bundle.main.url(forResource: "honey-and-bagel", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            fatalError("honey-and-bagel.json missing from bundle")
        }
        let raw: RawSheet
        do {
            raw = try JSONDecoder().decode(RawSheet.self, from: data)
        } catch {
            fatalError("Failed to decode honey-and-bagel.json: \(error)")
        }

        let rgb = raw.palette.mapValues { rgbComponents(hex: $0) }

        func buildScene(_ task: RawTask) -> Scene {
            var minX = task.width, minY = task.height, maxX = 0, maxY = 0
            let frames = task.frames.map { grid -> [Pixel] in
                var pixels: [Pixel] = []
                for (y, row) in grid.enumerated() {
                    for (x, cell) in row.enumerated() {
                        if case let .key(k) = cell, let c = rgb[k] {
                            pixels.append(Pixel(
                                x: x, y: y,
                                color: Color(red: c.r, green: c.g, blue: c.b),
                                cg: CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
                            ))
                            minX = min(minX, x); maxX = max(maxX, x)
                            minY = min(minY, y); maxY = max(maxY, y)
                        }
                    }
                }
                return pixels
            }
            let bounds = PixelBounds(minX: minX, minY: minY,
                                     width: max(1, maxX - minX + 1),
                                     height: max(1, maxY - minY + 1))
            return Scene(id: task.id, label: task.label, fps: task.fps,
                         width: task.width, height: task.height,
                         frames: frames, bounds: bounds)
        }

        // Stable display order: Honey, Bagel, Together, then any others.
        let preferred = ["honey", "bagel", "both"]
        let orderedKeys = preferred.filter { raw.casts[$0] != nil }
            + raw.casts.keys.filter { !preferred.contains($0) }.sorted()

        let casts = orderedKeys.map { key -> Cast in
            let rc = raw.casts[key]!
            return Cast(id: key, name: rc.name, solo: rc.solo, width: rc.width,
                        scenes: rc.tasks.map(buildScene))
        }

        return SpriteSheet(grid: raw.grid, casts: casts, castOrder: raw.castOrder,
                           palette: Palette(rgb: rgb))
    }
}

// MARK: - JSON decoding

private struct RawSheet: Decodable {
    let grid: Int
    let palette: [String: String]
    let castOrder: [String]
    let casts: [String: RawCast]
}

private struct RawCast: Decodable {
    let name: String
    let solo: Bool
    let width: Int
    let tasks: [RawTask]
}

private struct RawTask: Decodable {
    let id: String
    let label: String
    let fps: Double
    let width: Int
    let height: Int
    let frames: [[[Cell]]]   // frame -> row -> cell
}

/// A cell is either transparent (`0` as a number, or `"0"`) or a palette key string.
private enum Cell: Decodable {
    case empty
    case key(String)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            self = (s == "0" || s.isEmpty) ? .empty : .key(s)
        } else {
            self = .empty
        }
    }
}

private func rgbComponents(hex: String) -> (r: Double, g: Double, b: Double) {
    var s = hex
    if s.hasPrefix("#") { s.removeFirst() }
    let v = UInt64(s, radix: 16) ?? 0
    return (
        Double((v >> 16) & 0xff) / 255,
        Double((v >> 8) & 0xff) / 255,
        Double(v & 0xff) / 255
    )
}
