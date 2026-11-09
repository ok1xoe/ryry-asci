// Copyright 2026 OK1XOE (RYRY), LGPL v3

/// Turns the difference between two screen buffers into terminal bytes (cursor moves + SGR styles + characters).
/// The terminal is assumed to be in the default style before each `render` (every render ends with a reset when needed).
public struct ANSIWriter: Sendable {
    public let caps: Capabilities
    public init(caps: Capabilities) { self.caps = caps }

    public func render(_ new: ScreenBuffer, previous: ScreenBuffer?) -> [UInt8] {
        var out = ""
        let full = previous == nil || previous!.width != new.width || previous!.height != new.height
        if full { out += "\u{1B}[0m\u{1B}[2J" }
        var current = Style.plain
        for y in 0..<new.height {
            var cursorX = -1                                   // -1 = unknown, must move
            for x in 0..<new.width {
                let cell = new[x: x, y: y]
                if cell.isContinuation { continue }
                if !full, previous![x: x, y: y] == cell { continue }
                if full, cell == .blank, new[x: x, y: y].style == .plain { continue }   // the screen was just cleared
                if cursorX != x { out += "\u{1B}[\(y + 1);\(x + 1)H" }
                if cell.style != current { out += sgr(cell.style); current = cell.style }
                out.append(cell.char)
                cursorX = x + (ScreenBuffer.displayWidth(cell.char) == 2 ? 2 : 1)
            }
        }
        if current != .plain { out += "\u{1B}[0m" }
        return Array(out.utf8)
    }

    private func sgr(_ s: Style) -> String {
        var p = ["0"]
        if s.bold { p.append("1") }
        if s.dim { p.append("2") }
        if s.underline { p.append("4") }
        if s.inverse { p.append("7") }
        p += colorParams(s.fg, base: 30)
        p += colorParams(s.bg, base: 40)
        return "\u{1B}[" + p.joined(separator: ";") + "m"
    }

    private func colorParams(_ c: Color, base: Int) -> [String] {
        switch Self.quantize(c, to: caps.colorDepth) {
        case .default: return []
        case .rgb(let r, let g, let b): return [base == 30 ? "38" : "48", "2", "\(r)", "\(g)", "\(b)"]
        case .indexed(let i):
            if caps.colorDepth == .ansi16 { return [String(i < 8 ? base + Int(i) : base + 60 + Int(i) - 8)] }
            return [base == 30 ? "38" : "48", "5", "\(i)"]
        }
    }

    // MARK: quantization

    private static let ansi16: [(Int, Int, Int)] = [
        (0, 0, 0), (205, 0, 0), (0, 205, 0), (205, 205, 0), (0, 0, 238), (205, 0, 205), (0, 205, 205), (229, 229, 229),
        (127, 127, 127), (255, 0, 0), (0, 255, 0), (255, 255, 0), (92, 92, 255), (255, 0, 255), (0, 255, 255), (255, 255, 255),
    ]

    public static func quantize(_ c: Color, to depth: ColorDepth) -> Color {
        switch (c, depth) {
        case (.default, _), (_, .mono): return .default
        case (.rgb, .trueColor), (.indexed, .trueColor), (.indexed, .ansi256): return c
        case (.rgb(let r, let g, let b), .ansi256): return .indexed(cube(Int(r), Int(g), Int(b)))
        case (.rgb(let r, let g, let b), .ansi16): return .indexed(nearest16(Int(r), Int(g), Int(b)))
        case (.indexed(let i), .ansi16):
            if i < 16 { return c }
            let (r, g, b) = rgb(ofIndex: Int(i)); return .indexed(nearest16(r, g, b))
        }
    }

    private static func cube(_ r: Int, _ g: Int, _ b: Int) -> UInt8 {
        if max(r, g, b) - min(r, g, b) < 8 {                    // a grey: use the grey ramp for finer steps
            let avg = (r + g + b) / 3
            if avg < 5 { return 16 }
            if avg > 246 { return 231 }
            return UInt8(232 + min(23, max(0, (avg - 8 + 5) / 10)))
        }
        func q(_ v: Int) -> Int { (v * 5 + 127) / 255 }
        return UInt8(16 + 36 * q(r) + 6 * q(g) + q(b))
    }

    private static func rgb(ofIndex i: Int) -> (Int, Int, Int) {
        if i < 16 { return ansi16[i] }
        if i >= 232 { let v = 8 + (i - 232) * 10; return (v, v, v) }
        let n = i - 16
        func lv(_ k: Int) -> Int { k == 0 ? 0 : 55 + k * 40 }
        return (lv(n / 36), lv((n / 6) % 6), lv(n % 6))
    }

    private static func nearest16(_ r: Int, _ g: Int, _ b: Int) -> UInt8 {
        var best = 0, bestD = Int.max
        for (i, p) in ansi16.enumerated() {
            let d = (p.0 - r) * (p.0 - r) + (p.1 - g) * (p.1 - g) + (p.2 - b) * (p.2 - b)
            if d < bestD { bestD = d; best = i }
        }
        return UInt8(best)
    }
}
