import CoreNFC
import FamilyControls
import SwiftUI

struct ContentView: View {
    @Environment(FocusManager.self) private var focus
    @Environment(CardIdentityStore.self) private var cards
    @Environment(NFCManager.self) private var nfc

    @State private var showingPicker = false
    @State private var showingTestLab = false
    @State private var statusMessage: String?
    @State private var statusIsError = false

    var body: some View {
        NavigationStack {
            Group {
                if focus.isLocked {
                    lockedScreen
                } else if isConfigured {
                    mainScreen
                } else {
                    setupScreen
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .toolbar {
                // Test Lab im gesperrten Zustand nicht erreichbar – sonst waere
                // es ein Umweg um den Kartenzwang.
                if !focus.isLocked {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Test Lab") { showingTestLab = true }
                            .font(.footnote)
                    }
                }
            }
        }
        .sheet(isPresented: $showingPicker) {
            AppSelectionBinding(focus: focus)
        }
        .sheet(isPresented: $showingTestLab) {
            DebugNFCTestView()
        }
        .task {
            focus.refreshAuthorization()
            if case .notDetermined = focus.authorization {
                await focus.requestAuthorization()
            }
        }
    }

    private var isConfigured: Bool {
        focus.hasSelection && cards.isRegistered
    }

    // MARK: - Screen 1: Setup

    private var setupScreen: some View {
        VStack(alignment: .leading, spacing: 24) {
            header

            authorizationNotice
            paymentAvailabilityNotice

            VStack(alignment: .leading, spacing: 12) {
                Button("Apps auswählen") { showingPicker = true }
                    .buttonStyle(.borderedProminent)

                Text(focus.hasSelection
                     ? "\(focus.selectedCount) ausgewählt ✓"
                     : "Noch nichts ausgewählt")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                Button("Karte registrieren") { registerCard() }
                    .buttonStyle(.bordered)
                    .disabled(nfc.isScanning)

                Text(cards.isRegistered ? "Karte registriert ✓" : "Keine Karte registriert")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            statusView
            Spacer()
            debugSection
        }
    }

    // MARK: - Screen 2: Hauptbildschirm

    private var mainScreen: some View {
        VStack(alignment: .leading, spacing: 24) {
            header

            VStack(alignment: .leading, spacing: 4) {
                Text("Ausgewählte Apps: \(focus.selectedCount)")
                Text("Karte registriert ✓")
            }
            .font(.body)
            .monospaced()

            Button {
                if !focus.lock() {
                    show("Keine Apps ausgewählt.", isError: true)
                }
            } label: {
                Text("APPS SPERREN")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)

            HStack(spacing: 16) {
                Button("Auswahl ändern") { showingPicker = true }
                Button("Karte neu registrieren") { registerCard() }
            }
            .font(.footnote)

            statusView
            Spacer()
            debugSection
        }
    }

    // MARK: - Screen 3: Gesperrt

    private var lockedScreen: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("FOCUS AKTIV")
                .font(.largeTitle.weight(.bold))
                .monospaced()

            Text("Deine Apps sind gesperrt.")
                .foregroundStyle(.secondary)

            Button {
                unlockWithCard()
            } label: {
                Text(nfc.isScanning ? "Warte auf Karte …" : "MIT KARTE ENTSPERREN")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(nfc.isScanning)

            // Bewusst KEIN Software-Entsperren: Die Karte ist der einzige Weg.
            Text("Nur die registrierte Karte entsperrt diese Apps.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            statusView
            Spacer()
        }
    }

    // MARK: - Bausteine

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("KeyFocus")
                .font(.largeTitle.weight(.bold))
            Text("Deine Karte wird zum Schlüssel für deine Apps.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var authorizationNotice: some View {
        if case .denied(let reason) = focus.authorization {
            noticeBox(reason)
        } else if case .notDetermined = focus.authorization {
            VStack(alignment: .leading, spacing: 8) {
                Text("Screen-Time-Berechtigung nötig.")
                    .font(.footnote)
                Button("Berechtigung anfragen") {
                    Task { await focus.requestAuthorization() }
                }
                .font(.footnote)
            }
        }
    }

    @ViewBuilder
    private var paymentAvailabilityNotice: some View {
        if !NFCManager.deviceSupportsNFC {
            noticeBox(ScanFailure.nfcUnsupportedOnDevice.message)
        } else if !NFCManager.paymentReadingAvailable {
            noticeBox(ScanFailure.paymentSessionUnavailable.message)
        }
    }

    private func noticeBox(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var statusView: some View {
        if let statusMessage {
            Text(statusMessage)
                .font(.callout.weight(.medium))
                // Beide Zweige explizit als Color, sonst muss der Compiler
                // zwischen Color und HierarchicalShapeStyle vermitteln.
                .foregroundStyle(statusIsError ? Color.red : Color.primary)
        }
    }

    /// DEBUG-Bereich für die Entwicklung. Zeigt ausschließlich technische
    /// Zustände und Hash-Präfixe – niemals Zahlungs- oder Kartendaten.
    @ViewBuilder
    private var debugSection: some View {
        #if DEBUG
        VStack(alignment: .leading, spacing: 3) {
            Text("DEBUG").font(.caption2.weight(.bold))
            Text("NFC verfügbar: \(NFCManager.deviceSupportsNFC ? "ja" : "nein")")
            Text("Payment-Session verfügbar: \(NFCManager.paymentReadingAvailable ? "ja" : "nein")")
            Text("Registrierter Hash: \(cards.registeredHashPrefix ?? "–")")
            Text("Letzter Fehler: \(nfc.lastFailure?.message ?? "–")")
            Text("Gesperrt: \(focus.isLocked ? "ja" : "nein")")
        }
        .font(.caption2.monospaced())
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        #endif
    }

    // MARK: - Aktionen

    private func registerCard() {
        nfc.scan(purpose: .registration) { result in
            switch result {
            case .success(let outcome):
                if cards.register(hash: outcome.identifierHash) {
                    show("Karte registriert ✓", isError: false)
                } else {
                    show("Karte konnte nicht gespeichert werden (Keychain).", isError: true)
                }
            case .failure(let failure):
                show(failure.message, isError: true)
            }
        }
    }

    private func unlockWithCard() {
        nfc.scan(purpose: .unlock) { result in
            switch result {
            case .success(let outcome):
                if cards.matches(hash: outcome.identifierHash) {
                    focus.unlock()
                    show("Entsperrt ✓", isError: false)
                } else {
                    // Kein Entsperren. Erneuter Versuch ist jederzeit möglich.
                    show("Falsche Karte", isError: true)
                }
            case .failure(let failure):
                show(failure.message, isError: true)
            }
        }
    }

    private func show(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }
}

/// Kleiner Umweg, weil `@Environment`-Objekte kein direktes `Binding` liefern.
private struct AppSelectionBinding: View {
    @Bindable var focus: FocusManager

    var body: some View {
        AppSelectionView(selection: $focus.selection)
    }
}
