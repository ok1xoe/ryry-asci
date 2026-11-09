// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Testing
@testable import TUIKit

private func typed(_ s: String) -> LineEditor { var e = LineEditor(); for c in s { _ = e.handle(.char(c), []) }; return e }

@Test func editorInsertsAtCursor() {
    var e = typed("helo")
    _ = e.handle(.left, []); _ = e.handle(.char("l"), [])
    #expect(e.text == "hello" && e.cursor == 4)
}
@Test func editorCtrlWDeletesWord() {
    var e = typed("hello world")
    let used = e.handle(.char("w"), .ctrl)
    #expect(used)
    #expect(e.text == "hello " && e.cursor == 6)
}
@Test func editorBackspaceAtStartIsNoop() {
    var e = typed("a"); _ = e.handle(.home, [])
    _ = e.handle(.backspace, [])
    #expect(e.text == "a" && e.cursor == 0)
}
@Test func editorDeleteAndBackspace() {
    var e = typed("abc"); _ = e.handle(.left, [])
    _ = e.handle(.backspace, []); #expect(e.text == "ac" && e.cursor == 1)
    _ = e.handle(.delete, []); #expect(e.text == "a")
}
@Test func editorCtrlKAndCtrlU() {
    var e = typed("abcdef"); _ = e.handle(.left, []); _ = e.handle(.left, [])
    _ = e.handle(.char("k"), .ctrl); #expect(e.text == "abcd")
    _ = e.handle(.char("u"), .ctrl); #expect(e.text == "" && e.cursor == 0)
}
@Test func editorHomeEndAndCtrlAE() {
    var e = typed("abc")
    _ = e.handle(.char("a"), .ctrl); #expect(e.cursor == 0)
    _ = e.handle(.char("e"), .ctrl); #expect(e.cursor == 3)
    _ = e.handle(.home, []); _ = e.handle(.end, []); #expect(e.cursor == 3)
}
@Test func editorInsertSanitizesPaste() {
    var e = LineEditor(); e.insert("a\u{1B}[31mb\nc")
    #expect(e.text == "ab c")
}
@Test func editorIgnoresUnrelatedKeys() {
    var e = typed("a")
    let used = [e.handle(.f(1), []), e.handle(.up, []), e.handle(.char("t"), .ctrl), e.handle(.enter, [])]
    #expect(used == [false, false, false, false])
    #expect(e.text == "a")
}
@Test func editorCursorIsInCharactersNotBytes() {
    var e = typed("čaš"); _ = e.handle(.left, []); _ = e.handle(.backspace, [])
    #expect(e.text == "čš")
}
