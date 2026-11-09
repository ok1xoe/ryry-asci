// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Foundation
import Testing
import TUIKit
import Settings
@testable import AppUI
@testable import RYRYTUI

private let caps = Capabilities(colorDepth: .trueColor, unicode: true, mouse: true)
private func rowText(_ b: ScreenBuffer, _ y: Int) -> String { String((0..<b.width).map { b[x: $0, y: y].char }) }
private func allText(_ b: ScreenBuffer) -> String { (0..<b.height).map { rowText(b, $0) }.joined(separator: "\n") }
private let main = Rect(0, 0, 66, 2)

// MARK: top bar

@Test @MainActor func topBarShowsTxStateAndControls() {
    let f = TUIFixture()
    var b = ScreenBuffer(width: 66, height: 2)
    TopBarView.draw(into: &b, rect: main, model: f.model, caps: caps)
    #expect(rowText(b, 0).contains("[TX]") && rowText(b, 0).contains("[Tune]") && rowText(b, 0).contains("[Stop]"))
    #expect(rowText(b, 0).contains("STOP"))                                  // the engine is not running
    #expect(rowText(b, 1).contains("Baud") && rowText(b, 1).contains("Shift") && rowText(b, 1).contains("LTRS"))
    #expect(["AFC", "NET", "REV", "ATC"].allSatisfy { rowText(b, 1).contains($0) })
}

@Test @MainActor func topBarHitTestReturnsTargets() {
    let f = TUIFixture()
    for target in [HitTarget.toggleTx, .tune, .stop, .ham, .toggle("afc"), .toggle("net"), .baud, .shift, .demod] {
        guard let item = TopBarView.items(model: f.model, rect: main, caps: caps).first(where: { $0.target == target }) else {
            Issue.record("missing \(target)"); continue
        }
        #expect(TopBarView.hit(x: item.x, y: item.y, rect: main, model: f.model, caps: caps) == target)
        #expect(TopBarView.hit(x: item.x + item.width - 1, y: item.y, rect: main, model: f.model, caps: caps) == target)
    }
    #expect(TopBarView.hit(x: 65, y: 5, rect: main, model: f.model, caps: caps) == nil)
}

@Test @MainActor func topBarItemsStayInsideTheRect() {
    let f = TUIFixture()
    for item in TopBarView.items(model: f.model, rect: main, caps: caps) { #expect(item.x >= 0 && item.x + item.width <= 66, "\(item.text)") }
}

@Test func signalMeterGrowsWithLevel() {
    #expect(TopBarView.meter(level: 0, open: true, width: 4, unicode: true).count == 4)
    let low = TopBarView.meter(level: 10, open: true, width: 8, unicode: true)
    let high = TopBarView.meter(level: 5000, open: true, width: 8, unicode: true)
    #expect(low != high)
    #expect(TopBarView.meter(level: 5000, open: true, width: 8, unicode: false).allSatisfy { $0.isASCII })
}

// MARK: macros

@Test @MainActor func macroBarShowsSixteenLabelsInTwoRows() {
    let f = TUIFixture()
    f.configure = { $0.macros = (0..<16).map { Macro(name: "M\($0)", text: "T\($0)") } }
    var b = ScreenBuffer(width: 66, height: 2)
    MacroBarView.draw(into: &b, rect: Rect(0, 0, 66, 2), model: f.model)
    #expect(["F1", "F5", "F8"].allSatisfy { rowText(b, 0).contains($0) })
    #expect(["F9", "F12", "⇧F1", "⇧F4"].allSatisfy { rowText(b, 1).contains($0) })
}

@Test @MainActor func macroBarHitTestReturnsIndexAndSkipsEmptyOnes() {
    let f = TUIFixture()
    f.configure = { $0.macros = [Macro(name: "CQ", text: "CQ CQ"), Macro(name: "B", text: "B"), Macro(name: "E", text: "")] }
    let r = Rect(0, 0, 66, 2)
    let w = 66 / 8
    #expect(MacroBarView.hit(x: 0, y: 0, rect: r, model: f.model) == .macro(0))
    #expect(MacroBarView.hit(x: w + 1, y: 0, rect: r, model: f.model) == .macro(1))
    #expect(MacroBarView.hit(x: 2 * w + 1, y: 0, rect: r, model: f.model) == nil)          // empty text
    #expect(MacroBarView.hit(x: 5, y: 1, rect: r, model: f.model) == nil)                  // no macro in slot 8
    #expect(MacroBarView.hit(x: 0, y: 7, rect: r, model: f.model) == nil)
}

@Test @MainActor func macroButtonUsesItsColor() {
    let f = TUIFixture()
    f.configure = { $0.macros = [Macro(name: "CQ", text: "CQ", color: "#FF0000")] }
    var b = ScreenBuffer(width: 66, height: 2)
    MacroBarView.draw(into: &b, rect: Rect(0, 0, 66, 2), model: f.model)
    #expect(b[x: 1, y: 0].style.bg == .rgb(255, 0, 0))
}

// MARK: status bar

@Test @MainActor func statusBarShowsContestRateAndMessages() {
    let plain = TUIFixture()
    var b = ScreenBuffer(width: 66, height: 1)
    StatusBarView.draw(into: &b, rect: Rect(0, 0, 66, 1), model: plain.model, now: Date(timeIntervalSince1970: 1_000_000))
    #expect(!rowText(b, 0).contains("QSO "))
    let c = TUIFixture(); c.configure = { $0.contest.enabled = true }
    var b2 = ScreenBuffer(width: 66, height: 1)
    StatusBarView.draw(into: &b2, rect: Rect(0, 0, 66, 1), model: c.model, now: Date(timeIntervalSince1970: 1_000_000))
    #expect(rowText(b2, 0).contains("QSO 0") && rowText(b2, 0).contains("10m"))
}

@Test @MainActor func statusBarShowsMessageWithDismissTarget() {
    let f = TUIFixture()
    f.model.noteForTesting("Audio failed\u{1B}[2J")
    var b = ScreenBuffer(width: 66, height: 1)
    StatusBarView.draw(into: &b, rect: Rect(0, 0, 66, 1), model: f.model, now: Date())
    #expect(rowText(b, 0).contains("Audio failed") && rowText(b, 0).contains("[OK]"))
    #expect(!rowText(b, 0).contains("\u{1B}"))
    let ok = StatusBarView.items(model: f.model, rect: Rect(0, 0, 66, 1), now: Date()).first { $0.target == .dismissMessage }
    #expect(ok != nil)
    #expect(StatusBarView.hit(x: ok!.x, y: 0, rect: Rect(0, 0, 66, 1), model: f.model, now: Date()) == .dismissMessage)
}

// MARK: QSO panel

private let panel = Rect(66, 0, 34, 32)

@Test @MainActor func qsoPanelShowsFieldsAndCall() async {
    let f = TUIFixture(); await f.model.start()
    await f.model.setQSOField("call", "DL1ABC")
    var b = ScreenBuffer(width: 100, height: 32)
    QSOPanelView.draw(into: &b, rect: panel, model: f.model, ui: UIState())
    let t = allText(b)
    #expect(t.contains("QSO") && t.contains("Call") && t.contains("DL1ABC") && t.contains("RST s") && t.contains("599"))
    await f.model.stop()
}

@Test @MainActor func qsoPanelFieldBoxesAndHitTest() {
    let f = TUIFixture()
    let boxes = QSOPanelView.fieldBoxes(model: f.model, rect: panel)
    #expect(boxes.map(\.field) == ["call", "name", "qth", "locator", "rstSent", "rstRcvd", "notes"])
    for box in boxes {
        #expect(panel.contains(x: box.rect.x, y: box.rect.y) && box.rect.x + box.rect.w <= 100)
        #expect(QSOPanelView.hit(x: box.rect.x, y: box.rect.y, rect: panel, model: f.model) == .qsoField(box.field))
    }
    #expect(QSOPanelView.hit(x: 66, y: 31, rect: panel, model: f.model) == nil)
}

@Test @MainActor func qsoPanelContestFieldsFollowTheFormat() {
    let f = TUIFixture(); f.configure = { $0.contest.enabled = true }
    let fields = QSOPanelView.fieldBoxes(model: f.model, rect: panel).map(\.field)
    #expect(fields.contains("serialSent") && fields.contains("serialRcvd") && !fields.contains("name"))
}

@Test @MainActor func qsoPanelSanitizesFieldsAndCallbookStatus() async {
    let f = TUIFixture(); await f.model.start()
    await f.model.setQSOField("name", "A\u{1B}[2JB")
    var b = ScreenBuffer(width: 100, height: 32)
    QSOPanelView.draw(into: &b, rect: panel, model: f.model, ui: UIState())
    #expect(!allText(b).contains("\u{1B}"))
    await f.model.stop()
}

@Test @MainActor func qsoPanelHighlightsTheFocusedFieldWithCursor() async {
    let f = TUIFixture(); await f.model.start()
    await f.model.setQSOField("call", "DL1")
    var ui = UIState(); ui.focus = .qso("call"); ui.qsoEditor = LineEditor(text: "DL1")
    var b = ScreenBuffer(width: 100, height: 32)
    QSOPanelView.draw(into: &b, rect: panel, model: f.model, ui: ui)
    let box = QSOPanelView.fieldBoxes(model: f.model, rect: panel).first { $0.field == "call" }!
    #expect(b[x: box.rect.x + 3, y: box.rect.y].style.inverse)               // the cursor behind "DL1"
    #expect(!b[x: box.rect.x, y: box.rect.y].style.inverse)
    await f.model.stop()
}

@Test @MainActor func qsoPanelTooShortStillDrawsWithoutCrashing() {
    let f = TUIFixture()
    var b = ScreenBuffer(width: 100, height: 8)
    QSOPanelView.draw(into: &b, rect: Rect(66, 0, 34, 8), model: f.model, ui: UIState())
    #expect(allText(b).contains("QSO"))
}
