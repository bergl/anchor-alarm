package app.anchoralarm.anchor_alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Boot fail-safe: Android cannot restart the Flutter watch by itself after a
 * reboot (starting a location foreground service from BOOT_COMPLETED is not
 * allowed for background location on Android 14+, and the Dart isolate is
 * gone). Instead, if a watch was active when the phone went down, tell the
 * user loudly that the anchor is no longer being watched.
 *
 * LOCKED_BOOT_COMPLETED and BOOT_COMPLETED both arrive on a normal boot;
 * the notification uses a fixed id, so the second one just replaces it.
 * MY_PACKAGE_REPLACED covers an app update killing a running watch.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            Intent.ACTION_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON",
            Intent.ACTION_MY_PACKAGE_REPLACED,
            -> {
                if (WatchFailsafe.isWatchActive(context)) {
                    WatchFailsafe.postInterruptedNotification(context)
                }
            }
        }
    }
}
