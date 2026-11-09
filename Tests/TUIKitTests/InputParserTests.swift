// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Testing
@testable import TUIKit

private let ESC: UInt8 = 0x1B
private func bytes(_ s: String) -> [UInt8] { Array(s.utf8) }
private func parse(_ s: String) -> [InputEvent] { var p = InputParser(); return p.feed(bytes(s)) }
private func key(_ k: Key, _ m: Modifiers = []) -> InputEvent { .key(k, m) }

@Test func functionKeysSS3AndTilde() {
    #expect(parse("\u{1B}OP") == [key(.f(1))])
    #expect(parse("\u{1B}[11~") == [key(.f(1))])
    #expect(parse("\u{1B}[24~") == [key(.f(12))])
    #expect(parse("\u{1B}[19~") == [key(.f(8))])
}

@Test func shiftF1ToF4AndShiftF5() {
    #expect(parse("\u{1B}[1;2P") == [key(.f(1), .shift)])
    #expect(parse("\u{1B}[1;2Q") == [key(.f(2), .shift)])
    #expect(parse("\u{1B}[1;2R") == [key(.f(3), .shift)])
    #expect(parse("\u{1B}[1;2S") == [key(.f(4), .shift)])
    #expect(parse("\u{1B}[15;2~") == [key(.f(5), .shift)])
    #expect(parse("\u{1B}O2P") == [key(.f(1), .shift)])
}

@Test func arrowsAndModifiers() {
    #expect(parse("\u{1B}[A") == [key(.up)])
    #expect(parse("\u{1B}[1;5C") == [key(.right, .ctrl)])
    #expect(parse("\u{1B}OD") == [key(.left)])
    #expect(parse("\u{1B}[H") == [key(.home)])
    #expect(parse("\u{1B}[3~") == [key(.delete)])
    #expect(parse("\u{1B}[5~") == [key(.pageUp)])
}

@Test func controlAndAltAndSimpleKeys() {
    #expect(parse("\u{14}") == [key(.char("t"), .ctrl)])
    #expect(parse("\u{1B}1") == [key(.char("1"), .alt)])
    #expect(parse("\u{7F}") == [key(.backspace)])
    #expect(parse("\r") == [key(.enter)])
    #expect(parse("\t") == [key(.tab)])
    #expect(parse("\u{1B}[Z") == [key(.backTab)])
    #expect(parse("aB") == [key(.char("a")), key(.char("B"))])
}

@Test func sgrMouse() {
    #expect(parse("\u{1B}[<0;10;5M") == [.mouse(MouseEvent(kind: .press, button: .left, x: 9, y: 4, mods: []))])
    #expect(parse("\u{1B}[<0;10;5m") == [.mouse(MouseEvent(kind: .release, button: .left, x: 9, y: 4, mods: []))])
    #expect(parse("\u{1B}[<2;1;1M") == [.mouse(MouseEvent(kind: .press, button: .right, x: 0, y: 0, mods: []))])
    #expect(parse("\u{1B}[<64;10;5M") == [.mouse(MouseEvent(kind: .wheelUp, button: .none, x: 9, y: 4, mods: []))])
    #expect(parse("\u{1B}[<65;10;5M") == [.mouse(MouseEvent(kind: .wheelDown, button: .none, x: 9, y: 4, mods: []))])
    #expect(parse("\u{1B}[<32;3;3M") == [.mouse(MouseEvent(kind: .drag, button: .left, x: 2, y: 2, mods: []))])
    #expect(parse("\u{1B}[<4;3;3M") == [.mouse(MouseEvent(kind: .press, button: .left, x: 2, y: 2, mods: .shift))])
}

@Test func bracketedPasteEvenWhenSplit() {
    #expect(parse("\u{1B}[200~hello\nworld\u{1B}[201~") == [.paste("hello\nworld")])
    var p = InputParser()
    #expect(p.feed(bytes("\u{1B}[200~he")).isEmpty)
    #expect(p.feed(bytes("llo\u{1B}[20")).isEmpty)
    #expect(p.feed(bytes("1~x")) == [.paste("hello"), key(.char("x"))])
}

@Test func utf8SplitAcrossFeeds() {
    var p = InputParser()
    #expect(p.feed([0xC4]).isEmpty)
    #expect(p.feed([0x8D]) == [key(.char("č"))])
}

@Test func loneEscapeWaitsAndFlushes() {
    var p = InputParser()
    #expect(p.feed([ESC]).isEmpty)
    #expect(p.flushPendingEscape() == [key(.escape)])
    #expect(p.flushPendingEscape().isEmpty)
}

@Test func escapeFollowedByBracketSequenceIsNotEscape() {
    var p = InputParser()
    #expect(p.feed([ESC]).isEmpty)
    #expect(p.feed(bytes("[A")) == [key(.up)])
}

@Test func unknownSequenceIsDroppedAndDoesNotBlock() {
    #expect(parse("\u{1B}[999~a") == [key(.char("a"))])
    #expect(parse("\u{1B}[?9999zb") == [key(.char("b"))])
    var p = InputParser()
    #expect(p.feed([0xFF, 0x63]) == [key(.char("c"))])        // invalid UTF-8 lead byte
}

@Test func unterminatedPasteIsDroppedAfterTheCapAndInputWorksAgain() {
    var p = InputParser()
    #expect(p.feed(bytes("\u{1B}[200~")).isEmpty)
    let chunk = [UInt8](repeating: 0x41, count: 256 * 1024)
    for _ in 0..<5 { _ = p.feed(chunk) }                                    // 1.25 MB and the end marker never comes
    #expect(p.feed(bytes("x")) == [key(.char("x"))])
    #expect(p.flushPendingEscape().isEmpty)
}
