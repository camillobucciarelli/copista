import Foundation

/// Testo localizzato da `Resources/<lingua>.lproj/Localizable.strings`.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}
