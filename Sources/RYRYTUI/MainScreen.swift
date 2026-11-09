// Copyright 2026 OK1XOE (RYRY), LGPL v3
import AppUI
import Foundation
import TUIKit

/// The main window of the console version: draws the state of the `AppModel` into a `ScreenBuffer` and turns input events
/// into model calls. It does no terminal I/O, so it is testable; `TUIApp` connects it to a real terminal.
@MainActor
public final class MainScreen {
    public let model: AppModel
    public var caps: Capabilities
    public private(set) var size: (cols: Int, rows: Int)
    public var ui = UIState()
    public var tx = TxPane()
    /// Called for Ctrl+Z (the app gives the terminal back and stops itself).
    public var onSuspend: (() -> Void)?
    private let keymap = KeyMap()
    private var rxCache: (key: [Int], lines: [RxLine])?
    private var overlay: (any OverlayScreen)?

    public init(model: AppModel, caps: Capabilities, size: (cols: Int, rows: Int)) {
        self.model = model; self.caps = caps; self.size = size
    }

    public var layout: MainLayout? {
        MainLayout.compute(cols: size.cols, rows: size.rows, secondDecoder: model.settings.decoders.secondEnabled)
    }

    private var isTransmitting: Bool { model.state != .rx && model.state != .stopped }

    // MARK: drawing

    public func render(now: Date = Date()) -> ScreenBuffer {
        var buf = ScreenBuffer(width: size.cols, height: size.rows)
        if let o = overlay {
            o.draw(into: &buf, rect: Rect(0, 0, size.cols, size.rows), model: model)
            if isTransmitting {                  // a full-screen window must not hide that the transmitter is on
                buf.put(" TX ", x: max(0, size.cols / 2 - 2), y: 0, style: Style(fg: .rgb(255, 255, 255), bg: .rgb(190, 40, 40), bold: true), clip: nil)
            }
            return buf
        }
        guard let l = layout else {
            buf.put("Terminal too small (need \(MainLayout.minCols)×\(MainLayout.minRows))", x: 0, y: 0, style: Style(bold: true), clip: nil)
            buf.put("now \(size.cols)×\(size.rows)", x: 0, y: 1, style: Style(dim: true), clip: nil)
            return buf
        }
        TopBarView.draw(into: &buf, rect: l.topBar, model: model, caps: caps)
        let from = model.waterfallFromHz, to = model.waterfallToHz
        let markCol = WaterfallRaster.hzToColumn(model.mark, fromHz: from, toHz: to, cols: l.spectrum.w)
        let spaceCol = WaterfallRaster.hzToColumn(model.space, fromHz: from, toHz: to, cols: l.spectrum.w)
        blit(WaterfallRaster.spectrum(model.waterfall.spectrumLine, cols: l.spectrum.w, cellRows: l.spectrum.h, caps: caps,
                                      markCol: markCol, spaceCol: spaceCol), at: l.spectrum, into: &buf)
        let wfRows = WaterfallRaster.rows(from: model.waterfall, maxRows: l.waterfall.h * 2)
        blit(WaterfallRaster.cells(rows: wfRows, cols: l.waterfall.w, cellRows: l.waterfall.h, caps: caps), at: l.waterfall, into: &buf)
        let me = model.settings.station.call.uppercased()
        RxPane.draw(into: &buf, rect: l.rx, lines: rxLines(width: l.rx.w), scroll: ui.rxScroll,
                    highlight: { w in !me.isEmpty && w.uppercased().contains(me) ? Style(fg: .rgb(255, 220, 80), bold: true) : nil },
                    focused: ui.focus == .rx)
        buf.put(" RX ", x: l.rx.x + l.rx.w - 4, y: l.rx.y, style: Style(bold: ui.focus == .rx, dim: ui.focus != .rx, inverse: true), clip: l.rx)
        if let r = l.rx2 {
            let lines = RxPane.wrap(pieces: [(model.rx2Text, false)], width: r.w)
            RxPane.draw(into: &buf, rect: r, lines: lines, scroll: 0, highlight: { _ in nil }, focused: false)
            buf.put(" 2 ", x: r.x + r.w - 3, y: r.y, style: Style(dim: true, inverse: true), clip: r)
        }
        TxPane.draw(into: &buf, rect: l.tx, model: model, cursor: tx.cursor, focused: ui.focus == .tx)
        MacroBarView.draw(into: &buf, rect: l.macros, model: model)
        if let p = ui.prompt { drawPrompt(p, into: &buf, rect: l.status) }
        else { StatusBarView.draw(into: &buf, rect: l.status, model: model, now: now) }
        QSOPanelView.draw(into: &buf, rect: l.qso, model: model, ui: ui)
        return buf
    }

    private func blit(_ cells: [[Cell]], at r: Rect, into buf: inout ScreenBuffer) {
        for (dy, row) in cells.enumerated() { for (dx, c) in row.enumerated() where dx < r.w && dy < r.h { buf[x: r.x + dx, y: r.y + dy] = c } }
    }

    private func rxLines(width: Int) -> [RxLine] {
        let key = [model.rxAppendedTotal, model.rxTrimmedTotal, model.rxCharCount, width]
        if let c = rxCache, c.key == key { return c.lines }
        let lines = RxPane.wrap(model.rxRuns, width: width)
        rxCache = (key, lines)
        return lines
    }

    private func drawPrompt(_ p: Prompt, into buf: inout ScreenBuffer, rect: Rect) {
        let bar = Style(bold: true, inverse: true)
        buf.fill(Rect(rect.x, rect.y, rect.w, 1), style: bar)
        let title = " \(p.title): "
        buf.put(title, x: rect.x, y: rect.y, style: bar, clip: rect)
        let x0 = rect.x + title.count
        buf.put(p.editor.text, x: x0, y: rect.y, style: bar, clip: rect)
        let cx = min(rect.x + rect.w - 1, x0 + p.editor.cursor)
        var cell = buf[x: cx, y: rect.y]; cell.style = Style(bold: true, underline: true); buf[x: cx, y: rect.y] = cell
    }

    // MARK: input

    /// Returns false when the application should quit.
    public func handle(_ event: InputEvent) async -> Bool {
        if case .resize(let c, let r) = event { size = (c, r); ui.rxScroll = max(0, ui.rxScroll); return true }
        let action = keymap.action(for: event)
        if ui.prompt != nil {
            if let a = action, a == .stopRx || a == .quit || a == .suspend { return await perform(a) }
            await promptInput(event)
            return true
        }
        if let o = overlay {
            if let a = action {
                switch a {
                case .quit, .suspend, .openWindow, .windowMenu, .toggleTx, .tune, .macro: return await perform(a)
                case .stopRx where isTransmitting: await model.rxNow(); return true          // the first Esc stops the transmitter, the window stays
                default: break
                }
            }
            if await o.handle(event, model: model, rect: Rect(0, 0, size.cols, size.rows)) == .close { openOverlay(nil) }
            return true
        }
        if ui.focus == .tx, case .key(.enter, .alt) = event { _ = await tx.handle(event, model: model); return true }
        if let a = action { return await perform(a) }
        switch event {
        case .mouse(let m): await mouse(m)
        case .key, .paste: if layout != nil { await focusedInput(event) }
        default: break
        }
        return true
    }

    private func perform(_ a: Action) async -> Bool {
        switch a {
        case .toggleTx: await model.toggleTx()
        case .tune: await model.tune()
        case .stopRx:
            if ui.prompt != nil { ui.prompt = nil } else { await model.rxNow() }
        case .macro(let i): _ = await model.runMacro(i)
        case .logQSO: await model.logQSO(); syncEditor()
        case .clearQSO: await model.clearQSO(); syncEditor()
        case .openWindow(let w): openOverlay(w)
        case .windowMenu:       // for terminals without Alt: Ctrl+O steps through the windows
            let all = TUIWindow.allCases
            openOverlay(ui.window.flatMap { all.firstIndex(of: $0) }.map { all[($0 + 1) % all.count] } ?? all[0])
        case .closeWindow: openOverlay(nil)
        case .focusNext: focus(forward: true)
        case .focusPrev: focus(forward: false)
        case .settings: ui.window = nil; overlay = SettingsMenu(model: model)
        case .help: ui.window = nil; overlay = HelpScreen()
        case .quit: return false
        case .suspend:
            // never freeze the process with the transmitter keyed: go to receive first and wait until the engine really is there
            await model.rxNow()
            for _ in 0..<100 where isTransmitting { try? await Task.sleep(for: .milliseconds(20)) }
            if isTransmitting { ui.message = "Cannot suspend while transmitting" } else { onSuspend?() }
        case .freqEntry: ui.prompt = Prompt(kind: .frequency, title: "Frequency (kHz)")
        case .esmEnter: if let msg = await model.esmEnter() { ui.message = msg }
        case .rxScrollUp: ui.rxScroll += max(1, (layout?.rx.h ?? 4) / 2)
        case .rxScrollDown: ui.rxScroll = max(0, ui.rxScroll - max(1, (layout?.rx.h ?? 4) / 2))
        }
        return true
    }

    private func promptInput(_ e: InputEvent) async {
        guard var p = ui.prompt else { return }
        switch e {
        case .key(.enter, _):
            ui.prompt = nil
            if p.kind == .frequency, !p.editor.text.isEmpty { await model.setFrequency(text: p.editor.text) }
            return
        case .key(let k, let m): p.editor.handle(k, m)
        case .paste(let s): p.editor.insert(s)
        default: break
        }
        ui.prompt = p
    }

    private func openOverlay(_ w: TUIWindow?) {
        ui.window = w
        switch w {
        case .log: overlay = LogScreen()
        case .spots: overlay = SpotsScreen()
        case .bandMap: overlay = BandMapScreen()
        case .score: overlay = ScoreScreen()
        case .multipliers: overlay = MultipliersScreen()
        case nil: overlay = nil
        }
    }

    // MARK: focus and QSO fields

    private func fieldNames() -> [String] {
        QSOPanelView.fieldBoxes(model: model, rect: layout?.qso ?? Rect(66, 0, 34, 32)).map(\.field)
    }

    private func setFocus(_ f: Focus) {
        ui.focus = f
        if case .qso(let name) = f { ui.qsoEditor = LineEditor(text: model.qso.value(name) ?? "") }
    }

    private func syncEditor() { if case .qso(let name) = ui.focus { ui.qsoEditor = LineEditor(text: model.qso.value(name) ?? "") } }

    private func focus(forward: Bool) {
        let fields = fieldNames()
        switch ui.focus {
        case .tx: setFocus(forward ? .rx : (fields.last.map { .qso($0) } ?? .rx))
        case .rx: setFocus(forward ? (fields.first.map { .qso($0) } ?? .tx) : .tx)
        case .qso(let f):
            let i = fields.firstIndex(of: f) ?? 0
            if forward { setFocus(i + 1 < fields.count ? .qso(fields[i + 1]) : .tx) }
            else { setFocus(i > 0 ? .qso(fields[i - 1]) : .rx) }
        }
    }

    private func focusedInput(_ e: InputEvent) async {
        switch ui.focus {
        case .tx: _ = await tx.handle(e, model: model)
        case .rx:
            if case .key(.up, _) = e { ui.rxScroll += 1 }
            if case .key(.down, _) = e { ui.rxScroll = max(0, ui.rxScroll - 1) }
        case .qso(let f):
            let fields = fieldNames()
            let i = fields.firstIndex(of: f) ?? 0
            switch e {
            case .key(.up, _): setFocus(.qso(fields[max(0, i - 1)]))
            case .key(.down, _): setFocus(.qso(fields[min(fields.count - 1, i + 1)]))
            case .key(.enter, []):
                if model.esmActive { if let msg = await model.esmEnter() { ui.message = msg }; syncEditor() }
                else { focus(forward: true) }
            default:
                let before = ui.qsoEditor.text
                switch e {
                case .key(let k, let m): ui.qsoEditor.handle(k, m)
                case .paste(let s): ui.qsoEditor.insert(s)
                default: break
                }
                if ui.qsoEditor.text != before {
                    await model.setQSOField(f, ui.qsoEditor.text)
                    if f == "call" { model.superCheckPreview(ui.qsoEditor.text) }
                    let v = model.qso.value(f) ?? ""
                    if v != ui.qsoEditor.text { ui.qsoEditor.text = v; ui.qsoEditor.cursor = min(ui.qsoEditor.cursor, v.count) }
                }
            }
        }
    }

    // MARK: mouse

    private func mouse(_ m: MouseEvent) async {
        guard let l = layout else { return }
        if m.kind == .wheelUp || m.kind == .wheelDown {
            if l.rx.contains(x: m.x, y: m.y) { ui.rxScroll = max(0, ui.rxScroll + (m.kind == .wheelUp ? 3 : -3)) }
            return
        }
        guard m.kind == .press, m.button == .left || m.button == .right else { return }
        if l.topBar.contains(x: m.x, y: m.y) {
            if m.button == .left, let t = TopBarView.hit(x: m.x, y: m.y, rect: l.topBar, model: model, caps: caps) { await act(on: t) }
        } else if l.spectrum.contains(x: m.x, y: m.y) || l.waterfall.contains(x: m.x, y: m.y) {
            let r = l.spectrum.contains(x: m.x, y: m.y) ? l.spectrum : l.waterfall
            let hz = WaterfallRaster.columnToHz(m.x - r.x, fromHz: model.waterfallFromHz, toHz: model.waterfallToHz, cols: r.w)
            if m.button == .left { await model.tune(toMarkHz: hz) } else { await model.notchClick(hz: hz) }
        } else if l.rx.contains(x: m.x, y: m.y) {
            setFocus(.rx)
            guard m.button == .left else { return }
            let lines = rxLines(width: l.rx.w)
            let range = RxPane.visibleRange(count: lines.count, height: l.rx.h, scroll: ui.rxScroll)
            let idx = range.lowerBound + (m.y - l.rx.y)
            if range.contains(idx), let w = RxPane.word(at: m.x - l.rx.x, line: lines[idx]) { await model.insertWord(w) }
        } else if l.tx.contains(x: m.x, y: m.y) {
            setFocus(.tx)
        } else if l.macros.contains(x: m.x, y: m.y) {
            if m.button == .left, let t = MacroBarView.hit(x: m.x, y: m.y, rect: l.macros, model: model) { await act(on: t) }
        } else if l.status.contains(x: m.x, y: m.y) {
            if m.button == .left, let t = StatusBarView.hit(x: m.x, y: m.y, rect: l.status, model: model, now: Date()) { await act(on: t) }
        } else if l.qso.contains(x: m.x, y: m.y) {
            if m.button == .left, let t = QSOPanelView.hit(x: m.x, y: m.y, rect: l.qso, model: model) { await act(on: t) }
        }
    }

    private func next<T: Equatable>(after cur: T?, in list: [T]) -> T {
        guard let c = cur, let i = list.firstIndex(of: c) else { return list[0] }
        return list[(i + 1) % list.count]
    }

    private func act(on t: HitTarget) async {
        func double(_ id: String) -> Double? { if case .double(let d)? = model.param(id) { return d }; return nil }
        func flag(_ id: String) -> Bool { if case .bool(let b)? = model.param(id) { return b }; return false }
        switch t {
        case .toggleTx: await model.toggleTx()
        case .tune: await model.tune()
        case .stop: await model.rxNow()
        case .demod:
            var cur: String?
            if case .string(let s)? = model.param("demodType") { cur = s }
            await model.setParam("demodType", .string(next(after: cur, in: ["iir", "fir", "pll", "fft"])))
        case .ham: await model.hamShift()
        case .baud:
            let list = [45.45, 50, 75, 100, 110]
            let cur = double("baud").flatMap { b in list.first { abs($0 - b) < 0.01 } }
            await model.setParam("baud", .double(next(after: cur, in: list)))
        case .shift:
            let list = [170.0, 200, 425, 850]
            let cur = double("shift").flatMap { b in list.first { abs($0 - b) < 0.5 } }
            await model.setParam("shift", .double(next(after: cur, in: list)))
        case .filters: await model.setParam("bpf", .bool(!flag("bpf")))
        case .toggle(let id):
            switch id {
            case "xy": await model.setXYScope(!model.xyEnabled)
            case "second": await model.setSecondDecoder(!model.settings.decoders.secondEnabled)
            default: await model.setParam(id, .bool(!flag(id)))
            }
        case .macro(let i): _ = await model.runMacro(i)
        case .dismissMessage: model.dismissMessages()
        case .frequency: ui.prompt = Prompt(kind: .frequency, title: "Frequency (kHz)")
        case .profile, .previousQSO: break
        case .qsoField(let f): setFocus(.qso(f))
        }
    }
}
