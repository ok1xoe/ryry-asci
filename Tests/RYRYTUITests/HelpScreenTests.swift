// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Foundation
import Testing
import TUIKit
@testable import AppUI
@testable import RYRYTUI

private func key(_ k: Key, _ m: Modifiers = []) -> InputEvent { .key(k, m) }

@Test func helpListsEveryActionWithItsKey() {
    let map = KeyMap()
    let text = HelpScreen.lines(keyMap: map).joined(separator: "\n")
    for a in Action.allCases {
        let label = map.label(for: a)
        #expect(text.contains(label), "help does not show \(label) for \(a)")
    }
    #expect(HelpScreen.lines(keyMap: map).contains { $0.localizedCaseInsensitiveContains("mouse") })
}

@Test func everyActionHasADescription() {
    for a in Action.allCases { #expect(!HelpScreen.describe(a).isEmpty, "\(a)") }
}

@Test @MainActor func helpScrollsAndEscCloses() async {
    let f = TUIFixture()
    let h = HelpScreen()
    var b = ScreenBuffer(width: 100, height: 10)
    h.draw(into: &b, rect: Rect(0, 0, 100, 10), model: f.model)
    let first = (0..<10).map { y in String((0..<100).map { b[x: $0, y: y].char }) }.joined()
    #expect(first.contains("Keys"))
    for _ in 0..<5 { _ = await h.handle(key(.pageDown), model: f.model, rect: Rect(0, 0, 100, 10)) }
    var c = ScreenBuffer(width: 100, height: 10)
    h.draw(into: &c, rect: Rect(0, 0, 100, 10), model: f.model)
    #expect(b != c)
    #expect(await h.handle(key(.escape), model: f.model, rect: Rect(0, 0, 100, 10)) == .close)
}

@Test @MainActor func ctrlGOpensHelpFromTheMainScreen() async {
    let f = TUIFixture(); await f.model.start()
    let s = MainScreen(model: f.model, caps: Capabilities(colorDepth: .trueColor, unicode: true, mouse: true), size: (100, 40))
    _ = await s.handle(key(.char("g"), .ctrl))
    let b = s.render(now: Date())
    #expect((0..<40).contains { y in String((0..<100).map { b[x: $0, y: y].char }).contains("Ctrl+Q") })
    _ = await s.handle(key(.escape))
    let after = s.render(now: Date())
    #expect((0..<40).contains { y in String((0..<100).map { after[x: $0, y: y].char }).contains("[TX]") })
    await f.model.stop()
}
