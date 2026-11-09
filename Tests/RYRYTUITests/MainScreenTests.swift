// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Engine
import Foundation
import Settings
import Testing
import TUIKit
@testable import AppUI
@testable import RYRYTUI

private let caps = Capabilities(colorDepth: .trueColor, unicode: true, mouse: true)
private func rowText(_ b: ScreenBuffer, _ y: Int) -> String { String((0..<b.width).map { b[x: $0, y: y].char }) }
private func allText(_ b: ScreenBuffer) -> String { (0..<b.height).map { rowText(b, $0) }.joined(separator: "\n") }
private func click(_ x: Int, _ y: Int, _ b: MouseEvent.Button = .left) -> InputEvent { .mouse(MouseEvent(kind: .press, button: b, x: x, y: y, mods: [])) }
private func key(_ k: Key, _ m: Modifiers = []) -> InputEvent { .key(k, m) }

@MainActor private func screen(_ f: TUIFixture, cols: Int = 100, rows: Int = 32) async -> MainScreen {
    await f.model.start()
    let s = MainScreen(model: f.model, caps: caps, size: (cols, rows))
    _ = s.render(now: Date(timeIntervalSince1970: 1_000_000))
    return s
}

@Test @MainActor func rendersTheWholeMainWindow() async {
    let f = TUIFixture(); let s = await screen(f)
    let b = s.render(now: Date(timeIntervalSince1970: 1_000_000))
    #expect(b.width == 100 && b.height == 32)
    let t = allText(b)
    #expect(t.contains("[TX]") && t.contains("Baud") && t.contains("QSO") && t.contains("Macros:") && t.contains(" TX "))
    #expect(b == s.render(now: Date(timeIntervalSince1970: 1_000_000)))              // the same state draws the same picture
    await f.model.stop()
}

@Test @MainActor func clickOnRxWordInsertsCallIntoQSO() async {
    let f = TUIFixture(); let s = await screen(f)
    f.model.appendRx("CQ DE OK1XOE K", echo: false)
    _ = s.render(now: Date())
    let rx = s.layout!.rx
    #expect(await s.handle(click(rx.x + 8, rx.y)))
    #expect(f.model.qso.call == "OK1XOE")
    await f.model.stop()
}

@Test @MainActor func clickOnSpectrumTunesMarkAndRightClickAddsNotch() async {
    let f = TUIFixture(); let s = await screen(f)
    let sp = s.layout!.spectrum
    let col = sp.w / 2
    _ = await s.handle(click(sp.x + col, sp.y))
    await f.settle()
    let hz = WaterfallRaster.columnToHz(col, fromHz: f.model.waterfallFromHz, toHz: f.model.waterfallToHz, cols: sp.w)
    #expect(abs(f.model.mark - hz) < 60, "mark \(f.model.mark) expected near \(hz)")
    let wf = s.layout!.waterfall
    _ = await s.handle(click(wf.x + 3, wf.y, .right))
    await f.settle()
    #expect(!f.model.notchMarkers.isEmpty)
    await f.model.stop()
}

@Test @MainActor func clickOnMacroRunsMacro() async {
    let f = TUIFixture(); f.configure = { $0.macros = [Macro(name: "CQ", text: "CQ CQ DE %m")] }
    let s = await screen(f)
    let m = s.layout!.macros
    _ = await s.handle(click(m.x + 1, m.y))
    for _ in 0..<400 { await f.pump(); if await f.engine.state == .rx { break } }          // until the transmission has finished
    await f.settle()
    #expect(f.model.rxRuns.filter(\.echo).map(\.text).joined().contains("CQ CQ DE OK1XOE"))
    await f.model.stop()
}

@Test @MainActor func functionKeyRunsMacroToo() async {
    let f = TUIFixture(); f.configure = { $0.macros = [Macro(name: "CQ", text: "CQ CQ DE %m")] }
    let s = await screen(f)
    _ = await s.handle(key(.f(1)))
    for _ in 0..<400 { await f.pump(); if await f.engine.state == .rx { break } }          // until the transmission has finished
    await f.settle()
    #expect(f.model.rxRuns.filter(\.echo).map(\.text).joined().contains("CQ CQ DE OK1XOE"))
    await f.model.stop()
}

@Test @MainActor func tabCyclesFocusTxRxQsoFieldsAndBack() async {
    let f = TUIFixture(); let s = await screen(f)
    #expect(s.ui.focus == .tx)
    _ = await s.handle(key(.tab)); #expect(s.ui.focus == .rx)
    _ = await s.handle(key(.tab)); #expect(s.ui.focus == .qso("call"))
    _ = await s.handle(key(.tab)); #expect(s.ui.focus == .qso("name"))
    for _ in 0..<5 { _ = await s.handle(key(.tab)) }
    #expect(s.ui.focus == .qso("notes"))
    _ = await s.handle(key(.tab)); #expect(s.ui.focus == .tx)
    _ = await s.handle(key(.backTab)); #expect(s.ui.focus == .qso("notes"))
    await f.model.stop()
}

@Test @MainActor func typingGoesToTheFocusedPane() async {
    let f = TUIFixture(); let s = await screen(f)
    _ = await s.handle(key(.char("A")))
    #expect(f.model.txDraft == "A")
    _ = await s.handle(click(s.layout!.qso.x + 12, s.layout!.qso.y + 1))            // the Call field (row after the title)
    #expect(s.ui.focus == .qso("call"))
    for ch in "DL1ABC" { _ = await s.handle(key(.char(ch))) }
    #expect(f.model.qso.call == "DL1ABC")
    #expect(f.model.txDraft == "A")                                                  // nothing leaked into the TX pane
    await f.model.stop()
}

@Test @MainActor func belowMinimumShowsTooSmallMessageAndRecoversOnResize() async {
    let f = TUIFixture(); let s = await screen(f, cols: 80, rows: 24)
    #expect(s.layout == nil)
    #expect(allText(s.render(now: Date())).contains("too small"))
    _ = await s.handle(.resize(cols: 110, rows: 40))
    #expect(s.size.cols == 110 && s.size.rows == 40)
    let b = s.render(now: Date())
    #expect(b.width == 110 && allText(b).contains("[TX]"))
    await f.model.stop()
}

@Test @MainActor func wheelScrollsRxAndPageDownReturnsToLive() async {
    let f = TUIFixture(); let s = await screen(f)
    f.model.appendRx((1...60).map { "LINE\($0)" }.joined(separator: "\n"), echo: false)
    _ = s.render(now: Date())
    let rx = s.layout!.rx
    _ = await s.handle(.mouse(MouseEvent(kind: .wheelUp, button: .none, x: rx.x + 2, y: rx.y + 2, mods: [])))
    #expect(s.ui.rxScroll > 0)
    for _ in 0..<50 { _ = await s.handle(key(.pageDown)) }
    #expect(s.ui.rxScroll == 0)
    _ = await s.handle(key(.pageUp)); #expect(s.ui.rxScroll > 0)
    await f.model.stop()
}

@Test @MainActor func ctrlQQuitsAndNothingElseDoes() async {
    let f = TUIFixture(); let s = await screen(f)
    #expect(await s.handle(key(.char("a"))))
    #expect(await s.handle(key(.escape)))
    #expect(await s.handle(key(.char("q"), .ctrl)) == false)
    await f.model.stop()
}

@Test @MainActor func altFOpensFrequencyPromptThatEscCancels() async {
    let f = TUIFixture(); let s = await screen(f)
    _ = await s.handle(key(.char("f"), .alt))
    #expect(s.ui.prompt != nil)
    #expect(allText(s.render(now: Date())).contains("Frequency"))
    _ = await s.handle(key(.char("x")))
    #expect(f.model.txDraft == "")                                                    // typing went to the prompt
    _ = await s.handle(key(.escape))
    #expect(s.ui.prompt == nil)
    await f.model.stop()
}

@Test @MainActor func statusBarOkDismissesMessage() async {
    let f = TUIFixture(); let s = await screen(f)
    f.model.noteForTesting("Something failed")
    let r = s.layout!.status
    let b = s.render(now: Date())
    let x = (0..<b.width).first { rowText(b, r.y).dropFirst($0).hasPrefix("[OK]") }!
    _ = await s.handle(click(x, r.y))
    #expect(f.model.messages.isEmpty)
    await f.model.stop()
}

@Test @MainActor func toggleClicksChangeParameters() async {
    let f = TUIFixture(); let s = await screen(f)
    let items = TopBarView.items(model: f.model, rect: s.layout!.topBar, caps: caps)
    let afc = items.first { $0.target == .toggle("afc") }!
    let before = f.model.param("afc")
    _ = await s.handle(click(afc.x, afc.y)); await f.settle()
    #expect(f.model.param("afc") != before)
    await f.model.stop()
}

@Test @MainActor func resizeBelowMinimumKeepsWorking() async {
    let f = TUIFixture(); let s = await screen(f)
    _ = await s.handle(.resize(cols: 20, rows: 5))
    let b = s.render(now: Date())
    #expect(b.width == 20 && b.height == 5)
    _ = await s.handle(click(3, 3))                                                    // clicking the notice is harmless
    await f.model.stop()
}

// MARK: review fixes

@MainActor private func transmitting(_ f: TUIFixture, _ s: MainScreen) async {
    await f.model.toggleTx()
    for _ in 0..<20 { await f.pump(); if f.model.state != .rx { break } }
    await f.settle()
}

@Test @MainActor func suspendWhileTransmittingFirstReturnsToReceive() async {
    let f = TUIFixture(); let s = await screen(f)
    await transmitting(f, s)
    #expect(f.model.state != .rx && f.model.state != .stopped)
    var stateAtSuspend: EngineState?
    s.onSuspend = { stateAtSuspend = f.model.state }
    let pumper = Task { @MainActor in for _ in 0..<150 { await f.pump(); try? await Task.sleep(for: .milliseconds(10)) } }
    _ = await s.handle(key(.char("z"), .ctrl))
    pumper.cancel()
    #expect(stateAtSuspend == .rx || stateAtSuspend == .stopped, "suspended with the transmitter keyed: \(String(describing: stateAtSuspend))")
    await f.model.stop()
}

@Test @MainActor func suspendWhileReceivingSuspendsAtOnce() async {
    let f = TUIFixture(); let s = await screen(f)
    var called = false
    s.onSuspend = { called = true }
    _ = await s.handle(key(.char("z"), .ctrl))
    #expect(called)
    await f.model.stop()
}

@Test @MainActor func escInAWindowFirstStopsTheTransmissionAndKeepsTheWindow() async {
    let f = TUIFixture(); let s = await screen(f)
    await transmitting(f, s)
    _ = await s.handle(key(.char("l"), .alt))
    #expect(s.ui.window == .log)
    #expect(allText(s.render(now: Date())).contains(" TX "))                          // the full-screen window still shows that we transmit
    _ = await s.handle(key(.escape))
    for _ in 0..<60 { await f.pump(); if await f.engine.state == .rx { break } }
    await f.settle()
    #expect(await f.engine.state == .rx)
    #expect(s.ui.window == .log)                                                      // the first Esc stopped the TX only
    _ = await s.handle(key(.escape))
    #expect(s.ui.window == nil)
    await f.model.stop()
}

@Test @MainActor func txKeysWorkInsideAWindow() async {
    let f = TUIFixture(); f.configure = { $0.macros = [Macro(name: "CQ", text: "CQ CQ DE %m")] }
    let s = await screen(f)
    _ = await s.handle(key(.char("s"), .alt))
    #expect(s.ui.window == .spots)
    _ = await s.handle(key(.f(1)))
    for _ in 0..<400 { await f.pump(); if await f.engine.state == .rx { break } }
    await f.settle()
    #expect(f.model.rxRuns.filter(\.echo).map(\.text).joined().contains("CQ CQ DE OK1XOE"))
    #expect(s.ui.window == .spots)
    await f.model.stop()
}
