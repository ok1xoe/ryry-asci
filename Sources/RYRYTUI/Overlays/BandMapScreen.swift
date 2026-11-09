// Copyright 2026 OK1XOE (RYRY), LGPL v3
import AppUI
import Foundation
import TUIKit

/// The Band map: the spots around the rig as positions in the 0–4000 Hz audio range, with the mark and space tones.
@MainActor
public final class BandMapScreen: OverlayScreen {
    public let title = "Band map"
    public private(set) var selected = 0
    private var top = 0
    private nonisolated static let maxHz = 4000.0
    public init() {}

    public nonisolated static func rulerColumn(audioHz: Double, width: Int) -> Int {
        guard width > 1 else { return 0 }
        return min(width - 1, max(0, Int((audioHz / maxHz * Double(width - 1)).rounded())))
    }

    private func markers(_ model: AppModel) -> [BandMapMarker] { model.bandMapMarkers.sorted { $0.audioHz < $1.audioHz } }

    public func draw(into buf: inout ScreenBuffer, rect: Rect, model: AppModel) {
        buf.fill(rect)
        Chrome.header(&buf, rect, "Band map — spots as audio offsets around the rig")
        let w = max(20, min(60, rect.w - 40))
        var ruler = [Character](repeating: "-", count: w)
        ruler[Self.rulerColumn(audioHz: model.mark, width: w)] = "M"
        ruler[Self.rulerColumn(audioHz: model.space, width: w)] = "S"
        buf.put("[" + String(ruler) + "]", x: rect.x + 1, y: rect.y + 2, style: Style(fg: .rgb(120, 200, 255)), clip: rect)
        buf.put("0 Hz", x: rect.x + 2, y: rect.y + 3, style: Style(dim: true), clip: rect)
        buf.put("4000 Hz", x: rect.x + 2 + w - 7, y: rect.y + 3, style: Style(dim: true), clip: rect)
        let list = markers(model)
        let h = max(1, rect.h - 7)
        Chrome.fix(selected: &selected, top: &top, count: list.count, height: h)
        for i in 0..<h where top + i < list.count {
            let m = list[top + i]
            var r = [Character](repeating: "·", count: w)
            r[Self.rulerColumn(audioHz: m.audioHz, width: w)] = "▲"
            let st: String
            switch m.status { case .new: st = "NEW"; case .worked: st = "wkd"; case .dupe: st = "dup" }
            let line = "[" + String(r) + "] " + String(format: "%4.0f Hz  ", m.audioHz) + sanitize(m.spot.call).fitted(to: 11) + st
            buf.put(line.fitted(to: rect.w - 1), x: rect.x + 1, y: rect.y + 5 + i, style: Style(inverse: top + i == selected), clip: rect)
        }
        if list.isEmpty { buf.put("No spots in the band map (the rig frequency and the spot filter decide)", x: rect.x + 1, y: rect.y + 5, style: Style(dim: true), clip: rect) }
        Chrome.footer(&buf, rect, "↑↓ select · Enter / click tune + call · Esc close")
    }

    public func handle(_ e: InputEvent, model: AppModel, rect: Rect) async -> OverlayResult {
        let list = markers(model)
        if Chrome.navigate(e, selected: &selected, count: list.count, page: max(1, rect.h - 7)) { return .stay }
        switch e {
        case .key(.escape, _): return .close
        case .key(.enter, _): if selected < list.count { await model.bandMapClick(list[selected]) }
        case .mouse(let m) where m.kind == .press && m.button == .left:
            let row = top + (m.y - (rect.y + 5))
            if m.y >= rect.y + 5, row < list.count { selected = row; await model.bandMapClick(list[row]) }
        default: break
        }
        return .stay
    }
}
