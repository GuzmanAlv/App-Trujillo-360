package pe.com.alertaciudadana.alerta_ciudadana

import io.flutter.embedding.android.FlutterActivity
import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.Uri
import android.content.pm.PackageManager
import android.graphics.Color
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val incomingAlarm by lazy { SosIncomingAlarm(this) }
    private val userSignals by lazy { SosUserSignals(this) }
    private val progressSignals by lazy { SosProgressSignals(this) { incomingAlarm.active || userSignals.active } }
    private var callNotice: SosCallNotice? = null
    private var activityVisible = false
    private var channel: MethodChannel? = null
    private var permissionResult: MethodChannel.Result? = null
    private val alertChannel = "nearby_incidents"


    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel(
            alertChannel, "Incidencias a 500 metros", NotificationManager.IMPORTANCE_HIGH))
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel(
            "trujillo_push", "Avisos de Trujillo 360", NotificationManager.IMPORTANCE_HIGH))
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel("trujillo_sos_quiet", "Avisos durante una atención SOS", NotificationManager.IMPORTANCE_DEFAULT).apply {
                setSound(null, null); enableVibration(false)
            })
            manager.createNotificationChannel(NotificationChannel("trujillo_sos_calls", "Llamadas del operador SOS", NotificationManager.IMPORTANCE_HIGH).apply {
                setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE), AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE).build())
                enableVibration(true); vibrationPattern = longArrayOf(0, 550, 250, 550)
            })
            manager.createNotificationChannel(NotificationChannel("trujillo_sos_arrival", "Llegada de la policía al SOS", NotificationManager.IMPORTANCE_HIGH).apply {
                setSound(Uri.parse("android.resource://$packageName/${R.raw.sos_arrival}"), AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT).build())
                enableVibration(true); vibrationPattern = longArrayOf(0, 200, 800, 200, 800, 200, 800, 200)
            })
        }
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "trujillo360/proximity")
        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "sosProgressSignal" -> {
                    progressSignals.update(if (activityVisible) call.argument<String>("mode") else null)
                    result.success(null)
                }
                "sosCallNotice" -> {
                    if (call.argument<Boolean>("enabled") == true && activityVisible) {
                        if (callNotice == null) callNotice = SosCallNotice(this)
                        callNotice?.play()
                    } else callNotice?.stop()
                    result.success(null)
                }
                "sosCallbackRing" -> {
                    if (call.argument<Boolean>("enabled") == true && activityVisible) userSignals.startRing() else userSignals.stopRing()
                    result.success(null)
                }
                "sosArrivalSignal" -> { if (activityVisible) userSignals.arrival(); result.success(null) }
                "stopSosArrivalSignal" -> { userSignals.stopArrival(); result.success(null) }
                "sosIncomingAlarm" -> {
                    if (call.argument<Boolean>("enabled") == true && activityVisible) incomingAlarm.start()
                    else incomingAlarm.stop()
                    result.success(null)
                }
                "sosVolumeStatus" -> {
                    val (enabled, testOnly) = SosVolumeConfig.read(this)
                    val accessibility = getSystemService(AccessibilityManager::class.java)
                    val active = accessibility.getEnabledAccessibilityServiceList(
                        android.accessibilityservice.AccessibilityServiceInfo.FEEDBACK_ALL_MASK
                    ).any { it.resolveInfo.serviceInfo.name == SosVolumeService::class.java.name }
                    result.success(mapOf(
                        "enabled" to enabled,
                        "test_only" to testOnly,
                        "permission" to active
                    ))
                }
                "setSosVolume" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    val testOnly = call.argument<Boolean>("test_only") ?: true
                    SosVolumeConfig.write(this, enabled, testOnly)
                    result.success(null)
                }
                "openSosAccessibility" -> {
                    startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    result.success(null)
                }
                "takeSosSettingsRoute" -> {
                    result.success(intent.getBooleanExtra("open_sos_settings", false))
                    intent.removeExtra("open_sos_settings")
                }
                "openNotificationSettings" -> {
                    val target = if (Build.VERSION.SDK_INT >= 26)
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    else Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
                    startActivity(target)
                    result.success(null)
                }
                "clearPush" -> { manager.cancelAll(); result.success(null) }
                "takePush" -> {
                    result.success(intent.getStringExtra("push_payload"))
                    intent.removeExtra("push_payload")
                }
                "dial" -> {
                    try {
                        startActivity(Intent(Intent.ACTION_DIAL, Uri.parse("tel:044298734")))
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("dial_unavailable", "No se pudo abrir el teléfono", null)
                    }
                }
                "enable" -> {
                    if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        if (permissionResult != null) result.success(false)
                        else {
                            permissionResult = result
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 500)
                        }
                    } else result.success(manager.areNotificationsEnabled())
                }
                "show", "showPush" -> {
                    val isPush = call.method == "showPush"
                    val id = call.argument<String>("id") ?: ""
                    val payload = call.argument<String>("payload") ?: ""
                    if (manager.areNotificationsEnabled()) {
                        val target = Intent(this, MainActivity::class.java)
                            .setAction("trujillo360.alert.$id")
                            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                            .putExtra(if (isPush) "push_payload" else "nearby_payload", payload)
                        val pending = PendingIntent.getActivity(this, id.hashCode(), target,
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                        val quiet = call.argument<Boolean>("quiet") == true
                        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, if (quiet) "trujillo_sos_quiet" else if (isPush) "trujillo_push" else alertChannel) else Notification.Builder(this)
                        if (quiet && Build.VERSION.SDK_INT < 26) builder.setSound(null).setVibrate(longArrayOf(0))
                        val notification = builder
                            .setSmallIcon(R.drawable.ic_notification)
                            .setColor(Color.rgb(211, 47, 47))
                            .setContentTitle(call.argument<String>("title"))
                            .setContentText(call.argument<String>("body"))
                            .setStyle(Notification.BigTextStyle().bigText(call.argument<String>("body")))
                            .setContentIntent(pending)
                            .setVisibility(Notification.VISIBILITY_PRIVATE)
                            .setAutoCancel(true).build()
                        manager.notify(id.hashCode(), notification)
                    }
                    result.success(null)
                }
                "takePending" -> {
                    result.success(intent.getStringExtra("nearby_payload"))
                    intent.removeExtra("nearby_payload")
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        activityVisible = true
    }

    override fun onPause() {
        activityVisible = false
        progressSignals.stop()
        incomingAlarm.stop()
        userSignals.stop()
        callNotice?.stop()
        super.onPause()
    }

    override fun onDestroy() {
        progressSignals.stop()
        callNotice?.dispose()
        incomingAlarm.stop()
        userSignals.stop()
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.getBooleanExtra("open_sos_settings", false)) {
            channel?.invokeMethod("openSosSettings", null)
            intent.removeExtra("open_sos_settings")
        }
        intent.getStringExtra("push_payload")?.let {
            channel?.invokeMethod("openPush", it)
            intent.removeExtra("push_payload")
        }
        intent.getStringExtra("nearby_payload")?.let {
            channel?.invokeMethod("open", it)
            intent.removeExtra("nearby_payload")
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 500) {
            permissionResult?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            permissionResult = null
        }
    }
}
