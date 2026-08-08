// ReplayKitSwipeDetector.swift
//
// OPTIONALER, genauerer Datenpfad für iOS – zählt echte Swipes statt sie aus
// Screen-Time-Dauer zu schätzen. Kosten: Nutzer muss die Aufnahme pro Sitzung
// manuell starten, iOS zeigt zwingend einen sichtbaren roten Aufnahme-Indikator
// (lässt sich nicht unterdrücken), höherer Akku-/CPU-Verbrauch.
//
// Funktionsweise:
//   1. Nutzer startet über den System-Broadcast-Picker (RPSystemBroadcastPickerView)
//      eine Bildschirmaufnahme, bevor er Instagram öffnet.
//   2. Eine Broadcast-Upload-Extension bekommt die Frames lokal (nicht über
//      Internet – "Sample Handler" Extension-Typ "Broadcast Upload").
//   3. On-device (Vision/CoreImage) wird pro Frame ein simpler Differenz-Hash
//      berechnet; ein harter Sprung zwischen zwei Frames (kompletter
//      Bildwechsel statt kontinuierlicher Bewegung) = ein Swipe.
//   4. Alle Frames werden sofort verworfen, nur der Zähler wird persistiert –
//      aus Datenschutzgründen darf hier keinerlei Bildinhalt gespeichert oder
//      übertragen werden.
//
// Architektur-Skizze, kein vollständiges, kompilierbares Extension-Target.

import ReplayKit
import CoreImage
import Foundation

final class ReelSwipeSampleHandler: RPBroadcastSampleHandler {
    private let ciContext = CIContext()
    private var lastAverageBrightness: Double?
    private var framesSinceLastSwipe = 0

    /// Wie stark sich die mittlere Helligkeit zwischen zwei Frames ändern muss,
    /// um als "harter Szenenwechsel" (= ein Swipe) statt als normale
    /// Video-Bewegung innerhalb eines Reels zu gelten. Muss in der Praxis
    /// kalibriert werden.
    private let sceneChangeThreshold = 0.18
    private let minFramesBetweenSwipes = 20 // ~0.3s bei 60fps, verhindert Doppelzählung

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let brightness = averageBrightness(of: pixelBuffer)
        defer { lastAverageBrightness = brightness }
        framesSinceLastSwipe += 1

        guard let last = lastAverageBrightness else { return }
        let delta = abs(brightness - last)

        if delta > sceneChangeThreshold && framesSinceLastSwipe > minFramesBetweenSwipes {
            framesSinceLastSwipe = 0
            SharedStore.appendUsageSeconds(0, forApp: "com.instagram") // Platzhalter
            incrementSwipeCounter()
        }
    }

    private func incrementSwipeCounter() {
        guard let defaults = UserDefaults(suiteName: SharedStore.suiteName) else { return }
        let key = "realSwipeCount.\(todayKey())"
        defaults.set(defaults.integer(forKey: key) + 1, forKey: key)
    }

    private func averageBrightness(of buffer: CVPixelBuffer) -> Double {
        let image = CIImage(cvPixelBuffer: buffer)
        let extentVector = CIVector(x: image.extent.origin.x, y: image.extent.origin.y,
                                     z: image.extent.size.width, w: image.extent.size.height)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: image, kCIInputExtentKey: extentVector
        ]), let outputImage = filter.outputImage else { return 0 }

        var pixel = [UInt8](repeating: 0, count: 4)
        ciContext.render(outputImage, toBitmap: &pixel, rowBytes: 4,
                          bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                          format: .RGBA8, colorSpace: nil)
        return (Double(pixel[0]) + Double(pixel[1]) + Double(pixel[2])) / (3 * 255)
    }

    private func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
