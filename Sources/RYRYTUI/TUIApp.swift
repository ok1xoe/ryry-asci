// Copyright 2026 OK1XOE (RYRY), LGPL v3
import AppUI
import Darwin
import Foundation
import Settings
import TUIKit

/// An exclusive lock file: the console version and the GUI/other instances must not fight over the sound card and ports.
public final class InstanceLock {
    private var fd: Int32
    public init?(path: String) {
        let f = open(path, O_CREAT | O_RDWR, 0o644)
        guard f >= 0 else { return nil }
        guard flock(f, LOCK_EX | LOCK_NB) == 0 else { close(f); return nil }
        fd = f
    }
    public func release() { if fd >= 0 { flock(fd, LOCK_UN); close(fd); fd = -1 } }
    deinit { release() }
}

public struct TUIOptions: Equatable, Sendable {
    public var overrides: [String: String] = [:]
    public var help = false
    public var error: String?
    /// A different settings folder (default: the one the other RYRY tools use).
    public var settingsDir: String?
    public init() {}

    public static let usage = """
        ryry-tui – RYRY in the terminal (ASCII art interface)

        Usage: ryry-tui [--ascii] [--colors=none|16|256|true] [--no-mouse] [--settings DIR] [--help]

          --ascii            only plain ASCII characters (no half blocks, no box drawing)
          --colors=MODE      force the number of colors (default: detected from COLORTERM/TERM)
          --no-mouse         do not ask the terminal for mouse events
          --settings DIR     use another settings folder (settings.json, log, lock file)
          -h, --help         this text

        Press Ctrl+G inside the program for the list of keys, Ctrl+Q quits.
        """

    public static func parse(_ args: [String]) -> TUIOptions {
        var o = TUIOptions()
        var it = args.makeIterator()
        while let a = it.next() {
            switch a {
            case "--settings":
                if let d = it.next() { o.settingsDir = d } else { o.error = "--settings needs a folder" }
            case "--help", "-h": o.help = true
            case "--ascii": o.overrides["ascii"] = "1"
            case "--no-mouse": o.overrides["no-mouse"] = "1"
            default:
                if a.hasPrefix("--settings=") { o.settingsDir = String(a.dropFirst("--settings=".count)) }
                else if a.hasPrefix("--colors=") {
                    let v = String(a.dropFirst("--colors=".count))
                    if ["none", "16", "256", "true"].contains(v) { o.overrides["colors"] = v } else { o.error = "Unknown color mode '\(v)' (none, 16, 256, true)" }
                } else { o.error = "Unknown option \(a)" }
            }
        }
        return o
    }
}

public enum TUIMain {
    /// nil = go on; otherwise print `message` and exit with `code`.
    public static func preflight(options: TUIOptions, isTTY: Bool) -> (code: Int32, message: String)? {
        if options.help { return (0, TUIOptions.usage) }
        if let e = options.error { return (2, e + "\n\n" + TUIOptions.usage) }
        if !isTTY { return (2, "ryry-tui needs an interactive terminal (stdin and stdout must be a terminal).") }
        return nil
    }

    @MainActor
    public static func run(arguments: [String]) async -> Int32 {
        let options = TUIOptions.parse(Array(arguments.dropFirst()))
        let tty = isatty(0) == 1 && isatty(1) == 1
        if let r = preflight(options: options, isTTY: tty) {
            if r.code == 0 { print(r.message) } else { FileHandle.standardError.write(Data((r.message + "\n").utf8)) }
            return r.code
        }
        let dir = options.settingsDir.map { URL(fileURLWithPath: $0) } ?? SettingsPaths.defaultDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let lock = InstanceLock(path: dir.appendingPathComponent("ryry-tui.lock").path) else {
            FileHandle.standardError.write(Data("Another ryry-tui is already running (it holds the sound card and ports).\n".utf8))
            return 1
        }
        defer { lock.release() }
        let caps = Capabilities.detect(env: ProcessInfo.processInfo.environment, isTTY: tty).applying(overrides: options.overrides)
        let session = TerminalSession(caps: caps)
        let model = AppModel(settingsStore: SettingsStore(directory: dir), profileStore: ProfileStore(directory: dir))
        return await TUIApp(model: model, session: session, caps: caps).run()
    }
}

/// The I/O loop: terminal events in, the picture out, the application model in the middle.
@MainActor
public final class TUIApp {
    let model: AppModel
    let session: TerminalSession
    let caps: Capabilities

    public init(model: AppModel, session: TerminalSession, caps: Capabilities) { self.model = model; self.session = session; self.caps = caps }

    /// A message when the application could not start (the sound card or a port is busy, …); nil when it runs.
    public static func startupFailure(_ model: AppModel) -> String? {
        guard model.state == .stopped else { return nil }
        return model.messages.isEmpty ? "The application did not start." : model.messages.joined(separator: "\n")
    }

    public func run() async -> Int32 {
        do { try session.start() } catch {
            FileHandle.standardError.write(Data("ryry-tui needs an interactive terminal.\n".utf8)); return 2
        }
        let model = self.model
        session.onTerminate = { sig in Task { @MainActor in await model.shutdown(); exit(128 + sig) } }   // the session has already stopped writing
        await model.start()
        if let fail = Self.startupFailure(model) {
            session.stop()
            FileHandle.standardError.write(Data((fail + "\n").utf8))
            await model.shutdown()
            return 1
        }
        let screen = MainScreen(model: model, caps: caps, size: session.size)
        screen.onSuspend = { [session] in session.suspend() }
        let frames = FrameWriter(session: session, writer: ANSIWriter(caps: caps))
        var fullRedraw = true
        func present() {
            frames.submit(screen.render(), full: fullRedraw)          // never blocks: a slow terminal only drops frames
            fullRedraw = false
        }
        present()
        let ticker = Task { @MainActor in
            while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(66)); present() }
        }
        for await e in session.events {
            if case .resize = e { fullRedraw = true }
            let keepGoing = await screen.handle(e)
            present()
            if !keepGoing { break }
        }
        ticker.cancel()
        frames.stop()
        session.stop()
        await model.shutdown()
        return 0
    }
}
