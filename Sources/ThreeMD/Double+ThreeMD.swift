// MARK: - Double + 3md formatting

extension Double {
    /// Formats the value as an integer string when it is whole and within a safe
    /// range, falling back to the default decimal representation otherwise.
    ///
    /// Shared by ``Serializer`` and ``HTMLRenderer`` so a plane's `z` (and `x`,
    /// `y`) render identically wherever they appear.
    internal func formatted3MD() -> String {
        guard self == rounded(), abs(self) < 1e15 else { return String(self) }
        return String(Int(self))
    }
}
