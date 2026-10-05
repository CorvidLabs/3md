/// The frozen decimal grammar, scanned once without regular-expression backtracking.
internal enum FiniteDecimal {
    static func parse(_ raw: String) -> Double? {
        var bytes = raw.utf8.makeIterator()
        var byte = bytes.next()
        if byte == 43 || byte == 45 { byte = bytes.next() }
        var mantissaDigits = false
        while let current = byte, (48...57).contains(current) {
            mantissaDigits = true
            byte = bytes.next()
        }
        if byte == 46 {
            byte = bytes.next()
            while let current = byte, (48...57).contains(current) {
                mantissaDigits = true
                byte = bytes.next()
            }
        }
        guard mantissaDigits else { return nil }
        if byte == 69 || byte == 101 {
            byte = bytes.next()
            if byte == 43 || byte == 45 { byte = bytes.next() }
            var exponentDigits = false
            while let current = byte, (48...57).contains(current) {
                exponentDigits = true
                byte = bytes.next()
            }
            guard exponentDigits else { return nil }
        }
        guard byte == nil, let value = Double(raw), value.isFinite else { return nil }
        return value
    }
}
