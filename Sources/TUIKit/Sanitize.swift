// Copyright 2026 OK1XOE (RYRY), LGPL v3

/// Removes everything that could steer the terminal from text that came from outside (received text, telnet spots,
/// callbook): C0/C1 control characters, DEL, and whole CSI/OSC escape sequences. Tabs become spaces; newlines become
/// spaces unless `keepNewlines` (then `\r` is dropped and `\n` kept).
public func sanitize(_ s: String, keepNewlines: Bool = false) -> String {
    var out = String.UnicodeScalarView()
    let u = Array(s.unicodeScalars)
    var i = 0
    while i < u.count {
        let v = u[i].value
        if v == 0x1B {
            i += 1
            guard i < u.count else { break }
            switch u[i].value {
            case 0x5B:                                              // CSI: parameters, then a final byte 0x40…0x7E
                i += 1
                while i < u.count, !(0x40...0x7E).contains(u[i].value) { i += 1 }
                i += 1
            case 0x5D:                                              // OSC: until BEL or ESC \
                i += 1
                while i < u.count {
                    if u[i].value == 0x07 { i += 1; break }
                    if u[i].value == 0x1B { i += (i + 1 < u.count && u[i + 1].value == 0x5C) ? 2 : 1; break }
                    i += 1
                }
            default: i += 1                                         // ESC + one character
            }
            continue
        }
        i += 1
        switch v {
        case 0x09: out.append(" ")
        case 0x0A: if keepNewlines { out.append("\n") } else { out.append(" ") }
        case 0x0D: if !keepNewlines, !(i < u.count && u[i].value == 0x0A) { out.append(" ") }
        case 0x00...0x1F, 0x7F, 0x80...0x9F: break
        default: out.append(Unicode.Scalar(v)!)
        }
    }
    return String(out)
}
