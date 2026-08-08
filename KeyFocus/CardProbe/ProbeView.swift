import SwiftUI

/// Einziger Bildschirm: scannen, Ergebnis zählen, Urteil anzeigen.
struct ProbeView: View {
    @Environment(NFCManager.self) private var nfc

    @State private var scans: [CardScan] = []
    @State private var cardLabel = "Karte A"
    @State private var mode: SessionMode = .anyTag
    @State private var status: String?

    /// Alle Scans der aktuell eingestellten Karte – Basis für das Urteil.
    private var scansForCurrentLabel: [CardScan] {
        scans.filter { $0.cardLabel == cardLabel }
    }

    private var report: StabilityReport {
        StabilityReport.make(from: scansForCurrentLabel)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    availability
                    modePicker
                    labelField
                    scanButton
                    verdict
                    if scans.count > scansForCurrentLabel.count {
                        crossCardCheck
                    }
                    history
                }
                .padding()
            }
            .navigationTitle("CardProbe")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Leeren") { scans.removeAll(); status = nil }
                        .disabled(scans.isEmpty)
                }
            }
        }
    }

    // MARK: - Bausteine

    private var availability: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("NFC: \(NFCManager.deviceSupportsNFC ? "verfügbar" : "nicht verfügbar")")
            Text("Zahlkarten-Session: \(NFCManager.paymentReadingAvailable ? "verfügbar" : "nicht verfügbar")")
        }
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Modus", selection: $mode) {
                ForEach(SessionMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(mode.explanation)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var labelField: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Karten-Label", text: $cardLabel)
                .textFieldStyle(.roundedBorder)
            Text("Beim Wechsel auf eine andere physische Karte umbenennen. "
                 + "Das Urteil unten bezieht sich immer auf das aktuelle Label.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var scanButton: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                scan()
            } label: {
                Text(nfc.isScanning ? "Warte auf Karte …" : "Karte scannen")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .disabled(nfc.isScanning || cardLabel.isEmpty)

            if let status {
                Text(status).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var verdict: some View {
        let scanned = scansForCurrentLabel
        if !scanned.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(cardLabel): \(scanned.count) Scans")
                    .font(.caption.weight(.bold))

                Text(report.headline)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(report.isStable ? Color.green : Color.red)

                Text(report.detail)
                    .font(.body.monospaced())

                if scanned.count < 10 {
                    Text("Für ein belastbares Urteil auf 10 Scans kommen "
                         + "(\(10 - scanned.count) fehlen noch).")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if report.anyLookedRandomized {
                    Text("Mindestens ein Identifier sah nach einer Zufalls-UID aus "
                         + "(4 Byte, beginnt mit 0x08/0xF8 – nach ISO/IEC 14443-3 "
                         + "die Kennzeichnung dafür). Bei dieser Karte ist ein "
                         + "instabiles Ergebnis zu erwarten.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                if !report.isStable && scanned.count >= 2 {
                    Text("Diese Karte taugt nicht als Schlüssel: Der Identifier "
                         + "ändert sich zwischen den Scans, ein gespeicherter "
                         + "Hash kann sie also nicht wiedererkennen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    /// Prüft die zweite Anforderung: verschiedene Karten müssen sich
    /// unterscheiden. Sonst wäre der Schlüssel nicht eindeutig.
    private var crossCardCheck: some View {
        let byLabel = Dictionary(grouping: scans, by: \.cardLabel)
        let stableLabels = byLabel.filter { Set($0.value.map(\.identifierHash)).count == 1 }
        let stableHashes = Set(stableLabels.compactMap { $0.value.first?.identifierHash })
        let collision = stableLabels.count > 1 && stableHashes.count < stableLabels.count

        return VStack(alignment: .leading, spacing: 4) {
            Text("KARTENVERGLEICH").font(.caption.weight(.bold))
            ForEach(byLabel.keys.sorted(), id: \.self) { label in
                let group = byLabel[label] ?? []
                let distinct = Set(group.map(\.identifierHash)).count
                Text("\(label): \(group.count) Scans, \(distinct) Identifier")
                    .font(.caption2.monospaced())
                    .foregroundStyle(distinct == 1 ? Color.green : Color.red)
            }
            if stableLabels.count > 1 {
                Text(collision
                     ? "Achtung: Zwei Karten liefern denselben Identifier."
                     : "Verschiedene Karten liefern verschiedene Identifier ✓")
                    .font(.caption2)
                    .foregroundStyle(collision ? Color.red : Color.secondary)
            }
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !scans.isEmpty {
                Text("VERLAUF").font(.caption.weight(.bold))
            }
            ForEach(scans.reversed()) { scan in
                VStack(alignment: .leading, spacing: 1) {
                    Text("#\(scan.index) \(scan.cardLabel) · \(scan.tagKind)")
                        .fontWeight(.semibold)
                    Text("Hash: \(scan.hashPrefix)")
                    Text("\(scan.identifierByteCount) Byte"
                         + (scan.selectedAID.isEmpty ? "" : " · AID \(scan.selectedAID)")
                         + (scan.looksRandomized ? " · sieht zufällig aus" : ""))
                }
                .font(.caption2.monospaced())
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - Aktion

    private func scan() {
        nfc.scan(purpose: .test, mode: mode) { result in
            switch result {
            case .success(let outcome):
                scans.append(
                    CardScan(
                        index: scans.count + 1,
                        timestamp: Date(),
                        identifierHash: outcome.identifierHash,
                        selectedAID: outcome.selectedAID,
                        tagKind: outcome.tagKind,
                        identifierByteCount: outcome.identifierByteCount,
                        looksRandomized: outcome.looksRandomized,
                        matchesRegisteredCard: nil,
                        cardLabel: cardLabel
                    )
                )
                status = nil
            case .failure(let failure):
                status = failure.message
            }
        }
    }
}
