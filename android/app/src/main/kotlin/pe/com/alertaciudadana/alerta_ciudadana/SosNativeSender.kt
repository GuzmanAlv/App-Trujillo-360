package pe.com.alertaciudadana.alerta_ciudadana

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.os.SystemClock
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import com.google.android.gms.tasks.Tasks
import com.google.firebase.FirebaseApp
import com.google.firebase.auth.FirebaseAuth
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URI
import java.util.UUID
import java.util.concurrent.TimeUnit

internal class SosNativeSender(private val context: Context) {
    fun checkOnly(): Boolean {
        if (context.checkSelfPermission(Manifest.permission.ACCESS_BACKGROUND_LOCATION) != PackageManager.PERMISSION_GRANTED ||
            context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) return false
        if (FirebaseApp.initializeApp(context) == null) return false
        if (FirebaseAuth.getInstance().currentUser == null) return false
        return currentLocation() != null
    }

    fun send(): Boolean {
        if (context.checkSelfPermission(Manifest.permission.ACCESS_BACKGROUND_LOCATION) != PackageManager.PERMISSION_GRANTED ||
            context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) return false
        val manager = context.getSystemService(LocationManager::class.java)
        if (!manager.isProviderEnabled(LocationManager.GPS_PROVIDER) &&
            !manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) return false
        if (FirebaseApp.initializeApp(context) == null) return false
        val user = FirebaseAuth.getInstance().currentUser ?: return false
        val prefs = context.getSharedPreferences("sos_native_pending", Context.MODE_PRIVATE)
        val pending = if (prefs.getString("owner", null) == user.uid)
            prefs.getString("request_id", null) else null
        val requestId: String
        val latitude: Double
        val longitude: Double
        if (pending != null) {
            requestId = pending
            latitude = prefs.getString("latitude", null)?.toDoubleOrNull() ?: return false
            longitude = prefs.getString("longitude", null)?.toDoubleOrNull() ?: return false
        } else {
            val location = currentLocation() ?: return false
            requestId = UUID.randomUUID().toString()
            latitude = location.latitude
            longitude = location.longitude
            if (!prefs.edit().putString("owner", user.uid)
                    .putString("request_id", requestId)
                    .putString("latitude", latitude.toString())
                    .putString("longitude", longitude.toString()).commit()) return false
        }
        val endpoint = URI(BuildConfig.BACKEND_URL).resolve("/sos")
        if (endpoint.scheme != "https" || endpoint.host.isNullOrBlank() || endpoint.userInfo != null) return false
        val body = JSONObject()
            .put("request_id", requestId)
            .put("latitude", latitude)
            .put("longitude", longitude).toString()
        for (attempt in 0..1) {
            if (FirebaseAuth.getInstance().currentUser?.uid != user.uid) return false
            val token = Tasks.await(user.getIdToken(attempt == 1), 15, TimeUnit.SECONDS).token ?: return false
            val connection = endpoint.toURL().openConnection() as HttpURLConnection
            try {
                connection.requestMethod = "POST"
                connection.instanceFollowRedirects = false
                connection.connectTimeout = 15_000
                connection.readTimeout = 90_000
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json")
                connection.setRequestProperty("Authorization", "Bearer $token")
                connection.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
                if (connection.responseCode == 401 && attempt == 0) continue
                if (connection.responseCode != 200) return false
                val reply = JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
                if ((!reply.optBoolean("existing_active") && reply.optString("request_id") != requestId) || reply.optString("source") != "sos") return false
                prefs.edit().clear().commit()
                return true
            } finally {
                connection.disconnect()
            }
        }
        return false
    }

    private fun currentLocation(): Location? {
        val provider = LocationServices.getFusedLocationProviderClient(context)
        val current = Tasks.await(
            provider.getCurrentLocation(Priority.PRIORITY_HIGH_ACCURACY, CancellationTokenSource().token),
            20, TimeUnit.SECONDS
        )
        if (current != null) return current
        val last = Tasks.await(provider.lastLocation, 5, TimeUnit.SECONDS) ?: return null
        val age = SystemClock.elapsedRealtimeNanos() - last.elapsedRealtimeNanos
        return last.takeIf { age in 0L..120_000_000_000L && it.accuracy <= 100f }
    }
}
