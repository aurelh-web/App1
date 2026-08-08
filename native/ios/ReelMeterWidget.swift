// ReelMeterWidget.swift
//
// WidgetKit-Extension-Skizze für den Home-Screen-Widget. Liest ausschließlich
// die im App Group Storage abgelegten, bereits aufbereiteten Zahlen – die
// Widget-Extension selbst hat keinen Zugriff auf DeviceActivity oder Instagram.
//
// Architektur-Skizze, kein vollständiges Xcode-Target.

import WidgetKit
import SwiftUI

struct ReelMeterEntry: TimelineEntry {
    let date: Date
    let reelsToday: Int
    let metersToday: Double
    let reelsAllTime: Int
    let kmAllTime: Double
}

struct ReelMeterTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> ReelMeterEntry {
        ReelMeterEntry(date: Date(), reelsToday: 42, metersToday: 6.5, reelsAllTime: 1200, kmAllTime: 176)
    }

    func getSnapshot(in context: Context, completion: @escaping (ReelMeterEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ReelMeterEntry>) -> Void) {
        let entry = readEntry()
        // Widgets aktualisieren sich nicht live – iOS entscheidet, wie oft ein
        // Reload passiert (Budget von wenigen Reloads/Stunde). Ein vorgeschlagenes
        // nächstes Update reicht als Hinweis.
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func readEntry() -> ReelMeterEntry {
        let defaults = UserDefaults(suiteName: SharedStore.suiteName)
        return ReelMeterEntry(
            date: Date(),
            reelsToday: defaults?.integer(forKey: "reelsToday") ?? 0,
            metersToday: defaults?.double(forKey: "metersToday") ?? 0,
            reelsAllTime: defaults?.integer(forKey: "reelsAllTime") ?? 0,
            kmAllTime: defaults?.double(forKey: "kmAllTime") ?? 0
        )
    }
}

struct ReelMeterWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: ReelMeterEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("ReelMeter", systemImage: "film")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("\(entry.reelsToday)")
                .font(.system(size: 30, weight: .bold))
            Text("Reels heute")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(formatMeters(entry.metersToday))
                .font(.headline)
            Text("Strecke heute")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if family == .systemMedium {
                Divider()
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(entry.reelsAllTime)").font(.title3.bold())
                        Text("Reels gesamt").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(String(format: "%.1f km", entry.kmAllTime)).font(.title3.bold())
                        Text("Strecke gesamt").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
    }

    private func formatMeters(_ m: Double) -> String {
        m < 1000 ? String(format: "%.0f m", m) : String(format: "%.2f km", m / 1000)
    }
}

struct ReelMeterWidget: Widget {
    let kind = "ReelMeterWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ReelMeterTimelineProvider()) { entry in
            ReelMeterWidgetView(entry: entry)
        }
        .configurationDisplayName("ReelMeter")
        .description("Geschätzte Reels & Strecke basierend auf deiner Screen-Time-Nutzung von Instagram.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
