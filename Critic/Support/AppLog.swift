import Foundation

// Suppress console logging in release builds without touching every existing call site.
func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
#if DEBUG
    Swift.print(items.map { String(describing: $0) }.joined(separator: separator), terminator: terminator)
#endif
}
