// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Testing
@testable import TUIKit

private func caps(_ env: [String: String], tty: Bool = true) -> Capabilities { Capabilities.detect(env: env, isTTY: tty) }

@Test func truecolorFromCOLORTERM() { #expect(caps(["COLORTERM": "truecolor", "TERM": "xterm-256color"]).colorDepth == .trueColor) }
@Test func twoFiftySixFromTERM() { #expect(caps(["TERM": "xterm-256color"]).colorDepth == .ansi256) }
@Test func sixteenFromPlainXterm() { #expect(caps(["TERM": "xterm"]).colorDepth == .ansi16) }
@Test func dumbTerminalIsMono() { #expect(caps(["TERM": "dumb"]).colorDepth == .mono) }
@Test func noColorWins() { #expect(caps(["NO_COLOR": "1", "COLORTERM": "truecolor", "TERM": "xterm-256color"]).colorDepth == .mono) }
@Test func missingTermIsMono() { #expect(caps([:]).colorDepth == .mono) }
@Test func appleTerminalGets256() {
    #expect(caps(["TERM_PROGRAM": "Apple_Terminal", "TERM": "xterm"]).colorDepth == .ansi256)
}
@Test func ghosttyTermIsTrueColorOverSSH() { #expect(caps(["TERM": "xterm-ghostty"]).colorDepth == .trueColor) }
@Test func unicodeFromLocale() {
    #expect(caps(["LANG": "en_US.UTF-8", "TERM": "xterm"]).unicode)
    #expect(!caps(["LANG": "C", "TERM": "xterm"]).unicode)
    #expect(caps(["LC_ALL": "cs_CZ.UTF-8", "LANG": "C"]).unicode)          // LC_ALL has priority
}
@Test func noMouseWithoutTTY() { #expect(!caps(["TERM": "xterm"], tty: false).mouse); #expect(caps(["TERM": "xterm"]).mouse) }
@Test func overridesApply() {
    let c = caps(["COLORTERM": "truecolor", "LANG": "en_US.UTF-8", "TERM": "xterm"])
        .applying(overrides: ["colors": "16", "ascii": "1", "no-mouse": "1"])
    #expect(c.colorDepth == .ansi16 && !c.unicode && !c.mouse)
    #expect(caps(["TERM": "xterm"]).applying(overrides: ["colors": "none"]).colorDepth == .mono)
    #expect(caps(["TERM": "xterm"]).applying(overrides: ["colors": "true"]).colorDepth == .trueColor)
}
