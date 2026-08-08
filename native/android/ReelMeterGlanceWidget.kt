// ReelMeterGlanceWidget.kt
//
// Home-Screen-Widget via Jetpack Glance. Liest ausschließlich die von
// ReelAccessibilityService.kt geschriebenen SharedPreferences – kein eigener
// Zugriff auf Instagram.
//
// Architektur-Skizze, kein vollständiges, kompilierbares Gradle-Modul.

package com.example.reelmeter

import android.content.Context
import androidx.glance.GlanceId
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.provideContent
import androidx.glance.layout.Column
import androidx.glance.layout.fillMaxSize
import androidx.glance.text.Text
import java.time.LocalDate

class ReelMeterWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val prefs = context.getSharedPreferences("reelmeter_prefs", Context.MODE_PRIVATE)
        val todayKey = "reels_${LocalDate.now()}"
        val reelsToday = prefs.getInt(todayKey, 0)
        val reelsAllTime = prefs.getInt("reels_all_time", 0)
        val distanceCm = prefs.getFloat("distance_cm_all_time", 0f)
        val kmAllTime = distanceCm / 100_000f

        provideContent {
            Column(modifier = androidx.glance.GlanceModifier.fillMaxSize()) {
                Text("ReelMeter")
                Text("$reelsToday Reels heute")
                Text("$reelsAllTime Reels gesamt")
                Text("%.1f km gesamt".format(kmAllTime))
            }
        }
    }
}

class ReelMeterWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = ReelMeterWidget()
}
