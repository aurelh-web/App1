import CoreNFC
import Foundation
import Observation

/// Kapselt das Lesen der Karte.
///
/// Verwendet `NFCPaymentTagReaderSession` (iOS 26+), weil normale
/// `NFCTagReaderSession`-Sessions Zahlkarten nicht erfassen. Die Klasse ist
/// laut Apple-Dokumentation ausschließlich in der EU nutzbar – ist das Gerät
/// oder der Account nicht berechtigt, ist `readingAvailable` false.
///
/// DATENSCHUTZ: Diese Klasse ruft bewusst NIE `session.connect(to:)` auf und
/// sendet nie ein APDU-Kommando. Ausgewertet werden nur `identifier` und
/// `initialSelectedAID`, die beim Erkennen ohnehin anfallen. Damit findet gar
/// keine Kommunikation statt, in der PAN, Ablaufdatum oder Transaktionsdaten
/// anfallen könnten.
@MainActor
@Observable
final class NFCManager: NSObject {

    /// Ergebnis eines abgeschlossenen Scans.
    struct ScanOutcome: Sendable {
        let identifierHash: String
        let selectedAID: String
        let identifierByteCount: Int
        let looksRandomized: Bool
    }

    private(set) var isScanning = false
    private(set) var lastFailure: ScanFailure?

    private var session: NFCTagReaderSession?
    private var completion: ((Result<ScanOutcome, ScanFailure>) -> Void)?

    /// Grundsätzliche NFC-Fähigkeit des Geräts.
    static var deviceSupportsNFC: Bool {
        NFCTagReaderSession.readingAvailable
    }

    /// Ob speziell das Lesen von Zahlkarten erlaubt ist.
    ///
    /// Laut Apple false, wenn Gerät/Account nicht EU-berechtigt sind. Das ist
    /// der Gatekeeper für diese gesamte App.
    static var paymentReadingAvailable: Bool {
        NFCPaymentTagReaderSession.readingAvailable
    }

    /// Startet einen Scan. Das Ergebnis kommt über `completion` auf dem MainActor.
    func scan(
        purpose: ScanPurpose,
        completion: @escaping (Result<ScanOutcome, ScanFailure>) -> Void
    ) {
        guard !isScanning else { return }

        guard Self.deviceSupportsNFC else {
            fail(.nfcUnsupportedOnDevice, completion: completion)
            return
        }
        guard Self.paymentReadingAvailable else {
            fail(.paymentSessionUnavailable, completion: completion)
            return
        }
        // Apples ObjC-Header deklariert `- (instancetype)initWithDelegate:queue:`
        // ohne `nullable`, der Initializer wird also NICHT optional nach Swift
        // importiert (anders als bei NFCTagReaderSession, wo er `init?` ist).
        // Sollte dein SDK ihn doch als failable importieren, ist hier ein
        // `guard let` nötig – das ist die einzige betroffene Zeile.
        let newSession = NFCPaymentTagReaderSession(delegate: self, queue: nil)

        self.completion = completion
        self.lastFailure = nil
        self.isScanning = true
        self.session = newSession

        newSession.alertMessage = purpose.alertMessage
        newSession.begin()
    }

    private func fail(
        _ failure: ScanFailure,
        completion: (Result<ScanOutcome, ScanFailure>) -> Void
    ) {
        lastFailure = failure
        completion(.failure(failure))
    }

    // Aufgerufen vom Delegate, bereits auf dem MainActor.
    fileprivate func finish(with result: Result<ScanOutcome, ScanFailure>) {
        isScanning = false
        session = nil
        if case .failure(let failure) = result {
            lastFailure = failure
        }
        let handler = completion
        completion = nil
        handler?(result)
    }

    func clearFailure() {
        lastFailure = nil
    }
}

// MARK: - NFCTagReaderSessionDelegate

// Die Callbacks kommen auf der Session-Queue, nicht auf dem MainActor. Deshalb
// `nonisolated`: alles, was mit der nicht-Sendable `NFCTag`/`NFCISO7816Tag`
// oder der Session zu tun hat, passiert synchron hier. An den MainActor gehen
// nur Sendable-Werte (Data ist bereits zu String gehasht, Int, Bool).
extension NFCManager: NFCTagReaderSessionDelegate {

    nonisolated func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        // Nichts zu tun – die Systemoberfläche zeigt bereits alertMessage.
    }

    nonisolated func tagReaderSession(
        _ session: NFCTagReaderSession,
        didInvalidateWithError error: Error
    ) {
        let failure = Self.mapInvalidation(error)
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Ein sauber abgeschlossener Scan hat den Handler schon konsumiert;
            // die anschließende Invalidierung darf dann nichts mehr melden.
            guard self.isScanning else { return }
            self.finish(with: .failure(failure))
        }
    }

    nonisolated func tagReaderSession(
        _ session: NFCTagReaderSession,
        didDetect tags: [NFCTag]
    ) {
        guard tags.count == 1 else {
            session.invalidate(errorMessage: ScanFailure.multipleTagsDetected.message)
            return
        }
        guard case .iso7816(let tag) = tags[0] else {
            session.invalidate(errorMessage: ScanFailure.unsupportedTagType.message)
            return
        }

        // Nur diese beiden Werte werden gelesen. Kein connect, kein APDU.
        let identifier = tag.identifier
        let aid = tag.initialSelectedAID

        guard !identifier.isEmpty else {
            session.invalidate(errorMessage: ScanFailure.cardRemovedTooQuickly.message)
            return
        }

        // Hash sofort bilden, damit der rohe Identifier diese Funktion nicht verlässt.
        let outcome = ScanOutcome(
            identifierHash: CardIdentityStore.hash(identifier: identifier),
            selectedAID: aid,
            identifierByteCount: identifier.count,
            looksRandomized: IdentifierHeuristics.looksRandomized(identifier)
        )

        session.alertMessage = "Karte gelesen ✓"
        session.invalidate()

        Task { @MainActor [weak self] in
            self?.finish(with: .success(outcome))
        }
    }

    /// Übersetzt Core-NFC-Fehler in lesbare Zustände.
    private static func mapInvalidation(_ error: Error) -> ScanFailure {
        guard let readerError = error as? NFCReaderError else {
            return .readFailed(error.localizedDescription)
        }
        switch readerError.code {
        case .readerSessionInvalidationErrorUserCanceled:
            return .cancelledByUser
        case .readerSessionInvalidationErrorSessionTimeout:
            return .sessionTimeout
        case .readerSessionInvalidationErrorSessionTerminatedUnexpectedly:
            return .cardRemovedTooQuickly
        case .readerTransceiveErrorTagConnectionLost:
            return .cardRemovedTooQuickly

        // Neu in iOS 26 (ObjC: NFCReaderErrorIneligible). Signalisiert, dass
        // Gerät oder Account nicht für das Lesen von Zahlkarten berechtigt sind
        // – in der Praxis: außerhalb der EU. Sollte dieses Symbol in deinem SDK
        // anders heißen, ist das die einzige Zeile, die anzupassen ist.
        case .readerErrorIneligible:
            return .ineligibleRegionOrAccount

        case .readerErrorUnsupportedFeature, .readerErrorSecurityViolation:
            return .paymentSessionUnavailable
        default:
            return .readFailed(readerError.localizedDescription)
        }
    }
}
