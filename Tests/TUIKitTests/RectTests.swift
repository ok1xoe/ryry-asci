// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Testing
@testable import TUIKit

@Test func rectContainsAndInset() {
    let r = Rect(2, 3, 4, 5)
    #expect(r.contains(x: 5, y: 7))
    #expect(!r.contains(x: 6, y: 7))
    #expect(Rect(0, 0, 10, 10).inset(1) == Rect(1, 1, 8, 8))
}
