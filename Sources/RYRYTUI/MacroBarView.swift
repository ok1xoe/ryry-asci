// Copyright 2026 OK1XOE (RYRY), LGPL v3
import AppUI
import Settings
import TUIKit

/// The 16 macro buttons in two rows of eight (F1–F12, then ⇧F1–⇧F4), colored like the GUI buttons.
@MainActor
public enum MacroBarView {
    static func keyLabel(_ i: Int) -> String { i < 12 ? "F\(i + 1)" : "⇧F\(i - 11)" }

    public static func items(model: AppModel, rect: Rect) -> [ViewItem] {
        let macros = model.settings.macros
        let slot = max(2, rect.w / 8)
        var out: [ViewItem] = []
        for row in 0..<2 { for col in 0..<8 {
            let i = row * 8 + col
            let x = rect.x + col * slot, y = rect.y + row
            guard x + slot - 1 <= rect.x + rect.w else { continue }
            let m: Macro? = i < macros.count ? macros[i] : nil
            let usable = m.map { !$0.text.isEmpty } ?? false
            var style: Style = Style(dim: true)
            if usable {
                if let (r, g, b) = parseHexColor(m?.color) {
                    let light = (Int(r) * 299 + Int(g) * 587 + Int(b) * 114) / 1000 > 140
                    style = Style(fg: light ? .rgb(0, 0, 0) : .rgb(255, 255, 255), bg: .rgb(r, g, b))
                } else {
                    style = Style(fg: .rgb(235, 235, 245), bg: .rgb(55, 60, 85))
                }
            }
            let label = m.map { "\(keyLabel(i)) \(sanitize($0.name))" } ?? keyLabel(i)
            out.append(ViewItem(text: label.fitted(to: slot - 1), x: x, y: y, style: style, target: usable ? .macro(i) : nil))
        } }
        return out
    }

    public static func draw(into buf: inout ScreenBuffer, rect: Rect, model: AppModel) {
        buf.fill(Rect(rect.x, rect.y, rect.w, 2))
        ItemRow.draw(items(model: model, rect: rect), into: &buf, clip: rect)
    }

    public static func hit(x: Int, y: Int, rect: Rect, model: AppModel) -> HitTarget? {
        ItemRow.hit(items(model: model, rect: rect), x: x, y: y)
    }
}
