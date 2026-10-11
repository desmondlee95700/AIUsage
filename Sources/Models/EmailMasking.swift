import Foundation

/// Optional privacy for screen sharing and screenshots: account emails show as "d3•••@gmail.com".
public enum EmailMasking {
    /// UserDefaults key for the "Hide Email Addresses" setting
    public static let defaultsKey = "hideEmailAddresses"

    /// Keeps the first two characters of the name and the whole domain, so the account stays
    /// recognisable to its owner without being readable by onlookers.
    public static func mask(_ email: String) -> String {
        guard let at = email.firstIndex(of: "@") else {
            return email.count > 2 ? String(email.prefix(2)) + "•••" : email
        }
        let name = email[..<at]
        let domain = email[at...]
        return String(name.prefix(min(2, max(0, name.count - 1)))) + "•••" + domain
    }
}
