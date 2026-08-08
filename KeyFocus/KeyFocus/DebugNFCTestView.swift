import SwiftUI

/// Test Lab: misst, ob `NFCISO7816Tag.identifier` über wiederholte Scans
/// derselben physischen Karte stabil bleibt.
///
/// Das ist das eigentliche Experiment dieser App. Apple garantiert nirgends,
/// dass der Identifier über Scans hinweg konstant ist – bei kontaktlosen
/// Zahlkarten ist eine pro Tap zufällig erzeugte UID aus Datenschutzgründen
/// verbreitet. Ob die konkrete Karte in deiner Hand das tut, kann nur eine
/// Messreihe beantworten, keine Dokumentation.
struct DebugNFCTestView: View {
    @Environment(NFCManager.self) private var nfc
    @Environment(CardIdentityStore.self) private var cards
    @Environment(\.dismiss) private var dismiss

    @State private var scans: [CardScan] = []
    @State private var cardLabel = "Karte A"
    @State private var statusMessage: String?

    /// Läuft gerade die geführte 10er-Messreihe?
    @State private var stabilityRunActive = false
    @State private var stabilityRunStartIndex = 0

    private let stabilityRunTarget = 10

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    availabilityBox
                    labelField
                    actionButtons

                    if stabilityRunActive {
                        stabilityProgress
                    }

                    if let report = finishedStabilityReport {
                        stabilityResult(report)
                    }

                    if !scans.isEmpty {
                        perCardSummary
                        scanHistory
                    }

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("Test Lab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Leeren") { reset() }
                        .disabled(scans.isEmpty)
                }
            }
        }
    }

    // MARK: - Bausteine

    private var availabilityBox: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("NFC verfügbar: \(NFCManager.deviceSupportsNFC ? "ja" : "nein")")
            Text("Payment-Session verfügbar: \(NFCManager.paymentReadingAvailable ? "ja" : "nein")")
            Text("Registrierte Karte: \(cards.registeredHashPrefix ?? "keine")")
        }
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
    }

    private var labelField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Karten-Label")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("z.B. Karte A", text: $cardLabel)
                .textFieldStyle(.roundedBorder)
            Text("Vor dem Wechsel auf eine andere physische Karte umbenennen – "
                 + "so lässt sich prüfen: gleiche Karte → gleicher Identifier, "
                 + "andere Karte → anderer Identifier.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button("Karte scannen") { performScan() }
                .buttonStyle(.borderedProminent)
                .disabled(nfc.isScanning || stabilityRunActive)

            Button("Stabilitätstest starten") { startStabilityRun() }
                .buttonStyle(.bordered)
                .disabled(nfc.isScanning || stabilityRunActive)
        }
    }

    private var stabilityProgress: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STABILITÄTSTEST LÄUFT")
                .font(.caption.weight(.bold))
            Text("Scan \(scansInCurrentRun.count + 1) von \(stabilityRunTarget) – "
                 + "immer dieselbe Karte auflegen.")
                .font(.footnote)

            Button(nfc.isScanning ? "Warte auf Karte …" : "Nächsten Scan ausführen") {
                performScan()
            }
            .buttonStyle(.borderedProminent)
            .disabled(nfc.isScanning)

            Button("Abbrechen") { stabilityRunActive = false }
                .font(.footnote)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func stabilityResult(_ report: StabilityReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(report.headline)
                .font(.headline)
                .foregroundStyle(report.isStable ? .green : .red)
            Text(report.detail)
                .font(.body.monospaced())
            Text("Verschiedene Identifier: \(report.distinctIdentifiers)")
                .font(.caption.monospaced())

            if report.anyLookedRandomized {
                Text("Hinweis: Mindestens ein Identifier sah nach einer zufällig "
                     + "erzeugten UID aus (4 Byte, beginnt mit 0x08/0xF8). Nach "
                     + "ISO/IEC 14443-3 kennzeichnet das eine Zufalls-UID.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            if !report.isStable {
                Text("Damit taugt diese Karte nicht als dauerhafter Schlüssel: "
                     + "Der Identifier ändert sich zwischen den Scans, ein "
                     + "gespeicherter Hash kann also nicht wiedererkannt werden.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    /// Gruppiert nach Label: zeigt je physischer Karte, wie viele verschiedene
    /// Identifier auftraten.
    private var perCardSummary: some View {
        let grouped = Dictionary(grouping: scans, by: \.cardLabel)
        return VStack(alignment: .leading, spacing: 6) {
            Text("JE KARTE")
                .font(.caption.weight(.bold))
            ForEach(grouped.keys.sorted(), id: \.self) { label in
                let group = grouped[label] ?? []
                let distinct = Set(group.map(\.identifierHash)).count
                Text("\(label): \(group.count) Scans, \(distinct) verschiedene Identifier")
                    .font(.caption.monospaced())
                    .foregroundStyle(distinct == 1 ? .green : .red)
            }
            if grouped.count > 1 {
                let allHashes = Set(scans.map(\.identifierHash))
                Text(allHashes.count >= grouped.count
                     ? "Verschiedene Karten liefern verschiedene Identifier ✓"
                     : "Achtung: Karten teilen sich einen Identifier – unerwartet.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var scanHistory: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SCAN-VERLAUF")
                .font(.caption.weight(.bold))
            ForEach(scans.reversed()) { scan in
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scan #\(scan.index) – \(scan.cardLabel)")
                        .font(.caption.weight(.semibold))
                    Text("Hash-Präfix: \(scan.hashPrefix)")
                    Text("AID: \(scan.selectedAID.isEmpty ? "–" : scan.selectedAID)")
                    Text("Identifier: \(scan.identifierByteCount) Byte"
                         + (scan.looksRandomized ? " (sieht zufällig aus)" : ""))
                    if let matches = scan.matchesRegisteredCard {
                        Text("Registrierte Karte erkannt: \(matches ? "JA" : "NEIN")")
                            .foregroundStyle(matches ? .green : .red)
                    }
                }
                .font(.caption2.monospaced())
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - Ablauf

    private var scansInCurrentRun: [CardScan] {
        guard stabilityRunActive || finishedRunExists else { return [] }
        return Array(scans.dropFirst(stabilityRunStartIndex))
    }

    private var finishedRunExists: Bool {
        !stabilityRunActive
            && stabilityRunStartIndex < scans.count
            && scans.count - stabilityRunStartIndex >= stabilityRunTarget
    }

    private var finishedStabilityReport: StabilityReport? {
        guard finishedRunExists else { return nil }
        return StabilityReport.make(from: Array(scans.dropFirst(stabilityRunStartIndex)))
    }

    private func startStabilityRun() {
        stabilityRunStartIndex = scans.count
        stabilityRunActive = true
        statusMessage = "Dieselbe Karte \(stabilityRunTarget)× nacheinander auflegen."
    }

    private func performScan() {
        nfc.scan(purpose: .test) { result in
            switch result {
            case .success(let outcome):
                let scan = CardScan(
                    index: scans.count + 1,
                    timestamp: Date(),
                    identifierHash: outcome.identifierHash,
                    selectedAID: outcome.selectedAID,
                    identifierByteCount: outcome.identifierByteCount,
                    looksRandomized: outcome.looksRandomized,
                    matchesRegisteredCard: cards.isRegistered
                        ? cards.matches(hash: outcome.identifierHash)
                        : nil,
                    cardLabel: cardLabel
                )
                scans.append(scan)
                statusMessage = nil

                if stabilityRunActive,
                   scans.count - stabilityRunStartIndex >= stabilityRunTarget {
                    stabilityRunActive = false
                }
            case .failure(let failure):
                statusMessage = failure.message
            }
        }
    }

    private func reset() {
        scans.removeAll()
        stabilityRunActive = false
        stabilityRunStartIndex = 0
        statusMessage = nil
    }
}
