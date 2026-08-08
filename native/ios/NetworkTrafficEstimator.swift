// NetworkTrafficEstimator.swift
//
// EMPFOHLENER STANDARD-DATENPFAD für iOS.
//
// Idee: Jedes Reel muss als Videodatei von Instagrams CDN nachgeladen werden.
// Diese Netzwerk-Anfragen laufen über das Gerät und sind über Apples
// NetworkExtension-Framework beobachtbar – ohne Bildschirmaufnahme, ohne
// roten Aufnahme-Balken, ohne Jailbreak. Dieselbe API, über die
// App-Store-Werbeblocker (AdGuard, Lockdown Privacy) arbeiten.
//
// Sichtbar ist für den Nutzer nur das dezente "VPN"-Symbol in der Statusleiste.
// Wichtig: Der Tunnel bleibt vollständig auf dem Gerät – es wird KEIN Traffic
// an einen fremden Server ausgeleitet. Das ist Voraussetzung dafür, dass die
// App datenschutzrechtlich und in der App-Store-Review vertretbar ist.
//
// Warum PacketTunnelProvider und nicht die naheliegenderen Alternativen:
//   - NEFilterDataProvider (Content Filter) und NEDNSProxyProvider erfordern
//     auf iOS ein per MDM *supervidiertes* Gerät. Für eine normale
//     Endnutzer-App scheidet das aus.
//   - Bleibt NEPacketTunnelProvider über ein Personal-VPN-Profil, das der
//     Nutzer selbst bestätigt.
//
// Benötigte Capabilities im Xcode-Projekt:
//   - Network Extensions Capability mit "Packet Tunnel Provider"
//     (com.apple.developer.networking.networkextension) – muss im Apple
//     Developer Portal freigeschaltet sein, ggf. mit Antrag bei Apple
//   - Personal VPN Capability (com.apple.developer.networking.vpn.api)
//   - Eigenes Network-Extension-Target + App Group (geteilt mit Haupt-App
//     und Widget)
//
// Architektur-Skizze, kein vollständiges, kompilierbares Xcode-Target.
// Insbesondere fehlt der eigentliche Userspace-TCP/IP-Stack (siehe
// "Ehrliche Grenzen" unten).

import NetworkExtension
import Foundation

// MARK: - Kalibrierbare Heuristik-Parameter
//
// Alle Werte hier sind Startwerte, die in der Praxis gegen echte Messungen
// kalibriert werden müssen. Instagram dokumentiert nichts davon öffentlich,
// wir beobachten nur Muster von außen.

enum TrafficHeuristics {
    /// Ab wie vielen empfangenen Bytes am Stück gilt ein Datenschub als
    /// Video-Segment (statt als Thumbnail, Icon, Telemetrie o.ä.).
    static let minBurstBytes = 120_000

    /// Wie lange Ruhe herrschen muss, damit der nächste Datenschub als neuer
    /// Burst zählt statt als Fortsetzung des vorherigen.
    static let burstIdleGap: TimeInterval = 0.4

    /// Wie viele Segment-Bursts im Schnitt auf EIN Reel entfallen. Instagram
    /// lädt Videos gestückelt (adaptives Streaming), ein Reel kann mehrere
    /// Bursts erzeugen. Der wichtigste Kalibrierwert überhaupt.
    static let burstsPerReel: Double = 1.8

    /// Domains, deren Traffic als Reels-Video gewertet wird.
    static let instagramCDNSuffixes = ["cdninstagram.com", "fbcdn.net"]
}

// MARK: - Packet Tunnel Provider

/// Läuft als eigener Extension-Prozess, den iOS startet, sobald der Nutzer das
/// VPN-Profil aktiviert. Bekommt jedes IP-Paket des Geräts zu sehen.
final class ReelMeterTunnelProvider: NEPacketTunnelProvider {

    private let analyzer = ReelTrafficAnalyzer()

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        // Der Tunnel terminiert lokal. Die Remote-Adresse ist Pflichtfeld,
        // zeigt hier aber bewusst auf das Gerät selbst – es geht nichts nach
        // außen an einen Server von uns.
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")

        let ipv4 = NEIPv4Settings(addresses: ["10.42.0.2"], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.iPv4Settings = ipv4

        // DNS über den Tunnel leiten, damit wir Hostnamen → IP-Mapping
        // mitbekommen (siehe Grenzen: DoH/DoT umgeht das).
        settings.dnsSettings = NEDNSSettings(servers: ["1.1.1.1"])

        setTunnelNetworkSettings(settings) { [weak self] error in
            if let error {
                completionHandler(error)
                return
            }
            self?.readPacketsLoop()
            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        analyzer.flush()
        completionHandler()
    }

    /// Endlosschleife: Pakete lesen, analysieren, weiterreichen.
    private func readPacketsLoop() {
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self else { return }

            for (packet, proto) in zip(packets, protocols) {
                self.analyzer.inspect(packet: packet, protocolFamily: proto)
            }

            // WICHTIG: Hier müssten die Pakete an ihr echtes Ziel
            // weitergeleitet und die Antworten zurückgeschrieben werden –
            // siehe "Ehrliche Grenzen" unten.
            self.forwardUpstream(packets, protocols)

            self.readPacketsLoop()
        }
    }

    private func forwardUpstream(_ packets: [Data], _ protocols: [NSNumber]) {
        // Platzhalter. Ein PacketTunnelProvider ist kein passiver Mithörer:
        // sobald er die Default-Route übernimmt, ist er für den kompletten
        // Netzwerkverkehr des Geräts VERANTWORTLICH. Ohne funktionierendes
        // Forwarding hat das Gerät kein Internet mehr.
        //
        // Realistische Umsetzung: ein Userspace-TCP/IP-Stack (z.B. lwIP oder
        // tun2socks), der die Verbindungen terminiert und über NWConnection
        // neu aufbaut. Das ist der mit Abstand aufwendigste Teil dieses
        // Datenpfads – deutlich mehr Arbeit als die Zähl-Logik selbst.
    }
}

// MARK: - Traffic-Analyse

/// Wertet die vorbeikommenden Pakete aus. Sieht KEINE Videoinhalte – der
/// Traffic ist TLS/QUIC-verschlüsselt. Ausgewertet werden nur Metadaten:
/// Ziel-IP, Zeitpunkt, Paketgröße.
final class ReelTrafficAnalyzer {

    /// Aus DNS-Antworten gelernte IPs von Instagrams CDN.
    private var knownCDNAddresses = Set<String>()

    private var currentBurstBytes = 0
    private var lastPacketAt: Date?
    private var burstCount = 0

    func inspect(packet: Data, protocolFamily: NSNumber) {
        guard let header = IPHeader(packet: packet) else { return }

        if header.isDNSResponse {
            learnCDNAddresses(from: packet)
            return
        }

        // Nur eingehender Traffic von bekannten Instagram-CDN-IPs zählt.
        guard knownCDNAddresses.contains(header.sourceAddress) else { return }

        let now = Date()
        if let last = lastPacketAt, now.timeIntervalSince(last) > TrafficHeuristics.burstIdleGap {
            closeBurst()
        }
        currentBurstBytes += packet.count
        lastPacketAt = now
    }

    private func closeBurst() {
        if currentBurstBytes >= TrafficHeuristics.minBurstBytes {
            burstCount += 1
            persistBurst()
        }
        currentBurstBytes = 0
    }

    func flush() {
        closeBurst()
    }

    /// Schreibt einen Burst MIT ZEITSTEMPEL in den geteilten Speicher.
    ///
    /// Der Zeitstempel ist entscheidend: die Extension weiß nicht, ob
    /// Instagram gerade im Vordergrund war oder ob nur im Hintergrund
    /// vorgeladen wurde. Erst die Haupt-App verrechnet diese Bursts mit den
    /// Screen-Time-Nutzungsfenstern aus ScreenTimeEstimator.swift.
    private func persistBurst() {
        guard let defaults = UserDefaults(suiteName: SharedStore.suiteName) else { return }
        let key = "burstTimestamps"
        var timestamps = defaults.array(forKey: key) as? [Double] ?? []
        timestamps.append(Date().timeIntervalSince1970)
        defaults.set(timestamps, forKey: key)
    }

    private func learnCDNAddresses(from packet: Data) {
        // DNS-Antwort parsen: enthält der abgefragte Name einen der
        // CDN-Suffixe, werden die A/AAAA-Records in knownCDNAddresses
        // aufgenommen. (Parser hier ausgelassen.)
    }
}

/// Minimaler IP-Header-Parser. Vollständige Implementierung ausgelassen –
/// relevant sind Quell-/Ziel-Adresse, Protokoll und Port.
struct IPHeader {
    let sourceAddress: String
    let destinationAddress: String
    let isDNSResponse: Bool

    init?(packet: Data) {
        guard packet.count >= 20 else { return nil }
        // IPv4/IPv6 unterscheiden, Adressen und Ports extrahieren.
        self.sourceAddress = ""
        self.destinationAddress = ""
        self.isDNSResponse = false
        return nil
    }
}

// MARK: - Zusammenführung mit Screen Time

/// Läuft in der HAUPT-APP, nicht in der Extension. Kombiniert die beiden
/// Datenquellen zur finalen Schätzung.
enum CombinedEstimator {

    /// - Parameters:
    ///   - burstTimestamps: aus dem Netzwerk-Tunnel (siehe oben)
    ///   - activeWindows: Zeitfenster, in denen Instagram laut
    ///     DeviceActivity/Screen Time tatsächlich im Vordergrund war
    static func estimateReels(
        burstTimestamps: [Date],
        activeWindows: [DateInterval]
    ) -> Int {
        // Bursts außerhalb aktiver Nutzung verwerfen – das filtert genau den
        // Hintergrund-Prefetch heraus, der die reine Netzwerk-Zählung sonst
        // nach oben verfälscht.
        let relevant = burstTimestamps.filter { ts in
            activeWindows.contains { $0.contains(ts) }
        }
        return Int((Double(relevant.count) / TrafficHeuristics.burstsPerReel).rounded())
    }
}

// MARK: - VPN-Profil aus der Haupt-App einrichten

enum TunnelController {
    static func install() async throws {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        let manager = managers.first ?? NETunnelProviderManager()

        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = "com.example.reelmeter.tunnel"
        proto.serverAddress = "ReelMeter (lokal)" // wird dem Nutzer angezeigt

        manager.protocolConfiguration = proto
        manager.localizedDescription = "ReelMeter"
        manager.isEnabled = true

        // Löst den System-Dialog aus, in dem der Nutzer das VPN-Profil
        // ausdrücklich bestätigen muss.
        try await manager.saveToPreferences()
    }
}
