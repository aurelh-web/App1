import CryptoKit
import Foundation

/// SHA-256 als Hex-String.
///
/// Bewusst eine freie Funktion und nicht an eine Klasse gebunden: Sie wird im
/// NFC-Delegate auf der Session-Queue aufgerufen, also außerhalb des MainActor.
/// Der rohe Identifier soll direkt an der Fundstelle zu einem Hash werden und
/// von dort nicht weiterwandern.
nonisolated func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
}
