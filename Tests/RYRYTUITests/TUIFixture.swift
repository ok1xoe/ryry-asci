// Copyright 2026 OK1XOE (RYRY), LGPL v3
import AppCore
import AudioIO
import Engine
import Foundation
import Keying
import ModemKit
import RigControl
import RTTYModem
import RTTYSignalKit
import Settings
import TestSupport
@testable import AppUI

func tuiTempDir() -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("tui-\(UUID())")
    try! FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

/// An AppModel on a fake sound card and a manual clock (the same arrangement as the AppUI tests).
@MainActor
final class TUIFixture {
    let dir = tuiTempDir()
    let audio = FakeAudioBackend()
    let clock = ManualClock()
    var engines: [Engine] = []
    var configure: (inout AppSettings) -> Void = { _ in }
    let secrets = MemorySecretStore()
    lazy var model: AppModel = {
        var s = AppSettings()
        s.station.call = "OK1XOE"
        s.log.directory = dir.appendingPathComponent("log").path
        s.api.fldigiPort = 0; s.api.jsonRPCPort = 0
        configure(&s)
        try? SettingsStore(directory: dir).save(s)
        return AppModel(settingsStore: SettingsStore(directory: dir), profileStore: ProfileStore(directory: dir),
                        engineFactory: { [unowned self] settings, _ in
                            let e = Engine(modem: try! RTTYModem(config: settings.modemConfig()), rig: NoRig(), audio: self.audio,
                                           config: settings.engineConfig(), serialFactory: { _ in FakeSerialPort() },
                                           clock: self.clock, autoRun: false, auxModemFactory: AppModel.auxModemFactory(settings))
                            self.engines.append(e)
                            return e
                        }, spectrumFPS: 0, secrets: secrets)
    }()
    var engine: Engine { engines.last! }
    func pump(_ n: Int = 1) async { for _ in 0..<n { clock.advance(ms: 50); await engine.pump() } }
    func settle() async { for _ in 0..<5 { await Task.yield(); try? await Task.sleep(for: .milliseconds(10)) } }
}
