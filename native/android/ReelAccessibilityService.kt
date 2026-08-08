// ReelAccessibilityService.kt
//
// Android erlaubt einer App mit ausdrücklicher Nutzerfreigabe (Einstellungen ->
// Bedienungshilfen), AccessibilityEvents systemweit zu empfangen – auch aus
// Instagram, weil Instagram Screenreadern zugänglich sein muss. Damit sind
// hier ECHTE Swipe-/Scroll-Events zählbar, keine Schätzung wie bei iOS.
//
// Wichtig: Google Play erlaubt die Bedienungshilfen-API laut Policy nur für
// echte Bedienungshilfen-Zwecke. Eine App, die sie zweckfremd fürs
// Nutzungs-Tracking verwendet, riskiert eine Ablehnung/Entfernung im Play
// Store. Realistischer Vertriebsweg: Sideload (APK direkt, F-Droid) statt
// Play Store, oder klar als Selbstexperiment/offene-Source-Tool kommuniziert.
//
// Architektur-Skizze, kein vollständiges, kompilierbares Gradle-Modul.

package com.example.reelmeter

import android.accessibilityservice.AccessibilityService
import android.content.SharedPreferences
import android.util.DisplayMetrics
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import java.time.LocalDate

class ReelAccessibilityService : AccessibilityService() {

    private val instagramPackage = "com.instagram.android"
    private var lastEventAtMillis = 0L
    private val minMillisBetweenSwipes = 250L // entprellt Doppel-Events

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        if (event.packageName != instagramPackage) return

        // TYPE_VIEW_SCROLLED feuert u.a. bei RecyclerView/ViewPager2-Wechseln,
        // wie sie der Reels-Feed intern nutzt. Instagrams interne View-IDs sind
        // nicht öffentlich/stabil dokumentiert, daher hier bewusst ohne
        // View-ID-Filter – in der Praxis muss man das per UI-Inspektor
        // (z.B. `adb shell uiautomator dump`) verifizieren und ggf. auf
        // TYPE_WINDOW_CONTENT_CHANGED umstellen, falls sich Instagrams
        // View-Hierarchie ändert.
        val isScrollEvent = event.eventType == AccessibilityEvent.TYPE_VIEW_SCROLLED
        if (!isScrollEvent) return

        val now = System.currentTimeMillis()
        if (now - lastEventAtMillis < minMillisBetweenSwipes) return
        lastEventAtMillis = now

        registerSwipe()
    }

    override fun onInterrupt() {}

    private fun registerSwipe() {
        val prefs = sharedPrefs()
        val todayKey = "reels_${LocalDate.now()}"
        val allTimeKey = "reels_all_time"
        val distanceKey = "distance_cm_all_time"

        val screenHeightCm = screenHeightCm()

        prefs.edit()
            .putInt(todayKey, prefs.getInt(todayKey, 0) + 1)
            .putInt(allTimeKey, prefs.getInt(allTimeKey, 0) + 1)
            .putFloat(distanceKey, prefs.getFloat(distanceKey, 0f) + screenHeightCm)
            .apply()

        // Glance-Widget über WorkManager/updateAll() zum Neuzeichnen anstoßen,
        // siehe ReelMeterGlanceWidget.kt.
    }

    private fun screenHeightCm(): Float {
        val metrics = DisplayMetrics()
        (getSystemService(WINDOW_SERVICE) as WindowManager).defaultDisplay.getRealMetrics(metrics)
        val heightInches = metrics.heightPixels / metrics.ydpi
        return heightInches * 2.54f
    }

    private fun sharedPrefs(): SharedPreferences =
        getSharedPreferences("reelmeter_prefs", MODE_PRIVATE)
}
