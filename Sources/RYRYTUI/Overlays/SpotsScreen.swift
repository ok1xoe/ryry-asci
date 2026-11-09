// Copyright 2026 OK1XOE (RYRY), LGPL v3
import AppUI
import Foundation
import Spots
import TUIKit

/// The Spots window: DX cluster and RBN spots; Enter (or a second click) tunes to the spot and puts its call into the QSO.
@MainActor
public final class SpotsScreen: OverlayScreen {
    public let title = "Spots"
    public private(set) var selected = 0
    private var top = 0
    public init() {}

    public func draw(into buf: inout ScreenBuffer, rect: Rect, model: AppModel) {
        buf.fill(rect)
        let spots = model.spotFeed.visible
        let modes = model.settings.spots.filter.modes == SpotFilter.allModes ? "all modes" : "RTTY only"
        Chrome.header(&buf, rect, "Spots — \(spots.count) shown · cluster \(model.spotFeed.clusterState) · RBN \(model.spotFeed.rbnState) · \(modes)")
        let h = max(1, rect.h - 3)
        Chrome.fix(selected: &selected, top: &top, count: spots.count, height: h)
        buf.put("UTC   kHz       Call        Spotter   Mode  St   Comment".fitted(to: rect.w), x: rect.x, y: rect.y + 1, style: Style(bold: true, dim: true), clip: rect)
        for i in 0..<h where top + i < spots.count {
            let s = spots[top + i]
            let st: String
            switch model.spotStatus(s) { case .new: st = "NEW"; case .worked: st = "wkd"; case .dupe: st = "dup" }
            let line = Chrome.hm(s.time).fitted(to: 6) + String(format: "%.1f", s.frequencyKHz).fitted(to: 10) + sanitize(s.call).fitted(to: 12)
                + sanitize(s.spotter).fitted(to: 10) + sanitize(s.mode ?? "").fitted(to: 6) + st.fitted(to: 5) + sanitize(s.comment)
            buf.put(line.fitted(to: rect.w), x: rect.x, y: rect.y + 2 + i, style: Style(inverse: top + i == selected), clip: rect)
        }
        if spots.isEmpty { buf.put("No spots yet (set the cluster in settings.json → spots)", x: rect.x + 1, y: rect.y + 2, style: Style(dim: true), clip: rect) }
        Chrome.footer(&buf, rect, "↑↓ select · Enter tune + call · m RTTY only / all modes · Esc close")
    }

    public func handle(_ e: InputEvent, model: AppModel, rect: Rect) async -> OverlayResult {
        let spots = model.spotFeed.visible
        let h = max(1, rect.h - 3)
        if Chrome.navigate(e, selected: &selected, count: spots.count, page: h) { return .stay }
        switch e {
        case .key(.escape, _): return .close
        case .key(.enter, _): if selected < spots.count { await model.useSpot(spots[selected]) }
        case .key(.char("m"), []):
            let all = model.settings.spots.filter.modes == SpotFilter.allModes
            model.setSpots { $0.filterModes = all ? [.rtty] : SpotFilter.allModes }
        case .mouse(let m) where m.kind == .press && m.button == .left:
            let row = top + (m.y - (rect.y + 2))
            if m.y >= rect.y + 2, row < spots.count {
                if row == selected { await model.useSpot(spots[row]) } else { selected = row }
            }
        default: break
        }
        return .stay
    }
}
