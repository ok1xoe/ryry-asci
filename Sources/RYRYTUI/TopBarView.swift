// Copyright 2026 OK1XOE (RYRY), LGPL v3
import AppCore
import AppUI
import Engine
import Foundation
import QSOLog
import TUIKit

/// The two rows above the spectrum: TX/RX, Tune, Stop, state, demodulator, frequency, signal meter / baud, shift, filters, switches.
@MainActor
public enum TopBarView {
    static func stateLabel(_ s: EngineState) -> String {
        switch s {
        case .stopped: "STOP"
        case .rx: "RX"
        case .keying: "PTT…"
        case .pttOn: "PTT"
        case .tx: "TX"
        case .drain: "TX…"
        case .pttOff: "PTT↓"
        }
    }

    nonisolated static func meter(level: Double, open: Bool, width: Int, unicode: Bool) -> String {
        let frac = min(1, max(0, log10(max(level, 1)) / 4))
        let filled = Int((frac * Double(width)).rounded())
        return String(repeating: unicode ? "█" : "#", count: filled) + String(repeating: unicode ? "░" : "-", count: max(0, width - filled))
    }

    private static func on(_ model: AppModel, _ id: String) -> Bool { if case .bool(let b)? = model.param(id) { return b }; return false }

    static func filterLabel(_ model: AppModel) -> String {
        var a: [String] = []
        if on(model, "bpf") { a.append("BPF") }
        if on(model, "lms") { a.append(model.param("lmsType") == .string("lms") ? "LMS" : "NOT") }
        if on(model, "aa6yq") { a.append("AA6YQ") }
        if on(model, "uos") { a.append("UOS") }
        return "[" + (a.isEmpty ? "Filters" : a.joined(separator: "+")).ellipsized(to: 9) + "]"
    }

    public static func items(model: AppModel, rect: Rect, caps: Capabilities) -> [ViewItem] {
        let button = Style(bold: true, inverse: true)
        let transmitting = model.state != .rx && model.state != .stopped
        // row 0
        var l0 = RowBuilder(y: rect.y, x: rect.x)
        l0.add(transmitting ? "[RX]" : "[TX]", style: button, target: .toggleTx); l0.gap()
        l0.add("[Tune]", style: button, target: .tune); l0.gap()
        l0.add("[Stop]", style: button, target: .stop); l0.gap()
        let badge: Color = model.state == .rx ? .rgb(30, 120, 50) : model.state == .stopped ? .rgb(90, 90, 90) : .rgb(170, 40, 40)
        l0.add(" \(stateLabel(model.state)) ", style: Style(fg: .rgb(255, 255, 255), bg: badge, bold: true)); l0.gap()
        var demod = "IIR"
        if case .string(let s)? = model.param("demodType") { demod = s.uppercased() }
        l0.add("[\(demod)]", style: button, target: .demod); l0.gap()
        l0.add("[HAM]", style: button, target: .ham); l0.gap()
        l0.add("[Prof]", style: button, target: .profile)
        // frequency and signal meter on the right (dropped when they do not fit)
        let hz = model.rig?.frequency ?? model.qso.frequency
        var freq = hz.map { QSOFields.kHzString($0) } ?? "—"
        if let b = Bands.band(forHz: hz) { freq += " " + b }
        if let r = model.rig, !r.online { freq += " ?" }
        var right: [(String, Style, HitTarget?)] = [(freq, Style(bold: true), .frequency),
            (TopBarView.meter(level: model.signalLevel, open: model.squelchOpen, width: 6, unicode: caps.unicode),
             Style(fg: model.squelchOpen ? .rgb(90, 220, 110) : .rgb(130, 130, 130)), nil)]
        let items0 = place(left: l0.items, right: &right, y: rect.y, rect: rect)
        // row 1
        var l1 = RowBuilder(y: rect.y + 1, x: rect.x)
        var baud = "45.45"
        if case .double(let d)? = model.param("baud") { baud = String(format: "%g", d) }
        var shift = "170"
        if case .double(let d)? = model.param("shift") { shift = String(format: "%g", d) }
        l1.add("Baud \(baud)", target: .baud); l1.gap()
        l1.add("Shift \(shift)", target: .shift); l1.gap()
        l1.add(model.fig ? "FIGS" : "LTRS", style: model.fig ? Style(fg: .rgb(255, 170, 60), bold: true) : Style(dim: true)); l1.gap()
        l1.add(filterLabel(model), target: .filters)
        func sw(_ label: String, _ id: String, _ isOn: Bool) -> (String, Style, HitTarget?) {
            (label, isOn ? Style(fg: .rgb(255, 255, 255), bg: .rgb(30, 120, 50), bold: true) : Style(dim: true), .toggle(id))
        }
        var toggles: [(String, Style, HitTarget?)] = [sw("XY", "xy", model.xyEnabled), sw("2D", "second", model.settings.decoders.secondEnabled),
            sw("AFC", "afc", on(model, "afc")), sw("NET", "net", on(model, "net")), sw("REV", "reverse", on(model, "reverse")),
            sw("ATC", "atc", on(model, "atc")), sw("SQ", "squelch", on(model, "squelch"))]
        let items1 = place(left: l1.items, right: &toggles, y: rect.y + 1, rect: rect)
        return items0 + items1
    }

    /// Puts the right-aligned group after the left items; items that would collide are dropped (the last ones first).
    private static func place(left: [ViewItem], right: inout [(String, Style, HitTarget?)], y: Int, rect: Rect) -> [ViewItem] {
        let leftEnd = (left.last.map { $0.x + $0.width }) ?? rect.x
        func width(_ r: [(String, Style, HitTarget?)]) -> Int { r.reduce(0) { $0 + $1.0.cellWidth } + max(0, r.count - 1) }
        while !right.isEmpty, rect.x + rect.w - width(right) < leftEnd + 1 { right.removeLast() }
        var out = left
        var x = rect.x + rect.w - width(right)
        for r in right { let it = ViewItem(text: r.0, x: x, y: y, style: r.1, target: r.2); out.append(it); x += it.width + 1 }
        return out.filter { $0.x >= rect.x && $0.x + $0.width <= rect.x + rect.w }
    }

    public static func draw(into buf: inout ScreenBuffer, rect: Rect, model: AppModel, caps: Capabilities) {
        buf.fill(Rect(rect.x, rect.y, rect.w, 2))
        ItemRow.draw(items(model: model, rect: rect, caps: caps), into: &buf, clip: rect)
    }

    public static func hit(x: Int, y: Int, rect: Rect, model: AppModel, caps: Capabilities) -> HitTarget? {
        ItemRow.hit(items(model: model, rect: rect, caps: caps), x: x, y: y)
    }
}
