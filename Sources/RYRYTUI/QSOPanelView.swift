// Copyright 2026 OK1XOE (RYRY), LGPL v3
import AppCore
import AppUI
import Foundation
import QSOLog
import Settings
import TUIKit

/// The value cell of one QSO field.
public struct FieldBox: Equatable, Sendable {
    public var field: String
    public var label: String
    public var rect: Rect
}

/// The QSO panel on the right: call, exchange fields according to the contest, DXCC and beam, supercheck, frequency, previous QSOs.
@MainActor
public enum QSOPanelView {
    private static let fieldBg = Color.rgb(38, 40, 52)
    private static let focusBg = Color.rgb(62, 72, 110)

    private struct Plan {
        var boxes: [FieldBox] = []
        var texts: [(x: Int, y: Int, text: String, style: Style)] = []
        var previousStart: Int?                // the first row of the previous-QSO list
        var previousRows = 0
    }

    private static func plan(model: AppModel, rect: Rect) -> Plan {
        var p = Plan()
        let x0 = rect.x + 2, cw = max(8, rect.w - 3)
        let bottom = rect.y + rect.h
        var y = rect.y
        func line(_ text: String, style: Style = .plain, x: Int? = nil) { if y < bottom { p.texts.append((x ?? x0, y, text, style)) } }
        // title
        let c = model.settings.contest
        line("QSO", style: Style(bold: true))
        if c.enabled { p.texts.append((x0 + 4, y, sanitize(c.name.isEmpty ? "contest" : c.name).ellipsized(to: cw - 4), Style(dim: true))) }
        y += 1
        if model.esmActive { line("ESM \(model.settings.esm.mode == .run ? "run" : "s&p")", style: Style(dim: true)); y += 1 }
        for row in QSOLayout.rows(for: c) {
            guard y < bottom else { break }
            switch row {
            case .single(let field, let label):
                line(label.fitted(to: 6), style: Style(dim: true))
                let w = field == "call" ? max(3, cw - 7 - 9) : max(3, cw - 7)
                p.boxes.append(FieldBox(field: field, label: label, rect: Rect(x0 + 7, y, w, 1)))
                if field == "call" {
                    if model.isDupe { p.texts.append((x0 + 7 + w + 1, y, "DUPE", Style(fg: .rgb(255, 255, 255), bg: .rgb(190, 40, 40), bold: true))) }
                    else if !model.newMultiplier.isEmpty { p.texts.append((x0 + 7 + w + 1, y, "NEW MULT", Style(fg: .rgb(255, 255, 255), bg: .rgb(30, 130, 60), bold: true))) }
                }
                y += 1
                if field == "call", !model.scpPartial.isEmpty || !model.scpNear.isEmpty {
                    let t = ((model.scpPartial.prefix(4) + model.scpNear.prefix(3)).map { sanitize($0) }).joined(separator: " ")
                    line("SCP " + t.ellipsized(to: cw - 4), style: Style(dim: true)); y += 1
                }
            case .pair(let f1, let t1, let f2, let t2):
                let v1 = 8, v2 = max(3, cw - 6 - v1 - 1 - 6)
                line(t1.fitted(to: 6), style: Style(dim: true))
                p.boxes.append(FieldBox(field: f1, label: t1, rect: Rect(x0 + 6, y, v1, 1)))
                p.texts.append((x0 + 6 + v1 + 1, y, t2.fitted(to: 6), Style(dim: true)))
                p.boxes.append(FieldBox(field: f2, label: t2, rect: Rect(x0 + 6 + v1 + 1 + 6, y, v2, 1)))
                y += 1
            case .country:
                if let d = model.dxcc {
                    let local = Date().addingTimeInterval(d.utcOffsetHours * 3600)
                    let f = DateFormatter(); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "HH:mm"
                    let t = sanitize("\(d.name) · \(d.continent) · CQ \(d.cqZone) · ITU \(d.ituZone) · \(f.string(from: local))")
                    line(t.fitted(to: cw, pad: false), style: Style(dim: true)); y += 1
                    if t.cellWidth > cw { line(String(t.dropFirst(t.fitted(to: cw, pad: false).count)).fitted(to: cw, pad: false), style: Style(dim: true)); y += 1 }
                }
                if let b = model.beamToRemote {
                    line("az \(Int(b.shortAzimuth.rounded()) % 360)° · \(Geo.formatKm(b.shortKm)) km", style: Style(dim: true)); y += 1
                    line("long \(Int(b.longAzimuth.rounded()) % 360)° · \(Geo.formatKm(b.longKm)) km", style: Style(dim: true)); y += 1
                }
            }
        }
        // frequency
        if y < bottom {
            let hz = model.rig?.frequency ?? model.qso.frequency
            var t = "Freq  " + (hz.map { QSOFields.kHzString($0) + " kHz" } ?? "—")
            if let b = Bands.band(forHz: hz) { t += " " + b }
            line(t, style: Style(dim: true)); y += 1
        }
        if !model.callbookStatus.isEmpty, y < bottom {
            line(sanitize(model.callbookStatus).ellipsized(to: cw), style: Style(dim: true)); y += 1
        }
        // previous QSOs fill the rest
        if y + 2 < bottom, !model.previousQSOs.isEmpty {
            y += 1
            line("Previous (\(model.previousQSOs.count))", style: Style(bold: true)); y += 1
            p.previousStart = y; p.previousRows = min(model.previousQSOs.count, bottom - y)
        }
        return p
    }

    private static func previousText(_ r: QSORecord, width: Int) -> String {
        let f = DateFormatter(); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "MM-dd HH:mm"
        var t = "\(sanitize(r.call)) \(f.string(from: r.timeOn))"
        if let b = Bands.band(forHz: r.frequency) { t += " \(b)" }
        return t.ellipsized(to: width)
    }

    public static func fieldBoxes(model: AppModel, rect: Rect) -> [FieldBox] { plan(model: model, rect: rect).boxes }

    public static func draw(into buf: inout ScreenBuffer, rect: Rect, model: AppModel, ui: UIState) {
        guard rect.w >= 12, rect.h > 0 else { return }
        buf.fill(rect)
        for yy in rect.y..<(rect.y + rect.h) { buf.put("│", x: rect.x, y: yy, style: Style(dim: true), clip: rect) }
        let p = plan(model: model, rect: rect)
        for t in p.texts { buf.put(t.text, x: t.x, y: t.y, style: t.style, clip: rect) }
        for box in p.boxes {
            let focused = ui.focus == .qso(box.field)
            let value = focused ? ui.qsoEditor.text : sanitize(model.qso.value(box.field) ?? "")
            let filled = model.qso.historyFilled[box.field] == value && !value.isEmpty
            buf.fill(box.rect, style: Style(bg: focused ? focusBg : fieldBg))
            let cursor = focused ? ui.qsoEditor.cursor : 0
            let chars = Array(value)
            let start = focused ? max(0, cursor - box.rect.w + 1) : 0
            let shown = String(chars[min(start, chars.count)...]).fitted(to: box.rect.w, pad: false)
            buf.put(shown, x: box.rect.x, y: box.rect.y, style: Style(bg: focused ? focusBg : fieldBg, dim: filled), clip: box.rect)
            if focused {
                let cx = box.rect.x + min(box.rect.w - 1, cursor - start)
                var cell = buf[x: cx, y: box.rect.y]; cell.style.inverse = true; buf[x: cx, y: box.rect.y] = cell
            }
        }
        if let s = p.previousStart {
            for i in 0..<p.previousRows {
                buf.put(previousText(model.previousQSOs[i], width: rect.w - 3), x: rect.x + 2, y: s + i, style: Style(dim: true), clip: rect)
            }
        }
    }

    public static func hit(x: Int, y: Int, rect: Rect, model: AppModel) -> HitTarget? {
        let p = plan(model: model, rect: rect)
        if let b = p.boxes.first(where: { $0.rect.contains(x: x, y: y) }) { return .qsoField(b.field) }
        if let s = p.previousStart, y >= s, y < s + p.previousRows, x > rect.x { return .previousQSO(y - s) }
        return nil
    }
}
