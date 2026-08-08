import CryptoKit
import Foundation
import Observation

/// Verwaltet die Identität der registrierten Karte.
///
/// DATENSCHUTZ – das ist der Kern dieser Datei:
///
/// Gespeichert wird ausschließlich `SHA256(identifier)`, wobei `identifier` der
/// NFC-Tag-Identifier aus `NFCISO7816Tag.identifier` ist (die UID/PUPI aus der
/// ISO14443-Antikollision).
///
/// Nicht gespeichert, nicht gelesen, nicht angezeigt, nicht übertragen:
/// PAN/Kartennummer, Ablaufdatum, Karteninhabername, CVV, Transaktionsdaten,
/// sowie der rohe Identifier selbst.
///
/// Die App sendet zu keinem Zeitpunkt ein APDU-Kommando an die Karte und ruft
/// `connect(to:)` nie auf – es findet also gar keine Kommunikation statt, in
/// der Zahlungsdaten anfallen könnten. Gelesen wird nur, was die Session beim
/// Erkennen ohnehin bereitstellt.
///
/// Der rohe Identifier existiert nur als lokale Variable, bis der Hash gebildet
/// ist, und wird danach nicht weitergereicht.
@MainActor
@Observable
final class CardIdentityStore {

    private(set) var registeredHash: String?

    init() {
        registeredHash = Self.loadHash()
    }

    var isRegistered: Bool { registeredHash != nil }

    /// Erste 8 Hex-Zeichen des gespeicherten Hashes – nur zur Anzeige im Debug.
    /// Aus einem Präfix lässt sich der Identifier nicht rekonstruieren.
    var registeredHashPrefix: String? {
        guard let registeredHash else { return nil }
        return String(registeredHash.prefix(8)).uppercased()
    }

    /// Bildet den Hash. Der Identifier wird hier verbraucht und nicht behalten.
    ///
    /// `nonisolated`, weil das direkt im NFC-Delegate auf der Session-Queue
    /// aufgerufen wird – der rohe Identifier soll gar nicht erst auf den
    /// MainActor wandern, sondern sofort an der Fundstelle zu einem Hash werden.
    nonisolated static func hash(identifier: Data) -> String {
        SHA256.hash(data: identifier)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Registriert eine Karte. Erwartet den bereits gebildeten Hash, damit der
    /// rohe Identifier gar nicht erst bis hierher wandert.
    func register(hash: String) -> Bool {
        guard let data = hash.data(using: .utf8) else { return false }
        guard KeychainStore.save(data, for: .registeredCardHash) else { return false }
        registeredHash = hash
        return true
    }

    /// Prüft einen Scan gegen die registrierte Karte.
    func matches(hash: String) -> Bool {
        guard let registeredHash else { return false }
        return Self.constantTimeEquals(hash, registeredHash)
    }

    func reset() {
        KeychainStore.delete(.registeredCardHash)
        registeredHash = nil
    }

    private static func loadHash() -> String? {
        guard let data = KeychainStore.load(.registeredCardHash) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Vergleich ohne frühen Abbruch.
    ///
    /// Bei einem lokalen Besitzfaktor ist ein Timing-Angriff praktisch kaum
    /// relevant – aber ein Vergleich, der bei der ersten Abweichung abbricht,
    /// ist bei Sicherheitsentscheidungen die falsche Gewohnheit.
    private static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8)
        let b = Array(rhs.utf8)
        guard a.count == b.count else { return false }
        var difference: UInt8 = 0
        for index in a.indices {
            difference |= a[index] ^ b[index]
        }
        return difference == 0
    }
}
