// Copyright 2026 OK1XOE (RYRY), LGPL v3

/// A rectangle in terminal cells (0-based, origin at the top left).
public struct Rect: Equatable, Sendable {
    public var x, y, w, h: Int
    public init(_ x: Int, _ y: Int, _ w: Int, _ h: Int) { self.x = x; self.y = y; self.w = w; self.h = h }

    public func contains(x px: Int, y py: Int) -> Bool { px >= x && px < x + w && py >= y && py < y + h }

    public func inset(_ n: Int) -> Rect { Rect(x + n, y + n, max(0, w - 2 * n), max(0, h - 2 * n)) }
}
