// Copyright 2026 OK1XOE (RYRY), LGPL v3
import AppUI
import Foundation
import QSOLog
import TUIKit

/// The Log window: search, edit, delete, import ADIF, export ADIF/Cabrillo (paths are typed with Tab completion).
@MainActor
public final class LogScreen: OverlayScreen {
    public let title = "Log"
    public private(set) var selected = 0
    private var top = 0
    private var filter = ""
    private var status = ""

    private enum Kind { case importADIF, exportCabrillo, exportADIF }
    private enum Mode { case browse, search(LineEditor), edit(field: Int, editing: LineEditor?), confirmDelete, path(Kind, PathPrompt) }
    private var mode = Mode.browse

    public init() {}

    static let fields: [(key: String, label: String)] = [
        ("call", "Call"), ("rstSent", "RST sent"), ("rstRcvd", "RST rcvd"), ("name", "Name"), ("qth", "QTH"), ("grid", "Grid"),
        ("exchangeSent", "Exch sent"), ("exchangeRcvd", "Exch rcvd"), ("comment", "Comment")]

    static func value(_ r: QSORecord, _ key: String) -> String {
        switch key {
        case "call": r.call
        case "rstSent": r.rstSent ?? ""
        case "rstRcvd": r.rstRcvd ?? ""
        case "name": r.name ?? ""
        case "qth": r.qth ?? ""
        case "grid": r.grid ?? ""
        case "exchangeSent": r.exchangeSent ?? ""
        case "exchangeRcvd": r.exchangeRcvd ?? ""
        case "comment": r.comment ?? ""
        default: ""
        }
    }

    static func set(_ r: QSORecord, _ key: String, _ v: String) -> QSORecord {
        var r = r
        let o: String? = v.isEmpty ? nil : v
        switch key {
        case "call": r.call = v.uppercased()
        case "rstSent": r.rstSent = o
        case "rstRcvd": r.rstRcvd = o
        case "name": r.name = o
        case "qth": r.qth = o
        case "grid": r.grid = o
        case "exchangeSent": r.exchangeSent = o
        case "exchangeRcvd": r.exchangeRcvd = o
        case "comment": r.comment = o
        default: break
        }
        return r
    }

    /// Newest first, filtered by the search text.
    private func records(_ model: AppModel) -> [QSORecord] {
        let all = model.logRecords.enumerated().sorted { ($0.element.timeOn, $0.offset) > ($1.element.timeOn, $1.offset) }.map(\.element)
        guard !filter.isEmpty else { return all }
        let f = filter.lowercased()
        return all.filter { r in
            [r.call, r.name ?? "", r.qth ?? "", r.exchangeRcvd ?? "", r.exchangeSent ?? "", r.comment ?? "", r.mode]
                .contains { $0.lowercased().contains(f) }
        }
    }

    private func listHeight(_ rect: Rect) -> Int {
        var edit = 0
        if case .edit = mode { edit = Self.fields.count + 1 }
        return max(1, rect.h - 4 - edit)
    }

    private func rowText(_ r: QSORecord, width: Int) -> String {
        let band = Bands.band(forHz: r.frequency) ?? ""
        func ser(_ n: Int?) -> String { n.map { String(format: "%03d", $0) } ?? "" }
        let sent = [ser(r.serialSent), r.exchangeSent ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
        let rcvd = [ser(r.serialRcvd), r.exchangeRcvd ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
        let t = Chrome.dateTime(r.timeOn).fitted(to: 12) + sanitize(r.call).fitted(to: 12) + band.fitted(to: 6) + sanitize(r.mode).fitted(to: 6)
            + "\(r.rstSent ?? "-")/\(r.rstRcvd ?? "-")".fitted(to: 9) + "S:\(sent) R:\(rcvd)"
        return sanitize(t).fitted(to: width)
    }

    public func draw(into buf: inout ScreenBuffer, rect: Rect, model: AppModel) {
        buf.fill(rect)
        let recs = records(model)
        Chrome.header(&buf, rect, "Log — \(recs.count)/\(model.logRecords.count) QSOs" + (filter.isEmpty ? "" : " · filter “\(sanitize(filter))”"))
        let h = listHeight(rect)
        Chrome.fix(selected: &selected, top: &top, count: recs.count, height: h)
        buf.put("Time        Call        Band  Mode  RST      Exchange".fitted(to: rect.w), x: rect.x, y: rect.y + 1, style: Style(bold: true, dim: true), clip: rect)
        for i in 0..<h where top + i < recs.count {
            let sel = top + i == selected
            buf.put(rowText(recs[top + i], width: rect.w), x: rect.x, y: rect.y + 2 + i, style: Style(inverse: sel), clip: rect)
        }
        if recs.isEmpty { buf.put("No QSOs", x: rect.x + 1, y: rect.y + 2, style: Style(dim: true), clip: rect) }
        var hint = "↑↓ select · Enter edit · / search · d delete · i import ADIF · e export Cabrillo · a export ADIF"
        var note = status
        switch mode {
        case .browse: break
        case .search(let ed): note = "Search: " + ed.text + "▏"; hint = "Enter apply · Esc clear"
        case .confirmDelete:
            if selected < recs.count { note = "Delete QSO with \(sanitize(recs[selected].call))? (y/n)" }
        case .path(let k, let p):
            let what = k == .importADIF ? "Import ADIF from" : k == .exportCabrillo ? "Export Cabrillo to" : "Export ADIF to"
            note = "\(what): " + p.editor.text + "▏" + (p.candidates.count > 1 ? "   [" + p.candidates.prefix(4).map { ($0 as NSString).lastPathComponent }.joined(separator: " ") + (p.candidates.count > 4 ? " …" : "") + "]" : "")
            hint = "Tab complete · Enter run · Esc cancel"
        case .edit(let f, let editing):
            hint = editing == nil ? "↑↓ field · Enter edit value · Esc back" : "type the value · Enter save · Esc cancel"
            if selected < recs.count {
                let y0 = rect.y + 2 + h
                buf.put("Edit QSO \(sanitize(recs[selected].call)):".fitted(to: rect.w), x: rect.x, y: y0, style: Style(bold: true), clip: rect)
                for (i, fld) in Self.fields.enumerated() {
                    let v = (i == f && editing != nil) ? editing!.text + "▏" : sanitize(Self.value(recs[selected], fld.key))
                    buf.put(("  " + fld.label.fitted(to: 10) + v).fitted(to: rect.w), x: rect.x, y: y0 + 1 + i, style: Style(inverse: i == f), clip: rect)
                }
            }
        }
        Chrome.footer(&buf, rect, hint, status: note)
    }

    public func handle(_ e: InputEvent, model: AppModel, rect: Rect) async -> OverlayResult {
        let recs = records(model)
        let h = listHeight(rect)
        switch mode {
        case .browse:
            status = ""
            if Chrome.navigate(e, selected: &selected, count: recs.count, page: h) { return .stay }
            switch e {
            case .key(.escape, _): return .close
            case .key(.char("/"), []): mode = .search(LineEditor(text: filter))
            case .key(.enter, []): if !recs.isEmpty { mode = .edit(field: 0, editing: nil) }
            case .key(.char("d"), []), .key(.delete, _): if !recs.isEmpty { mode = .confirmDelete }
            case .key(.char("i"), []): mode = .path(.importADIF, PathPrompt(initial: "~/"))
            case .key(.char("e"), []): mode = .path(.exportCabrillo, PathPrompt(initial: "~/"))
            case .key(.char("a"), []): mode = .path(.exportADIF, PathPrompt(initial: "~/"))
            case .mouse(let m) where m.kind == .press && m.button == .left:
                let row = top + (m.y - (rect.y + 2))
                if m.y >= rect.y + 2, row < recs.count { if row == selected, !recs.isEmpty { mode = .edit(field: 0, editing: nil) } else { selected = row } }
            default: break
            }
        case .search(var ed):
            switch e {
            case .key(.enter, _): filter = ed.text; selected = 0; top = 0; mode = .browse
            case .key(.escape, _): filter = ""; selected = 0; top = 0; mode = .browse
            case .key(let k, let m): ed.handle(k, m); mode = .search(ed)
            case .paste(let s): ed.insert(s); mode = .search(ed)
            default: break
            }
        case .confirmDelete:
            if case .key(.char("y"), _) = e, selected < recs.count { await model.deleteLog(recs[selected].id); status = "Deleted" }
            if case .key(.char(let c), _) = e, c != "y" || selected >= recs.count { mode = .browse }
            if case .key(.escape, _) = e { mode = .browse }
            if case .key(.char("y"), _) = e { mode = .browse }
        case .edit(let f, let editing):
            guard selected < recs.count else { mode = .browse; break }
            if var ed = editing {
                switch e {
                case .key(.enter, _):
                    await model.updateLog(Self.set(recs[selected], Self.fields[f].key, ed.text))
                    mode = .browse
                case .key(.escape, _): mode = .edit(field: f, editing: nil)
                case .key(let k, let m): ed.handle(k, m); mode = .edit(field: f, editing: ed)
                case .paste(let s): ed.insert(s); mode = .edit(field: f, editing: ed)
                default: break
                }
            } else {
                switch e {
                case .key(.up, _): mode = .edit(field: max(0, f - 1), editing: nil)
                case .key(.down, _): mode = .edit(field: min(Self.fields.count - 1, f + 1), editing: nil)
                case .key(.enter, _): mode = .edit(field: f, editing: LineEditor(text: Self.value(recs[selected], Self.fields[f].key)))
                case .key(.escape, _): mode = .browse
                default: break
                }
            }
        case .path(let kind, var p):
            switch e {
            case .key(.escape, _): mode = .browse
            case .key(.tab, _): p.complete(); mode = .path(kind, p)
            case .key(.enter, _):
                mode = .browse
                status = await run(kind, path: p.expanded, model: model)
            case .key(let k, let m): p.editor.handle(k, m); p.candidates = []; mode = .path(kind, p)
            case .paste(let s): p.editor.insert(s); mode = .path(kind, p)
            default: break
            }
        }
        return .stay
    }

    private func run(_ kind: Kind, path: String, model: AppModel) async -> String {
        let url = URL(fileURLWithPath: path)
        do {
            switch kind {
            case .importADIF: return try await model.importADIF(url)
            case .exportADIF: try await model.exportADIF(to: url); return "Exported ADIF to \(path)"
            case .exportCabrillo:
                try await model.cabrilloText().write(to: url, atomically: true, encoding: .utf8)
                return "Exported Cabrillo to \(path)"
            }
        } catch { return "Error: \(error.localizedDescription)" }
    }
}
