// Copyright 2026 OK1XOE (RYRY), LGPL v3
import AppUI
import Foundation
import TUIKit

public enum OverlayResult: Equatable, Sendable { case stay, close }

/// A full-screen window over the main screen (Log, Spots, Band map, Score, Multipliers).
@MainActor
public protocol OverlayScreen: AnyObject {
    var title: String { get }
    func draw(into buf: inout ScreenBuffer, rect: Rect, model: AppModel)
    /// Esc is passed to the window first: it returns `.close` only when there is nothing to cancel.
    func handle(_ e: InputEvent, model: AppModel, rect: Rect) async -> OverlayResult
}

@MainActor
enum Chrome {
    private static let hmFormatter: DateFormatter = { let f = DateFormatter(); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "HH:mm"; return f }()
    private static let dateFormatter: DateFormatter = { let f = DateFormatter(); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "MM-dd HH:mm"; return f }()
    static func hm(_ d: Date) -> String { hmFormatter.string(from: d) }
    static func dateTime(_ d: Date) -> String { dateFormatter.string(from: d) }

    static func header(_ buf: inout ScreenBuffer, _ rect: Rect, _ text: String, right: String = "Esc close") {
        let st = Style(bold: true, inverse: true)
        buf.fill(Rect(rect.x, rect.y, rect.w, 1), style: st)
        buf.put(" " + text.ellipsized(to: max(1, rect.w - right.cellWidth - 3)), x: rect.x, y: rect.y, style: st, clip: rect)
        buf.put(right + " ", x: rect.x + rect.w - right.cellWidth - 1, y: rect.y, style: st, clip: rect)
    }

    static func footer(_ buf: inout ScreenBuffer, _ rect: Rect, _ text: String, status: String = "") {
        if !status.isEmpty { buf.put(" " + sanitize(status).ellipsized(to: rect.w - 2), x: rect.x, y: rect.y + rect.h - 2, style: Style(fg: .rgb(255, 200, 90)), clip: rect) }
        buf.fill(Rect(rect.x, rect.y + rect.h - 1, rect.w, 1), style: Style(dim: true, inverse: true))
        buf.put(" " + text.ellipsized(to: rect.w - 2), x: rect.x, y: rect.y + rect.h - 1, style: Style(dim: true, inverse: true), clip: rect)
    }

    /// Keeps `selected` in range and `top` so that it is visible.
    static func fix(selected: inout Int, top: inout Int, count: Int, height: Int) {
        selected = max(0, min(selected, count - 1))
        if selected < top { top = selected }
        if selected >= top + height { top = selected - height + 1 }
        top = max(0, min(top, max(0, count - height)))
    }

    /// Up/down/PgUp/PgDn/Home/End and the mouse wheel; true when used.
    static func navigate(_ e: InputEvent, selected: inout Int, count: Int, page: Int) -> Bool {
        switch e {
        case .key(.up, _): selected -= 1
        case .key(.down, _): selected += 1
        case .key(.pageUp, _): selected -= page
        case .key(.pageDown, _): selected += page
        case .key(.home, _): selected = 0
        case .key(.end, _): selected = count - 1
        case .mouse(let m) where m.kind == .wheelUp: selected -= 3
        case .mouse(let m) where m.kind == .wheelDown: selected += 3
        default: return false
        }
        selected = max(0, min(selected, max(0, count - 1)))
        return true
    }
}
