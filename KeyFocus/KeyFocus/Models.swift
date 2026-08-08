import Foundation

// MARK: - Scan purpose

/// Warum gerade gescannt wird. Bestimmt den Prompt und was mit dem Ergebnis passiert.
enum ScanPurpose: Sendable {
    case registration
    case unlock
    case test

    var alertMessage: String {
        switch self {
        case .registration:
            return "Halte die Karte an das obere Ende des iPhones, die künftig deine Apps entsperren soll."
        case .unlock:
            return "Halte deine registrierte Karte an das obere Ende des iPhones."
        case .test:
            return "Halte die Karte an das obere Ende des iPhones."
        }
    }
}

// MARK: - Scan-Ergebnis

/// Das Ergebnis eines Scans – bewusst OHNE Zahlungsdaten.
///
/// Was hier drin ist: der SHA-256-Hash des NFC-Tag-Identifiers, der ausgewählte
/// AID und die Länge des Identifiers. Was hier NICHT drin ist und auch nie
/// hineingehört: PAN, Ablaufdatum, Karteninhaber, CVV, Transaktionsdaten.
/// Der rohe Identifier wird bewusst nicht als Feld gespeichert – er existiert
/// nur kurz im Speicher, bis der Hash gebildet ist.
struct CardScan: Identifiable, Sendable {
    let id = UUID()
    let index: Int
    let timestamp: Date
    /// SHA-256 des Identifiers, hex-codiert.
    let identifierHash: String
    /// Der von der Session automatisch selektierte AID, z.B. "A0000000031010".
    let selectedAID: String
    /// Byte-Länge des Identifiers. 4 Byte deutet auf ISO14443-A single size hin.
    let identifierByteCount: Int
    /// Heuristik: sieht der Identifier nach einer zufällig erzeugten UID aus?
    let looksRandomized: Bool
    /// Nur gesetzt, wenn bereits eine Karte registriert ist.
    let matchesRegisteredCard: Bool?
    /// Freies Label, damit sich im Test Lab mehrere physische Karten unterscheiden lassen.
    let cardLabel: String

    var hashPrefix: String {
        String(identifierHash.prefix(8)).uppercased()
    }
}

// MARK: - Stabilitätsauswertung

/// Auswertung einer Messreihe: Wie oft kam derselbe Identifier heraus?
struct StabilityReport: Sendable {
    let totalScans: Int
    /// Größte Gruppe identischer Hashes.
    let largestIdenticalGroup: Int
    /// Anzahl verschiedener Identifier über alle Scans.
    let distinctIdentifiers: Int
    let anyLookedRandomized: Bool

    var isStable: Bool {
        totalScans > 0 && distinctIdentifiers == 1
    }

    var headline: String {
        isStable ? "IDENTIFIER STABIL" : "IDENTIFIER INSTABIL"
    }

    var detail: String {
        "\(largestIdenticalGroup) / \(totalScans) Identifier identisch"
    }

    static func make(from scans: [CardScan]) -> StabilityReport {
        var counts: [String: Int] = [:]
        for scan in scans {
            counts[scan.identifierHash, default: 0] += 1
        }
        return StabilityReport(
            totalScans: scans.count,
            largestIdenticalGroup: counts.values.max() ?? 0,
            distinctIdentifiers: counts.count,
            anyLookedRandomized: scans.contains { $0.looksRandomized }
        )
    }
}

// MARK: - Fehler

/// Lesbare Fehler statt Crashes. Jeder Fall bekommt einen Text, der dem Nutzer
/// sagt, was er tun kann.
enum ScanFailure: Equatable, Sendable {
    case nfcUnsupportedOnDevice
    case paymentSessionUnavailable
    case ineligibleRegionOrAccount
    case cancelledByUser
    case multipleTagsDetected
    case unsupportedTagType
    case readFailed(String)
    case cardRemovedTooQuickly
    case sessionTimeout

    var message: String {
        switch self {
        case .nfcUnsupportedOnDevice:
            return "Dieses Gerät unterstützt kein NFC-Tag-Lesen."
        case .paymentSessionUnavailable:
            return """
                Das Lesen von Zahlkarten ist auf diesem Gerät nicht verfügbar. \
                Apple gibt NFCPaymentTagReaderSession nur in der EU frei – die \
                Apple-ID muss in der EU registriert und das Gerät in der EU sein. \
                Siehe SETUP.md.
                """
        case .ineligibleRegionOrAccount:
            return """
                Gerät oder Account sind nicht berechtigt (NFCReaderError.readerErrorIneligible). \
                Diese API ist auf die EU beschränkt. Siehe SETUP.md.
                """
        case .cancelledByUser:
            return "Scan abgebrochen."
        case .multipleTagsDetected:
            return "Mehrere Karten erkannt. Bitte nur eine Karte an das iPhone halten."
        case .unsupportedTagType:
            return "Diese Karte ist kein ISO7816-Tag und kann nicht als Schlüssel dienen."
        case .cardRemovedTooQuickly:
            return "Karte zu früh entfernt. Bitte ruhig halten, bis die Bestätigung erscheint."
        case .sessionTimeout:
            return "Zeitüberschreitung. Bitte erneut versuchen."
        case .readFailed(let detail):
            return "Lesefehler: \(detail)"
        }
    }
}

// MARK: - Identifier-Heuristik

enum IdentifierHeuristics {
    /// Schätzt, ob eine UID zufällig erzeugt wurde.
    ///
    /// Nach ISO/IEC 14443-3 kennzeichnet bei einer einfachen 4-Byte-UID
    /// (single size) das erste Byte 0x08 eine zufällig erzeugte UID; 0xF8 ist
    /// ebenfalls für nicht-eindeutige IDs reserviert.
    ///
    /// WICHTIG: Das ist ein Hinweis, kein Beweis.
    /// - Bei ISO14443-B ist der Identifier die PUPI, die ebenfalls häufig
    ///   zufällig ist, sich aber nicht an diesem Muster erkennen lässt.
    /// - Eine Karte kann trotz anderem Präfix bei jedem Tap neu würfeln.
    /// Verlässlich ist nur die Messreihe im Test Lab.
    static func looksRandomized(_ identifier: Data) -> Bool {
        guard let first = identifier.first else { return false }
        return identifier.count == 4 && (first == 0x08 || first == 0xF8)
    }
}
