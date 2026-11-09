// Copyright 2026 OK1XOE (RYRY), LGPL v3
import AppUI
import TUIKit

public struct RxSegment: Equatable, Sendable {
    public var text: String
    public var echo: Bool
    public var startCol: Int
}

public struct RxLine: Equatable, Sendable {
    public var segments: [RxSegment]
    public var plain: String { segments.map(\.text).joined() }
}

/// The receive window: wrapping of the received runs, scrollback, drawing and finding the word under the mouse.
public enum RxPane {
    public static let echoStyle = Style(fg: .rgb(120, 200, 255))

    private struct Ch { var c: Character; var echo: Bool; var w: Int }

    /// Wraps the runs to `width` columns: at spaces when the word fits, hard otherwise; `\n` starts a new line.
    /// The text is sanitized first, so nothing from the radio can reach the terminal as a control sequence.
    public static func wrap(_ runs: [RxRun], width: Int) -> [RxLine] {
        let width = max(1, width)
        var lines: [[Ch]] = []
        var cur: [Ch] = []
        var curW = 0
        func flush() { lines.append(cur); cur = []; curW = 0 }
        for run in runs {
            for ch in sanitize(run.text, keepNewlines: true) {
                if ch == "\n" { flush(); continue }
                let w = max(1, ScreenBuffer.displayWidth(ch))
                if curW + w > width {
                    if ch != " ", let sp = cur.lastIndex(where: { $0.c == " " }), sp > 0 {
                        let rest = Array(cur[(sp + 1)...])
                        cur = Array(cur[..<sp])
                        flush()
                        cur = rest; curW = rest.reduce(0) { $0 + $1.w }
                    } else if ch == " " {
                        flush(); continue                              // the break replaces the space
                    } else {
                        flush()
                    }
                }
                cur.append(Ch(c: ch, echo: run.echo, w: w)); curW += w
            }
        }
        if !cur.isEmpty || lines.isEmpty { flush() }
        return lines.map(segments)
    }

    private static func segments(_ chars: [Ch]) -> RxLine {
        var segs: [RxSegment] = []
        var col = 0
        for ch in chars {
            if let last = segs.last, last.echo == ch.echo { segs[segs.count - 1].text.append(ch.c) }
            else { segs.append(RxSegment(text: String(ch.c), echo: ch.echo, startCol: col)) }
            col += ch.w
        }
        return RxLine(segments: segs)
    }

    /// The whole word under column `col` (also when it spans several runs), nil on a space or outside the text.
    public static func word(at col: Int, line: RxLine) -> String? {
        var cells: [(c: Character, col: Int, w: Int)] = []
        var x = 0
        for s in line.segments { for ch in s.text { let w = max(1, ScreenBuffer.displayWidth(ch)); cells.append((ch, x, w)); x += w } }
        guard col >= 0, let i = cells.firstIndex(where: { col >= $0.col && col < $0.col + $0.w }), cells[i].c != " " else { return nil }
        var a = i, b = i
        while a > 0, cells[a - 1].c != " " { a -= 1 }
        while b < cells.count - 1, cells[b + 1].c != " " { b += 1 }
        return String(cells[a...b].map(\.c))
    }

    /// `scroll` = lines back from the end (0 follows the newest text). Text shorter than the pane is top-aligned.
    public static func draw(into buf: inout ScreenBuffer, rect: Rect, lines: [RxLine], scroll: Int, highlight: (String) -> Style?, focused: Bool) {
        guard rect.w > 0, rect.h > 0 else { return }
        buf.fill(rect)
        let scroll = max(0, min(scroll, max(0, lines.count - rect.h)))
        let end = lines.count - scroll
        let start = max(0, end - rect.h)
        for (row, line) in lines[start..<end].enumerated() {
            let y = rect.y + row
            for s in line.segments { buf.put(s.text, x: rect.x + s.startCol, y: y, style: s.echo ? echoStyle : .plain, clip: rect) }
            // words get their highlight style (own call, needed station, …)
            var col = 0, wordStart = 0, word = ""
            func close() {
                if !word.isEmpty, let st = highlight(word) {
                    for cx in wordStart..<col where rect.x + cx < rect.x + rect.w {
                        var cell = buf[x: rect.x + cx, y: y]; cell.style = st; buf[x: rect.x + cx, y: y] = cell
                    }
                }
                word = ""
            }
            for s in line.segments { for ch in s.text {
                let w = max(1, ScreenBuffer.displayWidth(ch))
                if ch == " " { close(); col += w; wordStart = col } else { word.append(ch); col += w }
            } }
            close()
        }
        if scroll > 0 {
            let tag = " ▼ +\(scroll) "
            buf.put(tag, x: rect.x + rect.w - tag.count, y: rect.y + rect.h - 1, style: Style(bold: focused, inverse: true), clip: rect)
        }
    }
}
