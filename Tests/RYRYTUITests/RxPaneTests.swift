// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Testing
import TUIKit
@testable import AppUI
@testable import RYRYTUI

private func runs(_ parts: (String, Bool)...) -> [RxRun] { parts.enumerated().map { RxRun(id: $0.offset, text: $0.element.0, echo: $0.element.1) } }
private func plain(_ t: String) -> [RxRun] { runs((t, false)) }
private func texts(_ l: [RxLine]) -> [String] { l.map(\.plain) }
private func rowText(_ b: ScreenBuffer, _ y: Int) -> String { String((0..<b.width).map { b[x: $0, y: y].char }) }

@Test func wrapBreaksAtSpacesAndHardWrapsLongWords() {
    #expect(texts(RxPane.wrap(plain("HELLO WORLD"), width: 7)) == ["HELLO", "WORLD"])
    #expect(texts(RxPane.wrap(plain("ABCDEFGHIJ"), width: 4)) == ["ABCD", "EFGH", "IJ"])
    #expect(texts(RxPane.wrap(plain("AB CDEFGHIJ"), width: 4)) == ["AB", "CDEF", "GHIJ"])
}

@Test func wrapStartsNewLineAtNewline() {
    #expect(texts(RxPane.wrap(plain("CQ\nDE OK1XOE"), width: 20)) == ["CQ", "DE OK1XOE"])
    #expect(texts(RxPane.wrap(plain("A\r\nB"), width: 20)) == ["A", "B"])
}

@Test func wrapKeepsEchoFlagPerSegment() {
    let l = RxPane.wrap(runs(("CQ ", false), ("DE", true)), width: 20)
    #expect(l.count == 1)
    #expect(l[0].segments == [RxSegment(text: "CQ ", echo: false, startCol: 0), RxSegment(text: "DE", echo: true, startCol: 3)])
}

@Test func wrapUsesDisplayWidthForWideChars() {
    #expect(texts(RxPane.wrap(plain("漢漢漢"), width: 4)) == ["漢漢", "漢"])
}

@Test func wordAtColumnReturnsWholeWordUnderMouse() {
    let l = RxPane.wrap(plain("CQ DE OK1XOE K"), width: 40)[0]
    #expect(RxPane.word(at: 8, line: l) == "OK1XOE")
    #expect(RxPane.word(at: 3, line: l) == "DE")
    #expect(RxPane.word(at: 13, line: l) == "K")
}

@Test func wordAtSpaceOrOutsideReturnsNil() {
    let l = RxPane.wrap(plain("CQ DE OK1XOE K"), width: 40)[0]
    #expect(RxPane.word(at: 2, line: l) == nil)
    #expect(RxPane.word(at: 99, line: l) == nil)
    #expect(RxPane.word(at: -1, line: l) == nil)
}

@Test func wordSpanningRunsIsJoined() {
    let l = RxPane.wrap(runs(("OK1X", false), ("OE K", true)), width: 40)[0]
    #expect(RxPane.word(at: 1, line: l) == "OK1XOE")
    #expect(RxPane.word(at: 5, line: l) == "OK1XOE")
}

@Test func wordUnderWideCharContinuation() {
    let l = RxPane.wrap(plain("a 漢字 b"), width: 40)[0]
    #expect(RxPane.word(at: 3, line: l) == "漢字")                              // column 3 is the right half of 漢
}

@Test func drawSanitizesControlChars() {
    var b = ScreenBuffer(width: 10, height: 2)
    RxPane.draw(into: &b, rect: Rect(0, 0, 10, 2), lines: RxPane.wrap(plain("A\u{1B}[31mB\u{07}C"), width: 10), scroll: 0,
                highlight: { _ in nil }, focused: false)
    #expect(rowText(b, 0).hasPrefix("ABC") && !rowText(b, 0).contains("\u{1B}"))
}

@Test func scrollZeroShowsLastLines() {
    let lines = RxPane.wrap(plain("1\n2\n3\n4\n5"), width: 10)
    var b = ScreenBuffer(width: 10, height: 3)
    RxPane.draw(into: &b, rect: Rect(0, 0, 10, 3), lines: lines, scroll: 0, highlight: { _ in nil }, focused: false)
    #expect([0, 1, 2].map { rowText(b, $0).first! } == ["3", "4", "5"])
    var c = ScreenBuffer(width: 10, height: 3)
    RxPane.draw(into: &c, rect: Rect(0, 0, 10, 3), lines: lines, scroll: 2, highlight: { _ in nil }, focused: false)
    #expect([0, 1, 2].map { rowText(c, $0).first! } == ["1", "2", "3"])
    #expect(rowText(c, 2).contains("+2"))                                       // "scrolled back" indicator
}

@Test func shortTextIsTopAligned() {
    var b = ScreenBuffer(width: 10, height: 3)
    RxPane.draw(into: &b, rect: Rect(0, 0, 10, 3), lines: RxPane.wrap(plain("X"), width: 10), scroll: 0, highlight: { _ in nil }, focused: false)
    #expect(rowText(b, 0).first == "X" && rowText(b, 1).first == " ")
}

@Test func highlightAndEchoStylesAreApplied() {
    var b = ScreenBuffer(width: 20, height: 1)
    let hi = Style(fg: .indexed(3), bold: true)
    RxPane.draw(into: &b, rect: Rect(0, 0, 20, 1), lines: RxPane.wrap(runs(("CQ OK1XOE ", false), ("TEST", true)), width: 20), scroll: 0,
                highlight: { $0 == "OK1XOE" ? hi : nil }, focused: false)
    #expect(b[x: 3, y: 0].style == hi && b[x: 8, y: 0].style == hi)
    #expect(b[x: 0, y: 0].style != hi)
    #expect(b[x: 10, y: 0].style != b[x: 0, y: 0].style)                          // the echo has its own color
}
