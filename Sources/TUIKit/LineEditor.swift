// Copyright 2026 OK1XOE (RYRY), LGPL v3

/// A single-line text editor (cursor counted in characters). `handle` returns true when the key was used.
public struct LineEditor: Equatable, Sendable {
    public var text: String
    public var cursor: Int

    public init(text: String = "") { self.text = text; cursor = text.count }

    public mutating func insert(_ s: String) {
        let add = Array(sanitize(s))
        var c = Array(text)
        c.insert(contentsOf: add, at: min(cursor, c.count))
        text = String(c); cursor += add.count
    }

    @discardableResult
    public mutating func handle(_ key: Key, _ mods: Modifiers) -> Bool {
        var c = Array(text)
        cursor = min(max(0, cursor), c.count)
        switch (key, mods) {
        case (.char(let ch), []), (.char(let ch), .shift):
            insert(String(ch)); return true
        case (.left, _): cursor = max(0, cursor - 1)
        case (.right, _): cursor = min(c.count, cursor + 1)
        case (.home, _), (.char("a"), .ctrl): cursor = 0
        case (.end, _), (.char("e"), .ctrl): cursor = c.count
        case (.backspace, _):
            guard cursor > 0 else { return true }
            c.remove(at: cursor - 1); cursor -= 1; text = String(c)
        case (.delete, _), (.char("d"), .ctrl):
            guard cursor < c.count else { return true }
            c.remove(at: cursor); text = String(c)
        case (.char("k"), .ctrl): text = String(c[..<cursor])
        case (.char("u"), .ctrl): text = String(c[cursor...]); cursor = 0
        case (.char("w"), .ctrl):
            var i = cursor
            while i > 0, c[i - 1] == " " { i -= 1 }
            while i > 0, c[i - 1] != " " { i -= 1 }
            c.removeSubrange(i..<cursor); text = String(c); cursor = i
        default: return false
        }
        return true
    }
}
