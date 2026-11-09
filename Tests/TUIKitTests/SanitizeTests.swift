// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Testing
@testable import TUIKit

@Test func sanitizeStripsCSIAndOSC() {
    #expect(sanitize("A\u{1B}[31mB\u{1B}]0;x\u{07}C") == "ABC")
    #expect(sanitize("A\u{1B}]0;title\u{1B}\\B") == "AB")                 // OSC terminated by ST
    #expect(sanitize("A\u{1B}[?1049hB") == "AB")
}
@Test func sanitizeKeepsDiacritics() { #expect(sanitize("Příliš žluťoučký kůň") == "Příliš žluťoučký kůň") }
@Test func sanitizeDropsC1AndDelAndNul() { #expect(sanitize("\u{9B}31m\u{7F}x\u{0}") == "31mx") }
@Test func sanitizeDropsUnterminatedEscapeAtTheEnd() { #expect(sanitize("ab\u{1B}") == "ab"); #expect(sanitize("ab\u{1B}[3") == "ab") }
@Test func sanitizeTabsAndNewlines() {
    #expect(sanitize("a\tb") == "a b")
    #expect(sanitize("a\r\nb") == "a b")
    #expect(sanitize("a\r\nb", keepNewlines: true) == "a\nb")
}
@Test func sanitizeEscapeThenPlainCharDropsBoth() { #expect(sanitize("a\u{1B}cb") == "ab") }
