// Copyright 2026 OK1XOE (RYRY), LGPL v3
import AppUI
import TUIKit

public struct RGB: Equatable, Sendable {
    public var r, g, b: UInt8
    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) { self.r = r; self.g = g; self.b = b }
    var brightness: Int { Int(r) + Int(g) + Int(b) }                 // 0…765
    var color: Color { .rgb(r, g, b) }
}

/// Waterfall and spectrum pixels → terminal cells. With Unicode and colors a cell is a half block (two pixel rows);
/// otherwise a character from an ASCII brightness ramp (colored when the terminal has colors).
public enum WaterfallRaster {
    public static let asciiRamp: [Character] = Array(" .:-=+*#%@")

    /// The waterfall rows of the model (newest first) as RGB, sampled down to at most `maxRows` rows.
    public static func rows(from w: WaterfallRenderer, maxRows: Int) -> [[RGB]] {
        guard maxRows > 0, w.height > 0 else { return [] }
        let n = min(maxRows, w.height)
        return (0..<n).map { i in w.row(i * w.height / n).map { RGB($0.r, $0.g, $0.b) } }
    }

    public static func cells(rows: [[RGB]], cols: Int, cellRows: Int, caps: Capabilities) -> [[Cell]] {
        guard cols > 0, cellRows > 0 else { return [] }
        let half = caps.unicode && caps.colorDepth != .mono
        let pixelRows = half ? cellRows * 2 : cellRows
        func pixel(_ py: Int, _ x: Int) -> RGB {
            guard !rows.isEmpty else { return RGB(0, 0, 0) }
            let row = rows[min(rows.count - 1, py * rows.count / pixelRows)]
            guard !row.isEmpty else { return RGB(0, 0, 0) }
            let a = x * row.count / cols
            let b = max(a + 1, (x + 1) * row.count / cols)
            var best = row[a]
            for i in a..<min(b, row.count) where row[i].brightness > best.brightness { best = row[i] }
            return best
        }
        return (0..<cellRows).map { cy in
            (0..<cols).map { x -> Cell in
                if half {
                    let top = pixel(cy * 2, x), bottom = pixel(cy * 2 + 1, x)
                    return Cell(char: "▀", style: Style(fg: top.color, bg: bottom.color))
                }
                let p = pixel(cy, x)
                let ch = asciiRamp[min(asciiRamp.count - 1, p.brightness * asciiRamp.count / 766)]
                return Cell(char: ch, style: caps.colorDepth == .mono ? .plain : Style(fg: p.color))
            }
        }
    }

    public static func spectrum(_ line: [Float], cols: Int, cellRows: Int, caps: Capabilities, markCol: Int?, spaceCol: Int?) -> [[Cell]] {
        guard cols > 0, cellRows > 0 else { return [] }
        let blocks: [Character] = ["▁", "▂", "▃", "▄", "▅", "▆", "▇"]
        let bar = caps.colorDepth == .mono ? Style.plain : Style(fg: .rgb(110, 220, 120))
        var out = [[Cell]](repeating: [Cell](repeating: .blank, count: cols), count: cellRows)
        for x in 0..<cols {
            var v: Float = 0
            if !line.isEmpty {
                let a = x * line.count / cols, b = max(a + 1, (x + 1) * line.count / cols)
                for i in a..<min(b, line.count) { v = max(v, line[i]) }
            }
            let eighths = Int((min(1, max(0, v)) * Float(cellRows * 8)).rounded())
            let full = eighths / 8, part = eighths % 8
            for k in 0..<full where cellRows - 1 - k >= 0 {
                out[cellRows - 1 - k][x] = Cell(char: caps.unicode ? "█" : "#", style: bar)
            }
            if part > 0, cellRows - 1 - full >= 0 {
                let ch: Character = caps.unicode ? blocks[part - 1] : (part <= 2 ? "." : part <= 5 ? ":" : "|")
                out[cellRows - 1 - full][x] = Cell(char: ch, style: bar)
            }
        }
        if let m = markCol, (0..<cols).contains(m) {
            out[0][m] = Cell(char: caps.unicode ? "▼" : "M", style: Style(fg: .rgb(255, 90, 90), bold: true))
        }
        if let s = spaceCol, (0..<cols).contains(s) {
            out[0][s] = Cell(char: caps.unicode ? "▽" : "S", style: Style(fg: .rgb(90, 200, 255), bold: true))
        }
        return out
    }

    public static func hzToColumn(_ hz: Double, fromHz: Double, toHz: Double, cols: Int) -> Int {
        guard cols > 0, toHz > fromHz else { return 0 }
        return min(cols - 1, max(0, Int((hz - fromHz) / (toHz - fromHz) * Double(cols))))
    }

    /// The centre frequency of a column.
    public static func columnToHz(_ col: Int, fromHz: Double, toHz: Double, cols: Int) -> Double {
        guard cols > 0 else { return fromHz }
        return fromHz + (Double(col) + 0.5) / Double(cols) * (toHz - fromHz)
    }
}
