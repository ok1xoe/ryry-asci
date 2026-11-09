// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Testing
import TUIKit
@testable import RYRYTUI

private let map = KeyMap()
private func ev(_ k: Key, _ m: Modifiers = []) -> InputEvent { .key(k, m) }

@Test func f1ToF12MapToMacro0to11() { for n in 1...12 { #expect(map.action(for: ev(.f(n))) == .macro(n - 1)) } }

@Test func shiftF1AndAlt1BothMapToMacro12() {
    for n in 1...4 {
        #expect(map.action(for: ev(.f(n), .shift)) == .macro(11 + n))
        #expect(map.action(for: ev(.char(Character("\(n)")), .alt)) == .macro(11 + n))
    }
}
@Test func ctrlTTogglesTx() { #expect(map.action(for: ev(.char("t"), .ctrl)) == .toggleTx) }
@Test func escapeStopsRx() { #expect(map.action(for: ev(.escape)) == .stopRx) }
@Test func ctrlLLogsQSO() { #expect(map.action(for: ev(.char("l"), .ctrl)) == .logQSO) }
@Test func altLetterOpensWindows() {
    #expect(map.action(for: ev(.char("l"), .alt)) == .openWindow(.log))
    #expect(map.action(for: ev(.char("s"), .alt)) == .openWindow(.spots))
    #expect(map.action(for: ev(.char("b"), .alt)) == .openWindow(.bandMap))
    #expect(map.action(for: ev(.char("c"), .alt)) == .openWindow(.score))
    #expect(map.action(for: ev(.char("m"), .alt)) == .openWindow(.multipliers))
    #expect(map.action(for: ev(.char("L"), [.alt, .shift])) == .openWindow(.log))      // caps lock / shift is ignored
}
@Test func ctrlKeysForMenusAndQuit() {
    #expect(map.action(for: ev(.char("o"), .ctrl)) == .windowMenu)
    #expect(map.action(for: ev(.char("p"), .ctrl)) == .settings)
    #expect(map.action(for: ev(.char("g"), .ctrl)) == .help)
    #expect(map.action(for: ev(.char("q"), .ctrl)) == .quit)
    #expect(map.action(for: ev(.char("z"), .ctrl)) == .suspend)
}
@Test func focusAndScrollKeys() {
    #expect(map.action(for: ev(.tab)) == .focusNext)
    #expect(map.action(for: ev(.backTab)) == .focusPrev)
    #expect(map.action(for: ev(.pageUp)) == .rxScrollUp)
    #expect(map.action(for: ev(.pageDown)) == .rxScrollDown)
}
@Test func otherAltShortcuts() {
    #expect(map.action(for: ev(.char("t"), .alt)) == .tune)
    #expect(map.action(for: ev(.char("x"), .alt)) == .clearQSO)
    #expect(map.action(for: ev(.char("f"), .alt)) == .freqEntry)
    #expect(map.action(for: ev(.enter, .alt)) == .esmEnter)
}
@Test func plainCharactersAreNotActions() {
    #expect(map.action(for: ev(.char("a"))) == nil)
    #expect(map.action(for: ev(.char("t"))) == nil)
    #expect(map.action(for: .paste("x")) == nil)
}
@Test func everyActionHasLabelAndNoKeyIsBoundTwice() {
    for a in Action.allCases { #expect(!map.label(for: a).isEmpty, "\(a)") }
    #expect(Action.allCases.count == Set(Action.allCases).count)
    #expect(map.hasDuplicateKeys == false)
    #expect(map.label(for: .toggleTx).contains("Ctrl+T"))
    #expect(map.label(for: .macro(12)).contains("⇧F1") && map.label(for: .macro(12)).contains("Alt+1"))
}
