package pe.com.alertaciudadana.alerta_ciudadana

import android.Manifest
import android.app.*
import android.content.Intent
import android.content.pm.PackageManager
import android.os.*
import com.google.android.gms.location.*
import com.google.android.gms.tasks.Tasks
import com.google.firebase.auth.FirebaseAuth
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URI
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** Location foreground service survives leaving the activity and screen lock. */
class SosArrivalService : Service() {
    private val worker = Executors.newSingleThreadExecutor()
    private val busy = AtomicBoolean(false)
    private val handler = Handler(Looper.getMainLooper())
    private var owner: String? = null
    @Volatile private var destroyed = false
    @Volatile private var foregroundStarted = false
    @Volatile private var lastLocation: android.location.Location? = null
    private val locationClient by lazy { LocationServices.getFusedLocationProviderClient(this) }
    private val locationCallback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) { lastLocation = result.lastLocation }
    }
    private val pulse = object : Runnable {
        override fun run() {
            if (destroyed) return
            if (busy.compareAndSet(false, true)) worker.execute {
                val wake = getSystemService(PowerManager::class.java)
                    .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Trujillo360:Arrival")
                wake.acquire(60000)
                try { checkArrival() } catch (_: Exception) {
                    updateNotice("Conexión pendiente. Se reintentará la llegada.")
                } finally {
                    if (wake.isHeld) wake.release()
                    busy.set(false)
                }
            }
            handler.postDelayed(this, 12000)
        }
    }
    private fun updateNotice(text: String) {
        if (destroyed) return
        val open = PendingIntent.getActivity(this, 9031, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, "sos_arrival_tracking") else Notification.Builder(this)
        val notification = builder
            .setSmallIcon(R.drawable.ic_notification).setContentTitle("Atención SOS en curso")
            .setContentText(text).setContentIntent(open).setOngoing(true)
            .setOnlyAlertOnce(true).build()
        if (foregroundStarted) {
            getSystemService(NotificationManager::class.java).notify(9031, notification)
        } else {
            try {
                startForeground(9031, notification)
                foregroundStarted = true
            } catch (_: RuntimeException) { stopSelf() }
        }
    }
    override fun onCreate() {
        super.onCreate()
        owner = FirebaseAuth.getInstance().currentUser?.uid
        if (Build.VERSION.SDK_INT >= 26) getSystemService(NotificationManager::class.java)
            .createNotificationChannel(NotificationChannel("sos_arrival_tracking", "Llegada al SOS",
                NotificationManager.IMPORTANCE_LOW))
        if (owner == null || checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            stopSelf()
            return
        }
        updateNotice("Ubicación activa para comprobar la llegada al caso.")
        if (!foregroundStarted) return
        try {
            locationClient.requestLocationUpdates(
                LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 12000).setMinUpdateIntervalMillis(5000).build(),
                locationCallback, Looper.getMainLooper()).addOnFailureListener { stopSelf() }
            handler.post(pulse)
        } catch (_: SecurityException) { stopSelf() }
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_NOT_STICKY
    private fun request(path: String, body: JSONObject? = null): String {
        val user = FirebaseAuth.getInstance().currentUser ?: throw SecurityException()
        if (user.uid != owner) throw SecurityException()
        val endpoint = URI(BuildConfig.BACKEND_URL).resolve(path)
        require(endpoint.scheme == "https" && endpoint.host != null && endpoint.userInfo == null)
        for (attempt in 0..1) {
            val token = Tasks.await(user.getIdToken(attempt == 1), 10, TimeUnit.SECONDS).token ?: throw SecurityException()
            if (destroyed || FirebaseAuth.getInstance().currentUser?.uid != owner) throw SecurityException()
            val connection = endpoint.toURL().openConnection() as HttpURLConnection
            try {
                connection.connectTimeout = 8000
                connection.readTimeout = 8000
                connection.instanceFollowRedirects = false
                connection.setRequestProperty("Authorization", "Bearer $token")
                if (body != null) {
                    connection.requestMethod = "POST"
                    connection.doOutput = true
                    connection.setRequestProperty("Content-Type", "application/json")
                    connection.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
                }
                val code = connection.responseCode
                if (code == 401 && attempt == 0) continue
                if (code in listOf(401,403)) throw SecurityException()
                check(code == 200)
                return connection.inputStream.bufferedReader().use { it.readText() }
            } finally { connection.disconnect() }
        }
        throw SecurityException()
    }
    private fun checkArrival() {
        try {
            val rows = JSONArray(request("/operator/sos-map"))
            val active = (0 until rows.length()).map { rows.getJSONObject(it) }.filter {
                it.optBoolean("can_track") && it.optString("decision") == "confirmed" && it.optString("attention") == "en_route"
            }
            if (active.isEmpty()) { stopSelf(); return }
            val gps = lastLocation ?: run {
                updateNotice("Esperando la ubicación del dispositivo.")
                return
            }
            if (SystemClock.elapsedRealtimeNanos() - gps.elapsedRealtimeNanos > 30000000000L || gps.accuracy > 30) {
                updateNotice("Esperando una ubicación GPS precisa.")
                return
            }
            var remaining = 0
            for (row in active) {
                if (destroyed || FirebaseAuth.getInstance().currentUser?.uid != owner) return
                val result = JSONObject(request("/operator/sos-cases/${row.getString("id")}/arrival",
                    JSONObject().put("latitude",gps.latitude).put("longitude",gps.longitude)
                        .put("accuracy",gps.accuracy).put("observed_at",
                            java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", java.util.Locale.US).apply {
                                timeZone = java.util.TimeZone.getTimeZone("UTC")
                            }.format(java.util.Date(gps.time)))))
                if (result.optBoolean("tracking",true)) remaining++
            }
            if (remaining == 0) stopSelf()
            else updateNotice("Ubicación activa para comprobar la llegada al caso.")
        } catch (_: SecurityException) { stopSelf() }
    }
    override fun onDestroy() {
        destroyed = true
        handler.removeCallbacksAndMessages(null)
        locationClient.removeLocationUpdates(locationCallback)
        worker.shutdownNow()
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }
    override fun onBind(intent: Intent?) = null
}
