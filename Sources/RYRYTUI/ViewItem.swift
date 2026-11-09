// Copyright 2026 OK1XOE (RYRY), LGPL v3
import TUIKit

/// What a mouse click on a piece of the main screen means. The views only name the target; `TUIApp` acts on it.
public enum HitTarget: Equatable, Sendable {
    case toggleTx, tune, stop, demod, ham, profile, frequency, baud, shift, filters
    case toggle(String)              // a parameter / switch: afc, net, reverse, atc, squelch, xy, second
    case macro(Int)
    case dismissMessage
    case qsoField(String)
    case previousQSO(Int)
}

/// A piece of text placed on a row; the views are built from these so drawing and hit-testing share one layout.
public struct ViewItem: Equatable, Sendable {
    public var text: String
    public var x: Int
    public var y: Int
    public var style: Style
    public var target: HitTarget?
    public var width: Int { text.cellWidth }
}

enum ItemRow {
    static func draw(_ items: [ViewItem], into buf: inout ScreenBuffer, clip: Rect) {
        for i in items { buf.put(i.text, x: i.x, y: i.y, style: i.style, clip: clip) }
    }
    static func hit(_ items: [ViewItem], x: Int, y: Int) -> HitTarget? {
        items.first { $0.target != nil && $0.y == y && x >= $0.x && x < $0.x + $0.width }?.target
    }
}

/// Lays items left to right on one row.
struct RowBuilder {
    let y: Int
    var x: Int
    private(set) var items: [ViewItem] = []
    init(y: Int, x: Int) { self.y = y; self.x = x }
    mutating func add(_ text: String, style: Style = .plain, target: HitTarget? = nil) {
        let it = ViewItem(text: text, x: x, y: y, style: style, target: target)
        items.append(it); x += it.width
    }
    mutating func gap(_ n: Int = 1) { x += n }
}

extension String {
    var cellWidth: Int { reduce(0) { $0 + max(0, ScreenBuffer.displayWidth($1)) } }

    /// Cut to `width` columns (never splitting a wide character); padded with spaces when `pad`.
    func fitted(to width: Int, pad: Bool = true) -> String {
        var out = "", w = 0
        for ch in self {
            let cw = ScreenBuffer.displayWidth(ch)
            if cw < 0 { continue }
            if w + cw > width { break }
            out.append(ch); w += cw
        }
        if pad, w < width { out += String(repeating: " ", count: width - w) }
        return out
    }

    /// Cut to `width` columns with a trailing ellipsis when it did not fit.
    func ellipsized(to width: Int) -> String {
        guard cellWidth > width, width > 0 else { return fitted(to: width, pad: false) }
        return fitted(to: width - 1, pad: false) + "…"
    }
}

func parseHexColor(_ s: String?) -> (UInt8, UInt8, UInt8)? {
    guard var h = s, !h.isEmpty else { return nil }
    if h.hasPrefix("#") { h.removeFirst() }
    guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
    return (UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF))
}
