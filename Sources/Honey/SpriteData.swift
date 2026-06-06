import SwiftUI

/// One non-transparent cell of a frame, with its color resolved from the palette.
/// Carries both a SwiftUI `Color` (desktop Canvas) and a `CGColor` (menu-bar image).
struct Pixel {
    let x: Int
    let y: Int
    let color: Color
    let cg: CGColor
}

/// A single activity Honey can perform: a looping set of pre-rendered frames.
struct Activity: Identifiable {
    let id: String
    let label: String
    let fps: Double
    let frames: [[Pixel]]   // each frame is its list of non-transparent pixels
}

/// Tight bounding box (in grid cells) of drawn content, unioned across every
/// frame of every activity — used to center/crop the menu-bar icon without jitter.
struct PixelBounds {
    let minX: Int, minY: Int, width: Int, height: Int
}

struct SpriteSheet {
    let grid: Int
    let activities: [Activity]
    let bounds: PixelBounds

    /// Loads `honey-sprites.json` from the bundle and precomputes every frame
    /// into resolved-color pixel lists, so rendering is a tight fill loop.
    static func load() -> SpriteSheet {
        guard let url = Bundle.main.url(forResource: "honey-sprites", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            fatalError("honey-sprites.json missing from bundle")
        }
        let raw: RawSheet
        do {
            raw = try JSONDecoder().decode(RawSheet.self, from: data)
        } catch {
            fatalError("Failed to decode honey-sprites.json: \(error)")
        }

        let rgb = raw.palette.mapValues { rgbComponents(hex: $0) }
        let activities = raw.tasks.map { task -> Activity in
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
                        }
                    }
                }
                return pixels
            }
            return Activity(id: task.id, label: task.label, fps: task.fps, frames: frames)
        }

        var minX = raw.grid, minY = raw.grid, maxX = 0, maxY = 0
        for activity in activities {
            for frame in activity.frames {
                for p in frame {
                    minX = min(minX, p.x); maxX = max(maxX, p.x)
                    minY = min(minY, p.y); maxY = max(maxY, p.y)
                }
            }
        }
        let bounds = PixelBounds(minX: minX, minY: minY,
                                 width: maxX - minX + 1, height: maxY - minY + 1)
        return SpriteSheet(grid: raw.grid, activities: activities, bounds: bounds)
    }
}

// MARK: - JSON decoding

private struct RawSheet: Decodable {
    let grid: Int
    let palette: [String: String]
    let tasks: [RawTask]
}

private struct RawTask: Decodable {
    let id: String
    let label: String
    let fps: Double
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
            self = .empty   // any numeric cell (only 0 appears) is transparent
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
