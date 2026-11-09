// Copyright 2026 OK1XOE (RYRY), LGPL v3

public enum ColorDepth: Int, Comparable, Sendable {
    case mono, ansi16, ansi256, trueColor
    public static func < (a: ColorDepth, b: ColorDepth) -> Bool { a.rawValue < b.rawValue }
}

/// What the terminal can show. No terminal is the reference: everything degrades from true color + Unicode to plain ASCII.
public struct Capabilities: Equatable, Sendable {
    public var colorDepth: ColorDepth
    public var unicode: Bool
    public var mouse: Bool

    public init(colorDepth: ColorDepth, unicode: Bool, mouse: Bool) {
        self.colorDepth = colorDepth; self.unicode = unicode; self.mouse = mouse
    }

    public static func detect(env: [String: String], isTTY: Bool) -> Capabilities {
        let term = env["TERM"] ?? ""
        let colorTerm = (env["COLORTERM"] ?? "").lowercased()
        let depth: ColorDepth
        if !(env["NO_COLOR"] ?? "").isEmpty || term == "dumb" || term.isEmpty {
            depth = .mono
        } else if colorTerm.contains("truecolor") || colorTerm.contains("24bit") || term.contains("direct")
                    || term.contains("ghostty") || term.contains("kitty") || term.contains("wezterm") {
            depth = .trueColor
        } else if term.contains("256color") || env["TERM_PROGRAM"] == "Apple_Terminal" {
            depth = .ansi256
        } else {
            depth = .ansi16
        }
        let locale = [env["LC_ALL"], env["LC_CTYPE"], env["LANG"]].compactMap { $0 }.first { !$0.isEmpty } ?? ""
        let unicode = locale.lowercased().contains("utf-8") || locale.lowercased().contains("utf8")
        return Capabilities(colorDepth: depth, unicode: unicode, mouse: isTTY && term != "dumb")
    }

    /// Overrides from the command line: `colors` = none|16|256|true, `ascii`, `no-mouse`.
    public func applying(overrides: [String: String]) -> Capabilities {
        var c = self
        switch overrides["colors"] {
        case "none": c.colorDepth = .mono
        case "16": c.colorDepth = .ansi16
        case "256": c.colorDepth = .ansi256
        case "true": c.colorDepth = .trueColor
        default: break
        }
        if overrides["ascii"] != nil { c.unicode = false }
        if overrides["no-mouse"] != nil { c.mouse = false }
        return c
    }
}
