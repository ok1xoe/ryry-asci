// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Testing
import TUIKit
@testable import AppUI
@testable import RYRYTUI

@MainActor private func type(_ s: String, into pane: inout TxPane, model: AppModel) async {
    for ch in s { _ = await pane.handle(.key(ch == "\n" ? .enter : .char(ch), []), model: model) }
}
private func rowText(_ b: ScreenBuffer, _ y: Int) -> String { String((0..<b.width).map { b[x: $0, y: y].char }) }

@Test @MainActor func typingAddsToDraftAtCursor() async {
    let f = TUIFixture(); var pane = TxPane()
    await type("CQ DE", into: &pane, model: f.model)
    #expect(f.model.txDraft == "CQ DE" && pane.cursor == 5)
    _ = await pane.handle(.key(.left, []), model: f.model); _ = await pane.handle(.key(.char("X"), []), model: f.model)
    #expect(f.model.txDraft == "CQ DXE" && pane.cursor == 5)
}

@Test @MainActor func enterInsertsNewlineAndBackspaceRemoves() async {
    let f = TUIFixture(); var pane = TxPane()
    await type("A\nB", into: &pane, model: f.model)
    #expect(f.model.txDraft == "A\nB")
    _ = await pane.handle(.key(.backspace, []), model: f.model); _ = await pane.handle(.key(.backspace, []), model: f.model)
    #expect(f.model.txDraft == "A")
}

@Test @MainActor func upAndDownMoveBetweenLinesKeepingColumn() async {
    let f = TUIFixture(); var pane = TxPane()
    await type("ABCD\nEF\nGHIJ", into: &pane, model: f.model)
    _ = await pane.handle(.key(.up, []), model: f.model); #expect(pane.cursor == 7)          // clamped to the end of "EF"
    _ = await pane.handle(.key(.up, []), model: f.model); #expect(pane.cursor == 2)
    _ = await pane.handle(.key(.down, []), model: f.model); #expect(pane.cursor == 7)
}

@Test @MainActor func pasteKeepsNewlinesAndStripsEscapes() async {
    let f = TUIFixture(); var pane = TxPane()
    _ = await pane.handle(.paste("CQ\u{1B}[31m TEST\nDE"), model: f.model)
    #expect(f.model.txDraft == "CQ TEST\nDE")
}

@Test @MainActor func ctrlUClearsDraftAndCtrlNCyclesSendMode() async {
    let f = TUIFixture(); var pane = TxPane()
    await type("ABC", into: &pane, model: f.model)
    _ = await pane.handle(.key(.char("u"), .ctrl), model: f.model)
    #expect(f.model.txDraft == "" && pane.cursor == 0)
    #expect(f.model.sendMode == .word)
    _ = await pane.handle(.key(.char("n"), .ctrl), model: f.model); #expect(f.model.sendMode == .line)
    _ = await pane.handle(.key(.char("n"), .ctrl), model: f.model); #expect(f.model.sendMode == .char)
    _ = await pane.handle(.key(.char("n"), .ctrl), model: f.model); #expect(f.model.sendMode == .word)
}

@Test @MainActor func unrelatedKeysAreNotConsumed() async {
    let f = TUIFixture(); var pane = TxPane()
    let used = [await pane.handle(.key(.f(1), []), model: f.model), await pane.handle(.key(.char("t"), .ctrl), model: f.model),
                await pane.handle(.key(.tab, []), model: f.model), await pane.handle(.key(.escape, []), model: f.model)]
    #expect(used == [false, false, false, false])
}

@Test @MainActor func wrapColumnWrapsTypedText() async {
    let f = TUIFixture(); f.configure = { $0.txWindow.wrapColumn = 20 }
    var pane = TxPane()
    await type("AAAAAAAAA BBBBBBBBB CCCCCCCCC", into: &pane, model: f.model)
    #expect(f.model.txDraft.contains("\n"))
    #expect(f.model.txDraft.split(separator: "\n").allSatisfy { $0.count <= 20 })
}

@Test @MainActor func altEnterSendsWholeDraftAndSentTextLeavesIt() async {
    let f = TUIFixture(); var pane = TxPane()
    await f.model.start()
    await type("TEST", into: &pane, model: f.model)
    _ = await pane.handle(.key(.enter, .alt), model: f.model)
    #expect(f.model.txDraft == "" && pane.cursor == 0)
    #expect(f.model.lastSentForTesting == "TEST")
    await f.model.stop()
}

@Test @MainActor func wordModeSendsCompletedWordsWhileTransmitting() async {
    let f = TUIFixture(); var pane = TxPane()
    await f.model.start()
    await f.model.toggleTx()
    await f.pump(); await f.settle()
    f.model.sendMode = .word
    await type("CQ DE", into: &pane, model: f.model)
    #expect(f.model.lastSentForTesting == "CQ ")
    #expect(f.model.txDraft == "DE" && pane.cursor == 2)                   // the sent part left the window, the cursor followed
    await f.model.stop()
}

@Test @MainActor func drawShowsHeaderTextAndCursor() async {
    let f = TUIFixture(); var pane = TxPane()
    await type("CQ", into: &pane, model: f.model)
    var b = ScreenBuffer(width: 60, height: 4)
    TxPane.draw(into: &b, rect: Rect(0, 0, 60, 4), model: f.model, cursor: pane.cursor, focused: true)
    #expect(rowText(b, 0).contains("TX") && rowText(b, 0).contains("word"))
    #expect(rowText(b, 1).hasPrefix("CQ"))
    #expect(b[x: 2, y: 1].style.inverse && !b[x: 0, y: 1].style.inverse)
}

@Test @MainActor func longDraftScrollsToKeepCursorVisible() async {
    let f = TUIFixture(); var pane = TxPane()
    await type("1\n2\n3\n4\n5", into: &pane, model: f.model)
    var b = ScreenBuffer(width: 20, height: 4)                                // header + 3 editor rows
    TxPane.draw(into: &b, rect: Rect(0, 0, 20, 4), model: f.model, cursor: pane.cursor, focused: true)
    #expect([1, 2, 3].map { rowText(b, $0).first! } == ["3", "4", "5"])
}

@Test @MainActor func drawSanitizesDraftFromElsewhere() async {
    let f = TUIFixture()
    f.model.txDraft = "A\u{1B}[2JB"                                         // e.g. set by a macro or a message
    var b = ScreenBuffer(width: 20, height: 4)
    TxPane.draw(into: &b, rect: Rect(0, 0, 20, 4), model: f.model, cursor: 0, focused: false)
    #expect(!rowText(b, 1).contains("\u{1B}"))
}
