package pe.com.alertaciudadana.alerta_ciudadana

import io.flutter.embedding.android.FlutterActivity
import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var permissionResult: MethodChannel.Result? = null
    private val alertChannel = "nearby_incidents"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel(
            alertChannel, "Incidencias a 500 metros", NotificationManager.IMPORTANCE_HIGH))
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "trujillo360/proximity")
        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "enable" -> {
                    if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        if (permissionResult != null) result.success(false)
                        else {
                            permissionResult = result
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 500)
                        }
                    } else result.success(manager.areNotificationsEnabled())
                }
                "show" -> {
                    val id = call.argument<String>("id") ?: ""
                    val payload = call.argument<String>("payload") ?: ""
                    if (manager.areNotificationsEnabled()) {
                        val target = Intent(this, MainActivity::class.java)
                            .setAction("trujillo360.alert.$id")
                            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                            .putExtra("nearby_payload", payload)
                        val pending = PendingIntent.getActivity(this, id.hashCode(), target,
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, alertChannel) else Notification.Builder(this)
                        val notification = builder
                            .setSmallIcon(R.drawable.ic_notification)
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

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
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
