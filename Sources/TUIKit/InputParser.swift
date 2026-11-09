// Copyright 2026 OK1XOE (RYRY), LGPL v3

/// Turns the bytes read from the terminal into events. Incomplete sequences wait for the next `feed`; a lone ESC waits until
/// `flushPendingEscape()` (the caller calls it after a short pause) so that Esc can be told apart from escape sequences.
public struct InputParser: Sendable {
    private var buf: [UInt8] = []
    private var pasting = false
    private var pasteBytes: [UInt8] = []
    private static let pasteEnd: [UInt8] = [0x1B, 0x5B, 0x32, 0x30, 0x31, 0x7E]       // ESC [ 2 0 1 ~

    public init() {}

    public mutating func feed(_ bytes: [UInt8]) -> [InputEvent] {
        buf += bytes
        var events: [InputEvent] = []
        while !buf.isEmpty {
            if pasting {
                pasteBytes += buf; buf.removeAll()
                if let r = Self.find(Self.pasteEnd, in: pasteBytes) {
                    events.append(.paste(String(decoding: pasteBytes[..<r], as: UTF8.self)))
                    buf = Array(pasteBytes[(r + Self.pasteEnd.count)...])
                    pasteBytes.removeAll(); pasting = false
                }
                continue
            }
            switch parseOne() {
            case .needMore: return events
            case .consumed(let n, let e):
                buf.removeFirst(n)
                if let e { events.append(e) }
            case .startPaste(let n):
                buf.removeFirst(n); pasting = true
            }
        }
        return events
    }

    /// Call after a pause with no further input: a lone ESC is the Escape key; an incomplete sequence is dropped.
    public mutating func flushPendingEscape() -> [InputEvent] {
        guard !pasting else { return [] }
        defer { buf.removeAll() }
        return buf == [0x1B] ? [.key(.escape, [])] : []
    }

    private enum Step { case needMore, consumed(Int, InputEvent?), startPaste(Int) }

    private func parseOne() -> Step {
        let b = buf[0]
        switch b {
        case 0x1B: return parseEscape()
        case 0x0D, 0x0A: return .consumed(1, .key(.enter, []))
        case 0x09: return .consumed(1, .key(.tab, []))
        case 0x7F, 0x08: return .consumed(1, .key(.backspace, []))
        case 0x00: return .consumed(1, .key(.char(" "), .ctrl))
        case 0x01...0x1A: return .consumed(1, .key(.char(Character(UnicodeScalar(b + 0x60))), .ctrl))
        case 0x1C...0x1F: return .consumed(1, .key(.char(Character(UnicodeScalar(b + 0x40))), .ctrl))
        case 0x20...0x7E: return .consumed(1, .key(.char(Character(UnicodeScalar(b))), []))
        default: return parseUTF8(at: 0, mods: [])
        }
    }

    private func parseUTF8(at i: Int, mods: Modifiers) -> Step {
        let lead = buf[i]
        let len: Int
        switch lead {
        case 0xC2...0xDF: len = 2
        case 0xE0...0xEF: len = 3
        case 0xF0...0xF4: len = 4
        default: return .consumed(i + 1, nil)                      // invalid lead byte: drop it
        }
        if buf.count < i + len { return .needMore }
        guard let s = String(validatingUTF8: buf[i..<(i + len)].map { CChar(bitPattern: $0) } + [0]), let ch = s.first else {
            return .consumed(i + 1, nil)
        }
        return .consumed(i + len, .key(.char(ch), mods))
    }

    private func parseEscape() -> Step {
        if buf.count == 1 { return .needMore }
        switch buf[1] {
        case 0x5B: return parseCSI()
        case 0x4F: return parseSS3()
        case 0x1B: return .consumed(1, .key(.escape, []))
        case 0x20...0x7E: return .consumed(2, .key(.char(Character(UnicodeScalar(buf[1]))), .alt))
        case 0x80...0xFF:
            let s = parseUTF8(at: 1, mods: .alt)
            return s
        default: return .consumed(2, nil)
        }
    }

    private func parseSS3() -> Step {
        var i = 2
        var digits = ""
        while i < buf.count, (0x30...0x39).contains(buf[i]) { digits.append(Character(UnicodeScalar(buf[i]))); i += 1 }
        if i >= buf.count { return .needMore }
        let mods = Self.mods(Int(digits))
        let f = buf[i]
        let key: Key?
        switch f {
        case 0x50: key = .f(1)
        case 0x51: key = .f(2)
        case 0x52: key = .f(3)
        case 0x53: key = .f(4)
        default: key = Self.cursorKey(f)
        }
        return .consumed(i + 1, key.map { .key($0, mods) })
    }

    private func parseCSI() -> Step {
        var i = 2
        while i < buf.count, !(0x40...0x7E).contains(buf[i]) {
            if !(0x20...0x3F).contains(buf[i]) { return .consumed(i, nil) }     // garbage inside a sequence
            i += 1
        }
        if i >= buf.count { return .needMore }
        let final = buf[i]
        let paramText = String(decoding: buf[2..<i], as: UTF8.self)
        let consumed = i + 1
        if paramText.hasPrefix("<"), final == 0x4D || final == 0x6D { return .consumed(consumed, Self.mouse(paramText, release: final == 0x6D)) }
        let params = paramText.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) }
        let n0 = params.first ?? nil
        let mods = Self.mods(params.count > 1 ? params[1] : nil)
        switch final {
        case 0x5A: return .consumed(consumed, .key(.backTab, []))
        case 0x50: return .consumed(consumed, .key(.f(1), mods))
        case 0x51: return .consumed(consumed, .key(.f(2), mods))
        case 0x52: return .consumed(consumed, .key(.f(3), mods))
        case 0x53: return .consumed(consumed, .key(.f(4), mods))
        case 0x7E:
            guard let n = n0 else { return .consumed(consumed, nil) }
            if n == 200 { return .startPaste(consumed) }
            let key: Key?
            switch n {
            case 1, 7: key = .home
            case 2: key = .insert
            case 3: key = .delete
            case 4, 8: key = .end
            case 5: key = .pageUp
            case 6: key = .pageDown
            case 11...15: key = .f(n - 10)
            case 17...21: key = .f(n - 11)
            case 23, 24: key = .f(n - 12)
            default: key = nil
            }
            return .consumed(consumed, key.map { .key($0, mods) })
        default:
            return .consumed(consumed, Self.cursorKey(final).map { .key($0, mods) })
        }
    }

    private static func cursorKey(_ f: UInt8) -> Key? {
        switch f {
        case 0x41: return .up
        case 0x42: return .down
        case 0x43: return .right
        case 0x44: return .left
        case 0x48: return .home
        case 0x46: return .end
        default: return nil
        }
    }

    private static func mods(_ m: Int?) -> Modifiers {
        guard let m, m > 1 else { return [] }
        var r: Modifiers = []
        if (m - 1) & 1 != 0 { r.insert(.shift) }
        if (m - 1) & 2 != 0 { r.insert(.alt) }
        if (m - 1) & 4 != 0 { r.insert(.ctrl) }
        return r
    }

    private static func mouse(_ text: String, release: Bool) -> InputEvent? {
        let p = text.dropFirst().split(separator: ";").map { Int($0) }
        guard p.count == 3, let cb = p[0], let x = p[1], let y = p[2] else { return nil }
        var mods: Modifiers = []
        if cb & 4 != 0 { mods.insert(.shift) }
        if cb & 8 != 0 { mods.insert(.alt) }
        if cb & 16 != 0 { mods.insert(.ctrl) }
        let button: MouseEvent.Button
        switch cb & 3 { case 0: button = .left; case 1: button = .middle; case 2: button = .right; default: button = .none }
        let kind: MouseEvent.Kind
        if cb & 64 != 0 {
            kind = (cb & 3) == 0 ? .wheelUp : .wheelDown
            return .mouse(MouseEvent(kind: kind, button: .none, x: x - 1, y: y - 1, mods: mods))
        }
        if cb & 32 != 0 { kind = button == .none ? .move : .drag } else { kind = release ? .release : .press }
        return .mouse(MouseEvent(kind: kind, button: button, x: x - 1, y: y - 1, mods: mods))
    }

    private static func find(_ needle: [UInt8], in hay: [UInt8]) -> Int? {
        guard hay.count >= needle.count else { return nil }
        for i in 0...(hay.count - needle.count) where Array(hay[i..<(i + needle.count)]) == needle { return i }
        return nil
    }
}
