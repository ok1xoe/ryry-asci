// Copyright 2026 OK1XOE (RYRY), LGPL v3
import AppCore
import AppUI
import Foundation
import TUIKit

/// A window that shows pre-computed text lines (the Score and Multipliers windows).
@MainActor
private func drawLines(_ lines: [String], title: String, into buf: inout ScreenBuffer, rect: Rect, scroll: Int) {
    buf.fill(rect)
    Chrome.header(&buf, rect, title)
    let h = max(1, rect.h - 2)
    for (i, l) in lines.dropFirst(scroll).prefix(h).enumerated() { buf.put(" " + sanitize(l), x: rect.x, y: rect.y + 1 + i, style: .plain, clip: rect) }
    Chrome.footer(&buf, rect, "↑↓ scroll · Esc close")
}

private func contestOff(_ what: String) -> [String] {
    ["\(what) are only available in contest mode.", "Turn the contest mode on in Settings (Ctrl+P) → Contest."]
}

@MainActor
public final class ScoreScreen: OverlayScreen {
    public let title = "Score"
    private var scroll = 0
    public init() {}

    public static func lines(tally t: ScoreTally?) -> [String] {
        guard let t else { return contestOff("The score and the points") }
        var out = [t.rule.preset.title, ""]
        out.append("Band    QSOs   Dupes  Points")
        var q = 0, d = 0, p = 0
        for b in Multipliers.sortBands(Array(t.perBand.keys)) {
            guard let s = t.perBand[b] else { continue }
            out.append(b.fitted(to: 8) + String(s.qsos).fitted(to: 7) + String(s.dupes).fitted(to: 7) + String(s.points))
            q += s.qsos; d += s.dupes; p += s.points
        }
        out.append("Total".fitted(to: 8) + String(q).fitted(to: 7) + String(d).fitted(to: 7) + String(p))
        out += ["", "Multipliers: \(t.multipliers.total)", "Score: \(ScoreTally.format(t.score))"]
        if !t.rule.unverifiedNote.isEmpty { out += ["", "Note: " + t.rule.unverifiedNote] }
        out += ["", "Points: " + t.rule.pointsNote]
        return out
    }

    public func draw(into buf: inout ScreenBuffer, rect: Rect, model: AppModel) {
        drawLines(Self.lines(tally: model.score), title: "Score", into: &buf, rect: rect, scroll: scroll)
    }

    public func handle(_ e: InputEvent, model: AppModel, rect: Rect) async -> OverlayResult {
        if case .key(.escape, _) = e { return .close }
        _ = Chrome.navigate(e, selected: &scroll, count: Self.lines(tally: model.score).count, page: max(1, rect.h - 2))
        return .stay
    }
}

@MainActor
public final class MultipliersScreen: OverlayScreen {
    public let title = "Multipliers"
    private var scroll = 0
    public init() {}

    public static func lines(tally t: MultiplierTally?) -> [String] {
        guard let t else { return contestOff("The multipliers") }
        var out = [t.rule.preset.title, ""]
        for c in t.rule.components {
            let title = t.rule.title(c.kind)
            if c.perBand {
                let per = t.bands.map { "\($0) \(t.worked(c.kind, band: $0).count)" }.joined(separator: "  ")
                out.append("\(title): \(per.isEmpty ? "0" : per)")
                for b in t.bands { if let m = t.missing(c.kind, band: b), !m.isEmpty, m.count <= 40 { out.append("   \(b) missing: " + m.joined(separator: " ")) } }
            } else {
                out.append("\(title): \(t.worked(c.kind, band: nil).count)")
                if let m = t.missing(c.kind, band: nil), !m.isEmpty, m.count <= 60 { out.append("   missing: " + m.joined(separator: " ")) }
            }
        }
        out += ["", "Total: \(t.total)"]
        return out
    }

    public func draw(into buf: inout ScreenBuffer, rect: Rect, model: AppModel) {
        drawLines(Self.lines(tally: model.multipliers), title: "Multipliers", into: &buf, rect: rect, scroll: scroll)
    }

    public func handle(_ e: InputEvent, model: AppModel, rect: Rect) async -> OverlayResult {
        if case .key(.escape, _) = e { return .close }
        _ = Chrome.navigate(e, selected: &scroll, count: Self.lines(tally: model.multipliers).count, page: max(1, rect.h - 2))
        return .stay
    }
}
