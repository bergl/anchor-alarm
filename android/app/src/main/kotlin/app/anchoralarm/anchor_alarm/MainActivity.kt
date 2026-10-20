package app.anchoralarm.anchor_alarm

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var savedAlarmVolume: Int? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // Fail-safe flag + battery optimisation (lib/services/failsafe/failsafe.dart).
        MethodChannel(messenger, "anchor_alarm/failsafe").setMethodCallHandler { call, result ->
            when (call.method) {
                "setWatchActive" -> {
                    val active = call.argument<Boolean>("active") ?: false
                    WatchFailsafe.setWatchActive(applicationContext, active)
                    result.success(null)
                }
                "isIgnoringBatteryOptimizations" -> result.success(isIgnoringBatteryOptimizations())
                "requestIgnoreBatteryOptimizations" -> {
                    requestIgnoreBatteryOptimizations()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Alarm stream volume (lib/services/alarm/audio_alarm_output.dart).
        MethodChannel(messenger, "anchor_alarm/audio").setMethodCallHandler { call, result ->
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            try {
                when (call.method) {
                    "raiseAlarmVolume" -> {
                        if (savedAlarmVolume == null) {
                            savedAlarmVolume = am.getStreamVolume(AudioManager.STREAM_ALARM)
                        }
                        am.setStreamVolume(
                            AudioManager.STREAM_ALARM,
                            am.getStreamMaxVolume(AudioManager.STREAM_ALARM),
                            0,
                        )
                        result.success(null)
                    }
                    "restoreAlarmVolume" -> {
                        savedAlarmVolume?.let { am.setStreamVolume(AudioManager.STREAM_ALARM, it, 0) }
                        savedAlarmVolume = null
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: SecurityException) {
                // e.g. volume changes blocked by DnD policy on some devices.
                result.success(null)
            }
        }
    }

    /**
     * Back at the root of the Flutter navigator: move the task to the
     * background instead of finishing the activity. Finishing would destroy
     * the Flutter engine and with it a running anchor watch.
     */
    override fun popSystemNavigator(): Boolean {
        moveTaskToBack(true)
        return true
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    @SuppressLint("BatteryLife") // An anchor alarm is a legitimate exemption use case.
    private fun requestIgnoreBatteryOptimizations() {
        if (isIgnoringBatteryOptimizations()) return
        try {
            startActivity(
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                    .setData(Uri.parse("package:$packageName")),
            )
        } catch (e: Exception) {
            // Some OEM builds lack the dialog; fall back to the settings list.
            try {
                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            } catch (_: Exception) {
            }
        }
    }
}
