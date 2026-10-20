package app.anchoralarm.anchor_alarm

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

/**
 * "Watch active" flag owned by the app (separate prefs file, not the Flutter
 * shared_preferences one) and the "interrupted by restart" notification.
 *
 * The flag lives in device-protected storage so that it can be read during
 * LOCKED_BOOT_COMPLETED, before the user unlocks the phone after a reboot.
 */
object WatchFailsafe {
    private const val PREFS = "anchor_alarm_failsafe"
    private const val KEY_ACTIVE = "watch_active"
    private const val KEY_SINCE = "watch_active_since"

    /** Must match NotificationChannels.alarm in Dart. */
    const val ALARM_CHANNEL_ID = "anchor_alarm"
    private const val NOTIFICATION_ID = 900

    private fun prefs(context: Context): SharedPreferences {
        val storage = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            context.createDeviceProtectedStorageContext()
        } else {
            context
        }
        return storage.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    }

    fun setWatchActive(context: Context, active: Boolean) {
        prefs(context).edit()
            .putBoolean(KEY_ACTIVE, active)
            .putLong(KEY_SINCE, if (active) System.currentTimeMillis() else 0L)
            .apply()
    }

    fun isWatchActive(context: Context): Boolean = prefs(context).getBoolean(KEY_ACTIVE, false)

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(NotificationManager::class.java) ?: return
        if (nm.getNotificationChannel(ALARM_CHANNEL_ID) != null) return
        // Same settings as the Dart side creates (first creator wins).
        val channel = NotificationChannel(ALARM_CHANNEL_ID, "Anchor alarm", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "Anchor dragging, GPS lost, critical battery"
            enableVibration(true)
            setBypassDnd(true)
            setSound(
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                    ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
        }
        nm.createNotificationChannel(channel)
    }

    fun postInterruptedNotification(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        ensureChannel(context)
        val launch = (context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(context, MainActivity::class.java)).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra("anchor_alarm_resume", true)
        }
        val pending = PendingIntent.getActivity(
            context,
            NOTIFICATION_ID,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(context, ALARM_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_anchor)
            .setContentTitle("Anchor watch interrupted by restart")
            .setContentText("Anchor watch interrupted by restart — tap to resume")
            .setStyle(
                NotificationCompat.BigTextStyle().bigText(
                    "The phone restarted while the anchor watch was running. " +
                        "The anchor is NOT being watched. Tap to resume.",
                ),
            )
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(true)
            .setContentIntent(pending)
            .build()
        try {
            NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification)
        } catch (e: SecurityException) {
            // Notification permission revoked; nothing else we can do.
        }
    }
}
