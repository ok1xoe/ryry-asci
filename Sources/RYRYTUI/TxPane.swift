// Copyright 2026 OK1XOE (RYRY), LGPL v3
import AppUI
import Engine
import TUIKit

/// The transmit window. Behaves like the GUI's `TxEditor`: a multi-line draft (`AppModel.txDraft`); while transmitting, the text
/// is sent as it is typed according to the send mode and the sent part leaves the window; Enter is a new line.
@MainActor
public final class TxPane {
    /// The cursor as a character index into `txDraft`.
    public var cursor = 0
    public init() {}

    private static func next(_ m: SendMode) -> SendMode { switch m { case .char: .word; case .word: .line; case .line: .char } }

    /// Returns true when the event was used.
    public func handle(_ event: InputEvent, model: AppModel) async -> Bool {
        var chars = Array(model.txDraft)
        cursor = min(max(0, cursor), chars.count)
        func lineStart(_ i: Int) -> Int { var j = i; while j > 0, chars[j - 1] != "\n" { j -= 1 }; return j }
        func lineEnd(_ i: Int) -> Int { var j = i; while j < chars.count, chars[j] != "\n" { j += 1 }; return j }
        var edited = false
        switch event {
        case .key(.enter, .alt):
            await sendAll(model); return true
        case .key(.char(let c), let m) where (m.isEmpty || m == .shift) && ScreenBuffer.displayWidth(c) > 0:
            chars.insert(c, at: cursor); cursor += 1; edited = true
        case .key(.enter, let m) where m.isEmpty:
            chars.insert("\n", at: cursor); cursor += 1; edited = true
        case .paste(let s):
            let add = Array(sanitize(s, keepNewlines: true))
            chars.insert(contentsOf: add, at: cursor); cursor += add.count; edited = !add.isEmpty
        case .key(.backspace, _):
            if cursor > 0 { chars.remove(at: cursor - 1); cursor -= 1; edited = true }
        case .key(.delete, _):
            if cursor < chars.count { chars.remove(at: cursor); edited = true }
        case .key(.left, _): cursor = max(0, cursor - 1)
        case .key(.right, _): cursor = min(chars.count, cursor + 1)
        case .key(.home, _): cursor = lineStart(cursor)
        case .key(.end, _): cursor = lineEnd(cursor)
        case .key(.up, _):
            let s = lineStart(cursor), col = cursor - s
            if s > 0 { let ps = lineStart(s - 1); cursor = min(ps + col, s - 1) }
        case .key(.down, _):
            let e = lineEnd(cursor), col = cursor - lineStart(cursor)
            if e < chars.count { let ns = e + 1; cursor = min(ns + col, lineEnd(ns)) }
        case .key(.char("u"), .ctrl):
            model.txDraft = ""; cursor = 0; return true
        case .key(.char("n"), .ctrl):
            model.sendMode = Self.next(model.sendMode); return true
        default: return false
        }
        if edited { model.txDraft = String(chars); await afterEdit(model) }
        return true
    }

    private func afterEdit(_ model: AppModel) async {
        let transmitting = model.state != .rx && model.state != .stopped
        let col = model.settings.txWindow.wrapColumn
        if col > 0 {
            let w = TxWrap.wrap(model.txDraft, column: col, startColumn: transmitting ? model.txSentColumn : 0)
            if w != model.txDraft { model.txDraft = w }
        }
        if transmitting { await send(model, mode: model.sendMode) }
    }

    private func sendAll(_ model: AppModel) async { await send(model, mode: .char) }

    /// Sends according to `mode`; the text that left the draft moves the cursor back accordingly.
    private func send(_ model: AppModel, mode: SendMode) async {
        let before = model.txDraft.count
        await model.sendDraft(mode: mode)
        cursor = max(0, cursor - (before - model.txDraft.count))
    }

    // MARK: drawing

    private struct Visual { var rows: [[Character]]; var cursorRow: Int; var cursorCol: Int }

    private static func layout(_ draft: String, width: Int, cursor: Int) -> Visual {
        var rows: [[Character]] = [[]]
        var col = 0, cRow = 0, cCol = 0
        let chars = Array(draft)
        for i in 0...chars.count {
            if i == min(cursor, chars.count) { cRow = rows.count - 1; cCol = col }
            if i == chars.count { break }
            let ch = chars[i]
            if ch == "\n" { rows.append([]); col = 0; continue }
            let w = max(1, ScreenBuffer.displayWidth(ch))
            if col + w > width { rows.append([]); col = 0; if i == min(cursor, chars.count) { cRow = rows.count - 1; cCol = 0 } }
            rows[rows.count - 1].append(ch); col += w
        }
        return Visual(rows: rows, cursorRow: cRow, cursorCol: cCol)
    }

    public static func draw(into buf: inout ScreenBuffer, rect: Rect, model: AppModel, cursor: Int, focused: Bool) {
        guard rect.w > 0, rect.h > 0 else { return }
        buf.fill(rect)
        let bar = Style(bold: focused, inverse: true)
        buf.fill(Rect(rect.x, rect.y, rect.w, 1), style: bar)
        var x = rect.x
        x += buf.put(" TX ", x: x, y: rect.y, style: bar, clip: rect)
        for (m, name) in [(SendMode.char, "char"), (.word, "word"), (.line, "line")] {
            let sel = model.sendMode == m
            x += buf.put(sel ? "[\(name)]" : " \(name) ", x: x, y: rect.y, style: Style(bold: sel, dim: !sel, inverse: true), clip: rect)
        }
        let hint = "  Alt+Enter send all · Ctrl+U clear · Ctrl+N mode"
        if rect.w - (x - rect.x) >= hint.count { buf.put(hint, x: x, y: rect.y, style: Style(dim: true, inverse: true), clip: rect) }
        let rows = rect.h - 1
        guard rows > 0 else { return }
        let draft = sanitize(model.txDraft, keepNewlines: true)
        let v = layout(draft, width: rect.w, cursor: min(cursor, draft.count))
        let first = max(0, v.cursorRow - rows + 1)
        for r in 0..<rows where first + r < v.rows.count {
            buf.put(String(v.rows[first + r]), x: rect.x, y: rect.y + 1 + r, style: .plain, clip: rect)
        }
        let cy = rect.y + 1 + v.cursorRow - first, cx = rect.x + min(v.cursorCol, rect.w - 1)
        var cell = buf[x: cx, y: cy]
        cell.style.inverse = true
        buf[x: cx, y: cy] = cell                       // the cursor stays visible also when the pane is not focused
    }
}
