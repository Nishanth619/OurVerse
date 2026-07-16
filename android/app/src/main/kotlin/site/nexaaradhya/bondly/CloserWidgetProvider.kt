package site.nexaaradhya.bondly

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.View
import android.widget.RemoteViews
import android.graphics.BitmapFactory
import java.io.File
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.URL

/**
 * CloserWidgetProvider
 *
 * Reads question/mood data written by the Flutter side via HomeWidget.saveWidgetData()
 * and renders it into the glassmorphism Android App Widget layout.
 *
 * Keys written from Flutter:
 *   - "widget_mode"                → "question" | "mood"
 *   - "widget_question"            → Today's question text
 *   - "widget_my_emoji"            → My own selected mood emoji
 *   - "widget_partner_emoji"       → Partner's selected mood emoji
 *   - "widget_partner_device_id"   → Partner's device ID for background ping
 *
 * Emoji bubble tap behaviour (NEW):
 *   - Vibrates this device locally (subtle double-buzz).
 *   - Sends an HTTP POST to Vercel in a background thread → triggers push
 *     notification on partner's device ("Your partner is pinging you! 👋").
 *   - Does NOT open the Flutter app.
 */
class CloserWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: android.content.SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.closer_widget)

            val widgetMode = widgetData.getString("widget_mode", "question") ?: "question"

            if (widgetMode == "mood") {
                // ── MOOD MODE ─────────────────────────────────────────────────
                val myEmoji = widgetData.getString("widget_my_emoji", null)
                    ?.takeIf { it.isNotBlank() } ?: "😊"
                val partnerEmoji = widgetData.getString("widget_partner_emoji", null)
                    ?.takeIf { it.isNotBlank() } ?: "⏳"

                views.setTextViewText(R.id.widget_label, "TODAY'S MOOD")

                // Show mood row, hide others
                views.setViewVisibility(R.id.widget_mood_row, View.VISIBLE)
                views.setViewVisibility(R.id.widget_content, View.GONE)
                views.setViewVisibility(R.id.widget_flash_container, View.GONE)

                // Set both emoji values
                views.setTextViewText(R.id.widget_my_emoji, myEmoji)
                views.setTextViewText(R.id.widget_partner_emoji, partnerEmoji)

            } else if (widgetMode == "flash") {
                // ── FLASH MODE ───────────────────────────────────────────────
                val flashPath = widgetData.getString("widget_partner_flash_path", null)
                
                views.setTextViewText(R.id.widget_label, "TODAY'S FLASH")
                
                // Show flash container, hide mood/question rows
                views.setViewVisibility(R.id.widget_flash_container, View.VISIBLE)
                views.setViewVisibility(R.id.widget_content, View.GONE)
                views.setViewVisibility(R.id.widget_mood_row, View.GONE)
                
                if (flashPath != null && flashPath.isNotBlank()) {
                    val file = File(flashPath)
                    if (file.exists()) {
                        val bitmap = BitmapFactory.decodeFile(file.absolutePath)
                        if (bitmap != null) {
                            views.setImageViewBitmap(R.id.widget_flash_image, bitmap)
                        } else {
                            views.setViewVisibility(R.id.widget_flash_container, View.GONE)
                            views.setViewVisibility(R.id.widget_content, View.VISIBLE)
                            views.setTextViewText(R.id.widget_content, "Tap to open Flash! 📸")
                        }
                    } else {
                        views.setViewVisibility(R.id.widget_flash_container, View.GONE)
                        views.setViewVisibility(R.id.widget_content, View.VISIBLE)
                        views.setTextViewText(R.id.widget_content, "Tap to open Flash! 📸")
                    }
                } else {
                    views.setViewVisibility(R.id.widget_flash_container, View.GONE)
                    views.setViewVisibility(R.id.widget_content, View.VISIBLE)
                    views.setTextViewText(R.id.widget_content, "Waiting for partner's Flash... ⏳")
                }

            } else {
                // ── QUESTION MODE ─────────────────────────────────────────────
                val question = widgetData.getString(
                    "widget_question",
                    "Open Closer to see today's question"
                ) ?: "Open Closer to see today's question"

                views.setTextViewText(R.id.widget_label, "TODAY'S QUESTION")
                views.setTextViewText(R.id.widget_content, question)

                // Show question text, hide mood row and flash container
                views.setViewVisibility(R.id.widget_content, View.VISIBLE)
                views.setViewVisibility(R.id.widget_mood_row, View.GONE)
                views.setViewVisibility(R.id.widget_flash_container, View.GONE)
            }

            // ── Tap question/footer → Open App ────────────────────────────────
            val launchIntent = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
            if (launchIntent != null) {
                val launchPi = android.app.PendingIntent.getActivity(
                    context, 0, launchIntent,
                    android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                            android.app.PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(R.id.widget_content, launchPi)
                views.setOnClickPendingIntent(R.id.widget_footer, launchPi)
                views.setOnClickPendingIntent(R.id.widget_flash_container, launchPi)
            }

            // ── Emoji bubble taps → background PING (no app launch) ───────────
            val myEmoji   = widgetData.getString("widget_my_emoji",      null) ?: "😊"
            val partEmoji = widgetData.getString("widget_partner_emoji", null) ?: "⏳"

            val myTapIntent = Intent(context, CloserWidgetProvider::class.java).apply {
                action = ACTION_EMOJI_TAP
                putExtra(EXTRA_EMOJI, myEmoji)
                putExtra(EXTRA_TAPPER, "me")
            }
            val myTapPi = android.app.PendingIntent.getBroadcast(
                context, 1, myTapIntent,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                        android.app.PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_my_mood_block, myTapPi)

            val partTapIntent = Intent(context, CloserWidgetProvider::class.java).apply {
                action = ACTION_EMOJI_TAP
                putExtra(EXTRA_EMOJI, partEmoji)
                putExtra(EXTRA_TAPPER, "partner")
            }
            val partTapPi = android.app.PendingIntent.getBroadcast(
                context, 2, partTapIntent,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                        android.app.PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_partner_mood_block, partTapPi)

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    // ── Handle emoji bubble tap ────────────────────────────────────────────────
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)

        if (intent.action == ACTION_EMOJI_TAP) {
            val emoji = intent.getStringExtra(EXTRA_EMOJI) ?: return

            // 1. Vibrate this device (subtle double-buzz — no app needed)
            vibrateDevice(context)

            // 2. Read partner device ID from SharedPreferences.
            //    home_widget saves to "<packageName>_preferences" with raw keys.
            //    Flutter's shared_preferences saves to "FlutterSharedPreferences"
            //    with "flutter." prefix. Try both to be safe.
            val homeWidgetPrefs = context.getSharedPreferences(
                "${context.packageName}_preferences", Context.MODE_PRIVATE
            )
            val flutterPrefs = context.getSharedPreferences(
                "FlutterSharedPreferences", Context.MODE_PRIVATE
            )

            val partnerId =
                homeWidgetPrefs.getString("widget_partner_device_id", null)?.takeIf { it.isNotBlank() }
                    ?: flutterPrefs.getString("flutter.widget_partner_device_id", null)?.takeIf { it.isNotBlank() }

            // 3. Send background HTTP ping to Vercel → partner gets push notification
            if (!partnerId.isNullOrBlank()) {
                sendPingInBackground(partnerId, emoji)
            }

            // NOTE: We intentionally do NOT open the app here.
        }
    }

    // ── Vibrate helper ────────────────────────────────────────────────────────
    private fun vibrateDevice(context: Context) {
        try {
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                vm?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            } ?: return

            if (Build.VERSION.SDK_INT >= 33) {
                val attr = android.os.VibrationAttributes.Builder()
                    .setUsage(android.os.VibrationAttributes.USAGE_ALARM)
                    .build()
                vibrator.vibrate(VibrationEffect.createPredefined(VibrationEffect.EFFECT_HEAVY_CLICK), attr)
            } else if (Build.VERSION.SDK_INT >= 29) {
                val attr = android.media.AudioAttributes.Builder()
                    .setUsage(android.media.AudioAttributes.USAGE_ALARM)
                    .build()
                vibrator.vibrate(VibrationEffect.createPredefined(VibrationEffect.EFFECT_HEAVY_CLICK), attr)
            } else if (Build.VERSION.SDK_INT >= 26) {
                val attr = android.media.AudioAttributes.Builder()
                    .setUsage(android.media.AudioAttributes.USAGE_ALARM)
                    .build()
                vibrator.vibrate(VibrationEffect.createOneShot(150, 255), attr)
            } else {
                val attr = android.media.AudioAttributes.Builder()
                    .setUsage(android.media.AudioAttributes.USAGE_ALARM)
                    .build()
                @Suppress("DEPRECATION")
                vibrator.vibrate(150, attr)
            }
        } catch (_: Exception) { }
    }

    // ── Background HTTP ping ───────────────────────────────────────────────────
    private fun sendPingInBackground(partnerId: String, emoji: String) {
        Thread {
            try {
                val url = URL("https://closerbackend-1.vercel.app/api/ping")
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "POST"
                conn.setRequestProperty("Content-Type", "application/json")
                conn.doOutput = true
                conn.connectTimeout = 8000
                conn.readTimeout   = 8000

                val body = """{"emoji":"$emoji","partnerDeviceId":"$partnerId"}"""
                val out: OutputStream = conn.outputStream
                out.write(body.toByteArray(Charsets.UTF_8))
                out.flush()
                out.close()

                // Read response to complete the request (ignore result)
                conn.responseCode
                conn.disconnect()
            } catch (_: Exception) { }
        }.start()
    }

    companion object {
        const val ACTION_EMOJI_TAP = "site.nexaaradhya.bondly.WIDGET_EMOJI_TAP"
        const val EXTRA_EMOJI      = "extra_emoji"
        const val EXTRA_TAPPER     = "extra_tapper"
    }
}
