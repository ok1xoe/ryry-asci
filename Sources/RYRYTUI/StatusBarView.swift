// Copyright 2026 OK1XOE (RYRY), LGPL v3
import AppCore
import AppUI
import Foundation
import TUIKit

/// The bottom row: the last warning (with [OK]) or the macro set; in a contest the rate and score; the API status.
@MainActor
public enum StatusBarView {
    private static let bg = Color.rgb(40, 40, 48)

    public static func items(model: AppModel, rect: Rect, now: Date) -> [ViewItem] {
        var parts: [String] = []
        if model.settings.contest.enabled {
            let st = model.logStats(now: now)
            parts.append("QSO \(st.total) · 10m: \(st.rate10)/h · 60m: \(st.rate60)/h")
            if let s = model.score { parts.append("Score \(ScoreTally.format(s.score))") }
        }
        if !model.apiStatus.isEmpty { parts.append(sanitize(model.apiStatus)) }
        let right = parts.joined(separator: " · ").ellipsized(to: rect.w / 2)
        var out: [ViewItem] = []
        let room = rect.w - right.cellWidth - 1
        var l = RowBuilder(y: rect.y, x: rect.x + 1)
        if let m = model.messages.last {
            l.add("⚠ " + sanitize(m).ellipsized(to: max(4, room - 8)), style: Style(fg: .rgb(255, 180, 60), bg: bg)); l.gap()
            l.add("[OK]", style: Style(bold: true, inverse: true), target: .dismissMessage)
        } else {
            l.add("Macros: " + sanitize(model.macroSetTitle).ellipsized(to: max(4, room - 8)), style: Style(bg: bg, dim: true))
        }
        out += l.items
        if !right.isEmpty { out.append(ViewItem(text: right, x: rect.x + rect.w - right.cellWidth - 1, y: rect.y, style: Style(fg: .rgb(170, 175, 190), bg: bg), target: nil)) }
        return out
    }

    public static func draw(into buf: inout ScreenBuffer, rect: Rect, model: AppModel, now: Date) {
        buf.fill(Rect(rect.x, rect.y, rect.w, 1), style: Style(bg: bg))
        ItemRow.draw(items(model: model, rect: rect, now: now), into: &buf, clip: rect)
    }

    public static func hit(x: Int, y: Int, rect: Rect, model: AppModel, now: Date) -> HitTarget? {
        ItemRow.hit(items(model: model, rect: rect, now: now), x: x, y: y)
    }
}
