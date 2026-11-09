// Copyright 2026 OK1XOE (RYRY), LGPL v3

/// A grid of cells the views draw into; `ANSIWriter` turns the difference between two buffers into terminal bytes.
public struct ScreenBuffer: Equatable, Sendable {
    public let width: Int
    public let height: Int
    private var cells: [Cell]

    public init(width: Int, height: Int) {
        self.width = max(0, width); self.height = max(0, height)
        cells = Array(repeating: .blank, count: self.width * self.height)
    }

    public var bounds: Rect { Rect(0, 0, width, height) }

    /// Out-of-range reads return a blank cell and out-of-range writes are ignored.
    public subscript(x x: Int, y y: Int) -> Cell {
        get { (0..<width).contains(x) && (0..<height).contains(y) ? cells[y * width + x] : .blank }
        set { if (0..<width).contains(x) && (0..<height).contains(y) { cells[y * width + x] = newValue } }
    }

    /// Writes `text` from (x, y), clipped to `clip` (default: the whole buffer). Control characters are dropped.
    /// Returns the number of columns used.
    @discardableResult
    public mutating func put(_ text: String, x: Int, y: Int, style: Style, clip: Rect?) -> Int {
        let c = clip.map { intersect($0, bounds) } ?? bounds
        guard c.contains(x: c.x, y: y), y >= c.y, y < c.y + c.h else { return 0 }
        var cx = x
        var used = 0
        for ch in text {
            let w = Self.displayWidth(ch)
            if w < 0 { continue }                      // control character
            if w == 0 { continue }                    // a stray combining mark (Swift joins normal ones into the Character)
            if cx + w > c.x + c.w {                    // would cross the right edge: a wide character is not split
                if w == 2, cx >= c.x, cx < c.x + c.w { self[x: cx, y: y] = Cell(char: " ", style: style); used += 1 }
                break
            }
            if cx >= c.x {
                self[x: cx, y: y] = Cell(char: ch, style: style)
                if w == 2 { self[x: cx + 1, y: y] = Cell(char: " ", style: style, isContinuation: true) }
                used += w
            } else if cx + w > c.x {                   // wide character starting left of the clip
                self[x: c.x, y: y] = Cell(char: " ", style: style); used += 1
            }
            cx += w
        }
        return used
    }

    public mutating func fill(_ r: Rect, char: Character = " ", style: Style = .plain) {
        let rr = intersect(r, bounds)
        guard rr.w > 0, rr.h > 0 else { return }
        for yy in rr.y..<(rr.y + rr.h) { for xx in rr.x..<(rr.x + rr.w) { self[x: xx, y: yy] = Cell(char: char, style: style) } }
    }

    public mutating func box(_ r: Rect, style: Style, ascii: Bool) {
        guard r.w >= 2, r.h >= 2 else { return }
        let (tl, tr, bl, br, hz, vt): (Character, Character, Character, Character, Character, Character) =
            ascii ? ("+", "+", "+", "+", "-", "|") : ("┌", "┐", "└", "┘", "─", "│")
        let x2 = r.x + r.w - 1, y2 = r.y + r.h - 1
        for xx in r.x...x2 { self[x: xx, y: r.y] = Cell(char: hz, style: style); self[x: xx, y: y2] = Cell(char: hz, style: style) }
        for yy in r.y...y2 { self[x: r.x, y: yy] = Cell(char: vt, style: style); self[x: x2, y: yy] = Cell(char: vt, style: style) }
        self[x: r.x, y: r.y] = Cell(char: tl, style: style); self[x: x2, y: r.y] = Cell(char: tr, style: style)
        self[x: r.x, y: y2] = Cell(char: bl, style: style); self[x: x2, y: y2] = Cell(char: br, style: style)
    }

    private func intersect(_ a: Rect, _ b: Rect) -> Rect {
        let x0 = max(a.x, b.x), y0 = max(a.y, b.y)
        let x1 = min(a.x + a.w, b.x + b.w), y1 = min(a.y + a.h, b.y + b.h)
        return Rect(x0, y0, max(0, x1 - x0), max(0, y1 - y0))
    }

    /// Columns a character occupies: -1 = control (not printable), 0 = combining, 2 = wide/emoji, otherwise 1.
    public static func displayWidth(_ c: Character) -> Int {
        guard let first = c.unicodeScalars.first else { return 0 }
        let v = first.value
        if v < 0x20 || v == 0x7F || (0x80...0x9F).contains(v) { return -1 }
        if c.unicodeScalars.count == 1, isCombining(v) { return 0 }
        if c.unicodeScalars.contains(where: { $0.value == 0xFE0F }) { return 2 }     // emoji presentation selector
        return isWide(v) ? 2 : 1
    }

    private static func isCombining(_ v: UInt32) -> Bool {
        (0x0300...0x036F).contains(v) || (0x1AB0...0x1AFF).contains(v) || (0x1DC0...0x1DFF).contains(v)
            || (0x20D0...0x20FF).contains(v) || (0xFE20...0xFE2F).contains(v) || v == 0x200B || v == 0x200D
    }

    private static func isWide(_ v: UInt32) -> Bool {
        (0x1100...0x115F).contains(v) || (0x2E80...0xA4CF).contains(v) || (0xAC00...0xD7A3).contains(v)
            || (0xF900...0xFAFF).contains(v) || (0xFE30...0xFE6F).contains(v) || (0xFF00...0xFF60).contains(v)
            || (0xFFE0...0xFFE6).contains(v) || (0x1F300...0x1F64F).contains(v) || (0x1F900...0x1F9FF).contains(v)
            || (0x20000...0x3FFFD).contains(v)
    }
}
