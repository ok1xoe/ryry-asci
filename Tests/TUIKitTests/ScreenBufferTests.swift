// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Testing
@testable import TUIKit

private func row(_ b: ScreenBuffer, _ y: Int) -> String { String((0..<b.width).map { b[x: $0, y: y].char }) }

@Test func putClipsToRect() {
    var b = ScreenBuffer(width: 10, height: 2)
    let used = b.put("ABCDEFGH", x: 2, y: 0, style: .plain, clip: Rect(2, 0, 3, 1))
    #expect(used == 3)
    #expect(row(b, 0) == "  ABC     ")
}

@Test func wideCharTakesTwoCellsWithContinuation() {
    var b = ScreenBuffer(width: 6, height: 1)
    let used = b.put("漢a", x: 0, y: 0, style: .plain, clip: nil)
    #expect(used == 3)
    #expect(b[x: 0, y: 0].char == "漢" && !b[x: 0, y: 0].isContinuation)
    #expect(b[x: 1, y: 0].isContinuation)
    #expect(b[x: 2, y: 0].char == "a")
}

@Test func wideCharNotSplitAtClipEdge() {
    var b = ScreenBuffer(width: 6, height: 1)
    _ = b.put("a漢", x: 0, y: 0, style: .plain, clip: Rect(0, 0, 2, 1))
    #expect(b[x: 1, y: 0].char == " ")
    #expect(!b[x: 1, y: 0].isContinuation)
}

@Test func combiningMarkAttachesToPreviousCell() {
    var b = ScreenBuffer(width: 4, height: 1)
    let used = b.put("e\u{301}x", x: 0, y: 0, style: .plain, clip: nil)
    #expect(used == 2)
    #expect(b[x: 1, y: 0].char == "x")
    #expect(ScreenBuffer.displayWidth("\u{301}") == 0)
}

@Test func controlCharactersAreNotWritten() {
    var b = ScreenBuffer(width: 6, height: 1)
    _ = b.put("a\u{1B}b", x: 0, y: 0, style: .plain, clip: nil)
    #expect(!row(b, 0).contains("\u{1B}"))
}

@Test func boxAsciiUsesPlusDashPipe() {
    var b = ScreenBuffer(width: 4, height: 3)
    b.box(Rect(0, 0, 4, 3), style: .plain, ascii: true)
    #expect(row(b, 0) == "+--+")
    #expect(row(b, 1) == "|  |")
    #expect(row(b, 2) == "+--+")
}

@Test func outOfRangeSubscriptIsSafe() {
    var b = ScreenBuffer(width: 2, height: 2)
    _ = b.put("xyz", x: -1, y: 5, style: .plain, clip: nil)
    #expect(b[x: 9, y: 9] == Cell.blank)
}
