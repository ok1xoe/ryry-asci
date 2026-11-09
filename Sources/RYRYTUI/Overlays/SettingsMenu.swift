// Copyright 2026 OK1XOE (RYRY), LGPL v3
import AppUI
import AudioIO
import Foundation
import Keying
import RigControl
import Settings
import TUIKit

/// The simple settings menu: station, audio, rig and PTT, contest, macros. Everything else stays in `settings.json`.
/// Changes are made on a copy and applied with `s` (or the Save row); Esc throws them away.
@MainActor
public final class SettingsMenu: OverlayScreen {
    public let title = "Settings"
    private let model: AppModel
    private var draft: AppSettings
    private let original: AppSettings
    private var sel = 0
    private var top = 0
    private var status = ""

    private typealias Apply = (inout AppSettings) -> Void
    private enum Row {
        case header(String)
        case choice(String, current: (AppSettings) -> String, options: (AppSettings) -> [(String, Apply)])
        case text(String, get: (AppSettings) -> String, set: (inout AppSettings, String) -> Void)
        case toggle(String, WritableKeyPath<AppSettings, Bool>)
        case macro(Int)
        case save

        var label: String? {
            switch self {
            case .header: nil
            case .choice(let l, _, _), .text(let l, _, _), .toggle(let l, _): l
            case .macro(let i): "Macro " + (i < 12 ? "F\(i + 1)" : "⇧F\(i - 11)")
            case .save: "Save and apply"
            }
        }
        var selectable: Bool { if case .header = self { return false }; return true }
    }

    private enum Edit { case text(LineEditor, set: (inout AppSettings, String) -> Void), macroName(Int, LineEditor), macroText(Int, String, LineEditor) }
    private var edit: Edit?
    private var rows: [Row] = []

    public init(model: AppModel) {
        self.model = model
        draft = model.settings; original = model.settings
        rows = Self.buildRows(model: model)
        sel = rows.firstIndex { $0.selectable } ?? 0
    }

    private static func buildRows(model: AppModel) -> [Row] {
        let devices = AudioDevices.all()
        let ins = devices.filter { $0.inputChannels > 0 }, outs = devices.filter { $0.outputChannels > 0 }
        func deviceRow(_ label: String, _ list: [AudioDevice], uid: KeyPath<AppSettings, String?>, set: WritableKeyPath<AppSettings, String?>) -> Row {
            .choice(label, current: { s in s[keyPath: uid].map { u in list.first { $0.uid == u }?.name ?? u } ?? "(system default)" },
                    options: { _ in
                        var o: [(String, Apply)] = [("(system default)", { $0[keyPath: set] = nil })]
                        for d in list { o.append((d.name, { $0[keyPath: set] = d.uid })) }
                        return o
                    })
        }
        func enumRow<T: RawRepresentable & CaseIterable>(_ label: String, _ kp: WritableKeyPath<AppSettings, T>) -> Row where T.RawValue == String {
            .choice(label, current: { $0[keyPath: kp].rawValue }, options: { _ in T.allCases.map { c in (c.rawValue, { $0[keyPath: kp] = c }) } })
        }
        var r: [Row] = [
            .header("Station"),
            .text("Call", get: { $0.station.call }, set: { $0.station.call = $1.uppercased() }),
            .text("Locator", get: { $0.station.locator }, set: { $0.station.locator = $1.uppercased() }),
            .text("Name", get: { $0.station.name }, set: { $0.station.name = $1 }),
            .text("QTH", get: { $0.station.qth }, set: { $0.station.qth = $1 }),
            .header("Audio"),
            deviceRow("Input device", ins, uid: \.audio.inputUID, set: \.audio.inputUID),
            deviceRow("Output device", outs, uid: \.audio.outputUID, set: \.audio.outputUID),
            enumRow("Input channel", \.audio.inputChannel),
            .header("Rig and PTT"),
            enumRow("Rig type", \.rig.type),
            .text("Host", get: { $0.rig.host }, set: { $0.rig.host = $1 }),
            .text("Port", get: { $0.rig.port.map(String.init) ?? "" }, set: { $0.rig.port = Int($1) }),
            .text("Serial port", get: { $0.rig.serialPort }, set: { $0.rig.serialPort = $1 }),
            enumRow("CAT protocol", \.rig.catProtocol),
            enumRow("PTT method", \.ptt.method),
            .text("PTT port", get: { $0.ptt.port ?? "" }, set: { $0.ptt.port = $1.isEmpty ? nil : $1 }),
            .header("Contest"),
            .toggle("Contest mode", \.contest.enabled),
            .choice("Preset", current: { $0.contest.selectedPreset?.title ?? "(custom)" }, options: { _ in
                var o: [(String, Apply)] = [("(custom)", { $0.contest.preset = nil })]
                for p in ContestPreset.allCases {
                    o.append((p.title, { s in
                        let serial = s.contest.nextSerial
                        let ex = MainActor.assumeIsolated { model.defaultContestExchange(p, station: s.station) }       // the menu only runs on the main actor
                        s.contest = ContestSettings.upcoming(p, locator: s.station.locator, exchange: ex)
                        if p == .waeRTTY { s.contest.nextSerial = max(1, serial) }
                    }))
                }
                return o
            }),
            .text("Exchange", get: { $0.contest.exchange }, set: { $0.contest.exchange = $1 }),
            .header("Macros (name, then text)"),
        ]
        for i in 0..<16 { r.append(.macro(i)) }
        r.append(.header("")); r.append(.save)
        return r
    }

    // MARK: access for tests and mouse handling

    @discardableResult func select(_ label: String) -> Bool {
        guard let i = rows.firstIndex(where: { $0.label == label }) else { return false }
        sel = i; return true
    }
    var selectedLabel: String? { rows.indices.contains(sel) ? rows[sel].label : nil }

    // MARK: drawing

    private func value(_ row: Row) -> String {
        switch row {
        case .header, .save: return ""
        case .choice(_, let cur, _): return "◂ " + cur(draft) + " ▸"
        case .text(_, let get, _): return get(draft)
        case .toggle(_, let kp): return draft[keyPath: kp] ? "[x] on" : "[ ] off"
        case .macro(let i):
            guard i < draft.macros.count else { return "—" }
            return draft.macros[i].name + " · " + draft.macros[i].text
        }
    }

    public func draw(into buf: inout ScreenBuffer, rect: Rect, model: AppModel) {
        buf.fill(rect)
        Chrome.header(&buf, rect, "Settings", right: "s save · Esc cancel")
        let h = max(1, rect.h - 3)
        Chrome.fix(selected: &sel, top: &top, count: rows.count, height: h)
        for i in 0..<h where top + i < rows.count {
            let row = rows[top + i]
            let y = rect.y + 1 + i
            if case .header(let t) = row { buf.put(t, x: rect.x + 1, y: y, style: Style(fg: .rgb(120, 200, 255), bold: true), clip: rect); continue }
            let selected = top + i == sel
            var shown = sanitize(value(row))
            if selected, let e = edit {
                switch e {
                case .text(let ed, _), .macroName(_, let ed), .macroText(_, _, let ed): shown = ed.text + "▏"
                }
            }
            let label: String = {
                if case .macro = row, selected, let e = edit { if case .macroText = e { return (row.label ?? "") + " text" }; return (row.label ?? "") + " name" }
                return row.label ?? ""
            }()
            buf.put(("  " + label.fitted(to: 18) + shown).fitted(to: rect.w), x: rect.x, y: y, style: Style(inverse: selected), clip: rect)
        }
        var hint = "↑↓ move · Enter/→ change · ← back · s save · Esc discard"
        if edit != nil { hint = "type the value · Enter accept · Esc cancel" }
        Chrome.footer(&buf, rect, hint, status: status)
    }

    // MARK: input

    private func move(_ d: Int) {
        var i = sel
        while true {
            let n = i + d
            guard rows.indices.contains(n) else { return }
            i = n
            if rows[i].selectable { sel = i; return }
        }
    }

    public func handle(_ e: InputEvent, model: AppModel, rect: Rect) async -> OverlayResult {
        status = ""
        if edit != nil { handleEdit(e); return .stay }
        switch e {
        case .key(.escape, _): return .close
        case .key(.up, _): move(-1)
        case .key(.down, _): move(1)
        case .key(.pageUp, _): for _ in 0..<max(1, rect.h - 3) { move(-1) }
        case .key(.pageDown, _): for _ in 0..<max(1, rect.h - 3) { move(1) }
        case .key(.home, _): sel = rows.firstIndex { $0.selectable } ?? 0
        case .key(.end, _): sel = rows.lastIndex { $0.selectable } ?? 0
        case .mouse(let m) where m.kind == .wheelUp: for _ in 0..<3 { move(-1) }
        case .mouse(let m) where m.kind == .wheelDown: for _ in 0..<3 { move(1) }
        case .key(.char("s"), []), .key(.char("s"), .ctrl):
            await save(); return .close
        case .key(.left, _): step(-1)
        case .key(.right, _): step(1)
        case .key(.enter, _), .key(.char(" "), []):
            if case .save = rows[sel] { await save(); return .close }
            activate()
        case .mouse(let m) where m.kind == .press && m.button == .left:
            let i = top + (m.y - (rect.y + 1))
            if m.y >= rect.y + 1, rows.indices.contains(i), rows[i].selectable {
                if i == sel { if case .save = rows[sel] { await save(); return .close }; activate() } else { sel = i }
            }
        default: break
        }
        return .stay
    }

    /// ←/→ on choices (and toggles).
    private func step(_ d: Int) {
        switch rows[sel] {
        case .choice(_, let cur, let options):
            let opts = options(draft)
            guard !opts.isEmpty else { return }
            let i = opts.firstIndex { $0.0 == cur(draft) } ?? (d > 0 ? -1 : 0)
            opts[((i + d) % opts.count + opts.count) % opts.count].1(&draft)
        case .toggle(_, let kp): draft[keyPath: kp].toggle()
        default: break
        }
    }

    private func activate() {
        switch rows[sel] {
        case .choice, .toggle: step(1)
        case .text(_, let get, let set): edit = .text(LineEditor(text: get(draft)), set: set)
        case .macro(let i): edit = .macroName(i, LineEditor(text: i < draft.macros.count ? draft.macros[i].name : ""))
        default: break
        }
    }

    private func handleEdit(_ e: InputEvent) {
        guard let cur = edit else { return }
        if case .key(.escape, _) = e { edit = nil; return }
        func feed(_ ed: LineEditor) -> LineEditor { var x = ed; switch e { case .key(let k, let m): x.handle(k, m); case .paste(let s): x.insert(s); default: break }; return x }
        switch cur {
        case .text(let ed, let set):
            if case .key(.enter, _) = e { set(&draft, ed.text); edit = nil } else { edit = .text(feed(ed), set: set) }
        case .macroName(let i, let ed):
            if case .key(.enter, _) = e { edit = .macroText(i, ed.text, LineEditor(text: i < draft.macros.count ? draft.macros[i].text : "")) }
            else { edit = .macroName(i, feed(ed)) }
        case .macroText(let i, let name, let ed):
            if case .key(.enter, _) = e {
                while draft.macros.count <= i { draft.macros.append(Macro(name: "", text: "")) }
                let old = draft.macros[i]
                draft.macros[i] = Macro(name: name, text: ed.text, repeatSeconds: old.repeatSeconds, color: old.color)
                edit = nil
            } else { edit = .macroText(i, name, feed(ed)) }
        }
    }

    private func save() async {
        let before = try? Data(contentsOf: model.settingsURL)
        await model.applySettings(draft, baseline: original)
        if draft.macros != original.macros { await model.saveMacros(draft.macros) }
        SettingsPreserver.reinjectUnknown(before: before, url: model.settingsURL)
    }
}
