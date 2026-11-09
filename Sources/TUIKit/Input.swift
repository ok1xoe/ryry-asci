// Copyright 2026 OK1XOE (RYRY), LGPL v3

public enum Key: Hashable, Sendable {
    case char(Character)
    case f(Int)
    case up, down, left, right, home, end, pageUp, pageDown
    case enter, tab, backTab, backspace, delete, insert, escape
}

public struct Modifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let shift = Modifiers(rawValue: 1)
    public static let alt = Modifiers(rawValue: 2)
    public static let ctrl = Modifiers(rawValue: 4)
}

public struct MouseEvent: Equatable, Sendable {
    public enum Kind: Sendable { case press, release, drag, move, wheelUp, wheelDown }
    public enum Button: Sendable { case left, middle, right, none }
    public var kind: Kind
    public var button: Button
    /// 0-based cell coordinates.
    public var x: Int
    public var y: Int
    public var mods: Modifiers
    public init(kind: Kind, button: Button, x: Int, y: Int, mods: Modifiers) {
        self.kind = kind; self.button = button; self.x = x; self.y = y; self.mods = mods
    }
}

public enum InputEvent: Equatable, Sendable {
    case key(Key, Modifiers)
    case mouse(MouseEvent)
    case paste(String)
    case resize(cols: Int, rows: Int)
}
