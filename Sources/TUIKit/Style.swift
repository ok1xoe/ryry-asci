// Copyright 2026 OK1XOE (RYRY), LGPL v3

public enum Color: Equatable, Sendable {
    case `default`
    case indexed(UInt8)
    case rgb(UInt8, UInt8, UInt8)
}

public struct Style: Equatable, Sendable {
    public var fg: Color
    public var bg: Color
    public var bold: Bool
    public var dim: Bool
    public var inverse: Bool
    public var underline: Bool

    public init(fg: Color = .default, bg: Color = .default, bold: Bool = false, dim: Bool = false,
                inverse: Bool = false, underline: Bool = false) {
        self.fg = fg; self.bg = bg; self.bold = bold; self.dim = dim; self.inverse = inverse; self.underline = underline
    }

    public static let plain = Style()
}

public struct Cell: Equatable, Sendable {
    public var char: Character
    public var style: Style
    /// The right half of a double-width character (nothing is printed for it).
    public var isContinuation: Bool

    public init(char: Character = " ", style: Style = .plain, isContinuation: Bool = false) {
        self.char = char; self.style = style; self.isContinuation = isContinuation
    }

    public static let blank = Cell()
}
