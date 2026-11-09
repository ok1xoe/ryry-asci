// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Foundation
import Testing
import TUIKit
@testable import AppUI
@testable import RYRYTUI

@Test func secondInstanceFailsWithLockMessage() {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("tui-\(UUID()).lock").path
    let first = InstanceLock(path: path)
    #expect(first != nil)
    #expect(InstanceLock(path: path) == nil)
    first?.release()
    let third = InstanceLock(path: path)
    #expect(third != nil)
    third?.release()
}

@Test func optionsAreParsed() {
    #expect(TUIOptions.parse([]) == TUIOptions())
    let o = TUIOptions.parse(["--ascii", "--colors=256", "--no-mouse"])
    #expect(o.overrides == ["ascii": "1", "colors": "256", "no-mouse": "1"] && o.error == nil && !o.help)
    #expect(TUIOptions.parse(["--help"]).help && TUIOptions.parse(["-h"]).help)
    #expect(TUIOptions.parse(["--bogus"]).error?.contains("--bogus") == true)
    #expect(TUIOptions.parse(["--colors=pink"]).error != nil)
    #expect(TUIOptions.parse(["--settings", "/tmp/x"]).settingsDir == "/tmp/x")
    #expect(TUIOptions.parse(["--settings=/tmp/y"]).settingsDir == "/tmp/y")
    #expect(TUIOptions.parse(["--settings"]).error != nil)
}

@Test func nonTTYIsRefusedWithExitCode2() {
    let r = TUIMain.preflight(options: TUIOptions(), isTTY: false)
    #expect(r?.code == 2 && r?.message.contains("interactive terminal") == true)
    #expect(TUIMain.preflight(options: TUIOptions(), isTTY: true) == nil)
    #expect(TUIMain.preflight(options: TUIOptions.parse(["--bogus"]), isTTY: true)?.code == 2)
    #expect(TUIMain.preflight(options: TUIOptions.parse(["--help"]), isTTY: false)?.code == 0)      // help works anywhere
}

@Test @MainActor func startupFailureIsReportedWhenAudioCannotStart() async {
    let bad = TUIFixture(); bad.audio.failStart = true
    await bad.model.start()
    #expect(TUIApp.startupFailure(bad.model) != nil)
    await bad.model.stop()
    let ok = TUIFixture()
    await ok.model.start()
    #expect(TUIApp.startupFailure(ok.model) == nil)
    await ok.model.stop()
}
