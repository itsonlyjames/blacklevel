package io.github.itsonlyjames.blacklevel

import android.annotation.SuppressLint
import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInstaller
import android.media.tv.TvContract
import android.media.tv.TvInputInfo
import android.media.tv.TvInputManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.KeyEvent
import android.webkit.JavascriptInterface
import android.webkit.WebView
import org.json.JSONArray
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import org.json.JSONObject

class HomeActivity : Activity() {
    private lateinit var web: WebView

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        web = WebView(this).apply {
            setBackgroundColor(0xFF0D0B09.toInt())
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true // remembers most-recently-opened apps and the page's settings
            settings.allowFileAccess = true
            // the page never scrolls; without this a scrollbar flashes while the viewport settles on load
            isVerticalScrollBarEnabled = false
            isHorizontalScrollBarEnabled = false
            overScrollMode = WebView.OVER_SCROLL_NEVER
            // the page is laid out at 1920x1080; let the viewport meta size it to the screen
            settings.useWideViewPort = true
            settings.loadWithOverviewMode = true
            isFocusable = true
            // holding OK picks up an app to move; keep the WebView's own long-press (text selection) out of it
            setOnLongClickListener { true }
            addJavascriptInterface(Bridge(), "Launcher")
            loadUrl("file:///android_asset/index.html")
        }
        setContentView(web)
        web.requestFocus()
        registerReceiver(installed, IntentFilter(INSTALLED))
        getSystemService(TvInputManager::class.java)?.registerCallback(inputsChanged, handler)
    }

    override fun onDestroy() {
        getSystemService(TvInputManager::class.java)?.unregisterCallback(inputsChanged)
        handler.removeCallbacks(redrawInputs)
        unregisterReceiver(installed)
        super.onDestroy()
    }

    // Redraw the inputs row while Home is on screen as cables go in and out and CEC devices appear.
    // A source that's negotiating can drop and return several times a second, so wait for it to settle.
    private val handler = Handler(Looper.getMainLooper())
    private val redrawInputs = Runnable { web.evaluateJavascript("window.refreshInputs && refreshInputs()", null) }
    private val inputsChanged = object : TvInputManager.TvInputCallback() {
        private fun changed() { handler.removeCallbacks(redrawInputs); handler.postDelayed(redrawInputs, 500) }
        override fun onInputStateChanged(inputId: String, state: Int) = changed()
        override fun onInputAdded(inputId: String) = changed()
        override fun onInputRemoved(inputId: String) = changed()
        override fun onInputUpdated(inputId: String) = changed()
    }

    private fun updateStatus(status: JSONObject) =
        runOnUiThread { web.evaluateJavascript("window.updateStatus && updateStatus($status)", null) }

    private fun updateMessage(text: String) = updateStatus(JSONObject().put("message", text))

    // Android reports back here on the install it was handed: ask the viewer to confirm, or say why it failed.
    // On success there's nothing to do: Android replaces this process with the new version.
    private val installed = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
                PackageInstaller.STATUS_PENDING_USER_ACTION ->
                    @Suppress("DEPRECATION") intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
                        ?.let { startActivity(it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
                PackageInstaller.STATUS_SUCCESS -> {}
                PackageInstaller.STATUS_FAILURE_ABORTED -> updateMessage("Update cancelled")
                // A build signed with someone else's key can't be replaced by the release
                PackageInstaller.STATUS_FAILURE_CONFLICT, PackageInstaller.STATUS_FAILURE_INCOMPATIBLE ->
                    updateMessage("This copy was built from source: update it with adb")
                else -> updateMessage(intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: "Update failed")
            }
        }
    }

    override fun onResume() {
        super.onResume()
        // installs/uninstalls and focus reset when coming back home
        web.evaluateJavascript("window.refresh && refresh()", null)
    }

    // Home has nowhere to go back to; Back only closes the page's own panels.
    override fun dispatchKeyEvent(e: KeyEvent): Boolean {
        if (e.keyCode != KeyEvent.KEYCODE_BACK) return super.dispatchKeyEvent(e)
        if (e.action == KeyEvent.ACTION_UP) web.evaluateJavascript("window.back && back()", null)
        return true
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {}

    inner class Bridge {
        // Stock Sony/Google surfaces are left out; YouTube stays.
        private fun hidden(pkg: String) = pkg == packageName ||
            pkg.startsWith("com.sony.") ||
            (pkg.startsWith("com.google.") && !pkg.startsWith("com.google.android.youtube.tv")) ||
            pkg.startsWith("com.vewd.") || // Sony's bundled browser
            pkg == "com.android.vending" || pkg == "com.android.tv.settings"

        // Starting order until the page's own most-recently-opened list takes over.
        private val preferred = listOf(
            "com.netflix.ninja", "com.google.android.youtube.tv", "org.smarttube.beta", "com.plexapp.android",
            "com.spotify.tv.android", "au.com.kayosports.tv", "au.com.streamotion.ares.tv",
            "com.amazon.amazonvideo.livingroom", "au.net.abc.iview", "com.sbs.ondemand.tv",
            "au.com.ninenow.ctv", "au.com.tenplay", "com.swm.live", "au.com.optus.sport.androidtv",
        )
        private fun order(pkg: String) = preferred.indexOf(pkg).let { if (it < 0) preferred.size else it }

        @JavascriptInterface
        fun apps(): String {
            val pm = packageManager
            val main = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LEANBACK_LAUNCHER)
            val out = JSONArray()
            pm.queryIntentActivities(main, 0)
                .map { it.activityInfo.packageName to it.loadLabel(pm).toString().trim() }
                .distinctBy { it.first }
                .filterNot { hidden(it.first) }
                .sortedWith(compareBy({ order(it.first) }, { it.second.lowercase() }))
                .forEach { (pkg, label) -> out.put(JSONObject().put("pkg", pkg).put("label", label)) }
            return out.toString()
        }

        // One entry per connected HDMI port, named after the HDMI-CEC device on it ("SHIELD") when
        // there is one, else the port's own name ("PC", "HDMI 2").
        @JavascriptInterface
        fun inputs(): String {
            val tim = getSystemService(TvInputManager::class.java) ?: return "[]"
            val all = tim.tvInputList.filter { it.type == TvInputInfo.TYPE_HDMI }
            val ports = all.filter { it.parentId == null }
                .associateBy { portNumber(it.loadLabel(this@HomeActivity).toString()) }
            val children = all.filter { it.parentId != null }.groupBy { it.parentId }
            val cec = cachedCecNames() // port -> device name; refreshed in the background
            refreshCecNames()

            val out = JSONArray()
            ports.toSortedMap(compareBy { it }).forEach { (port, info) ->
                if (port < 0) return@forEach
                val child = children[info.id]?.firstOrNull()
                val connected = tim.getInputState(info.id) == TvInputManager.INPUT_STATE_CONNECTED || child != null
                if (!connected) return@forEach
                val portName = "HDMI $port"
                val custom = info.loadCustomLabel(this@HomeActivity)?.toString()?.takeIf { it.isNotBlank() }
                val device = cec[port] ?: child?.loadLabel(this@HomeActivity)?.toString()?.takeIf { it.isNotBlank() }
                out.put(JSONObject()
                    .put("id", (child ?: info).id) // the CEC child input selects the device itself
                    .put("label", device ?: custom ?: portName)
                    .put("sub", if (device != null || custom != null) portName else null))
            }
            return out.toString()
        }

        private fun portNumber(label: String) = Regex("""HDMI\s*(\d+)""").find(label)?.groupValues?.get(1)?.toInt() ?: -1

        // Sony's local REST API answers getCurrentExternalInputsStatus without a pre-shared key, but takes
        // ~1 s, so names are cached and the inputs row is redrawn when they change.
        // (TvInputManager doesn't expose CEC names for audio systems such as an AV receiver.)
        private val prefs by lazy { getSharedPreferences("cec", MODE_PRIVATE) }

        private fun cachedCecNames(): Map<Int, String> =
            prefs.all.mapNotNull { (k, v) -> k.toIntOrNull()?.let { port -> (v as? String)?.let { port to it } } }.toMap()

        private fun refreshCecNames() = Thread {
            val fresh = try {
                val conn = URL("http://127.0.0.1/sony/avContent").openConnection() as HttpURLConnection
                conn.connectTimeout = 2000; conn.readTimeout = 4000
                conn.requestMethod = "POST"; conn.doOutput = true
                conn.outputStream.use { it.write("""{"method":"getCurrentExternalInputsStatus","id":1,"params":[],"version":"1.0"}""".toByteArray()) }
                val body = conn.inputStream.bufferedReader().use { it.readText() }
                val list = JSONObject(body).getJSONArray("result").getJSONArray(0)
                (0 until list.length()).map { list.getJSONObject(it) }
                    .filter { it.optString("uri").startsWith("extInput:cec") && it.optBoolean("connection") }
                    .mapNotNull { o -> Regex("""port=(\d+)""").find(o.getString("uri"))?.groupValues?.get(1)?.toInt()?.let { it to o.getString("title") } }
                    .toMap()
            } catch (e: Exception) { return@Thread }
            if (fresh == cachedCecNames()) return@Thread
            prefs.edit().clear().apply { fresh.forEach { (port, name) -> putString(port.toString(), name) } }.apply()
            runOnUiThread { web.evaluateJavascript("window.refreshInputs && refreshInputs()", null) }
        }.start()

        @JavascriptInterface
        fun launch(pkg: String) = runOnUiThread {
            packageManager.getLeanbackLaunchIntentForPackage(pkg)
                ?.let { startActivity(it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
        }

        @JavascriptInterface
        fun input(id: String) = runOnUiThread {
            val view = Intent(Intent.ACTION_VIEW, TvContract.buildChannelUriForPassthroughInput(id))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (view.resolveActivity(packageManager) != null) startActivity(view)
        }

        @JavascriptInterface
        fun settings() = runOnUiThread {
            startActivity(Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }

        // Updates come from GitHub Releases, the only request that leaves the local network.
        @JavascriptInterface
        fun version(): String = packageManager.getPackageInfo(packageName, 0).versionName ?: ""

        /** Answers updateStatus({latest}) with the newer version, or null when this one is the latest. */
        @JavascriptInterface
        fun checkUpdate() = Thread {
            try {
                val latest = latestRelease().getString("tag_name").removePrefix("v")
                updateStatus(JSONObject().put("latest", if (newer(latest, version())) latest else JSONObject.NULL))
            } catch (e: Exception) { updateMessage("Couldn't reach GitHub") }
        }.start()

        /** Downloads the release APK, checks it against SHA256SUMS.txt and hands it to Android to install. */
        @JavascriptInterface
        fun installUpdate() {
            if (!packageManager.canRequestPackageInstalls()) {
                runOnUiThread {
                    val allow = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
                    val fallback = Intent(Settings.ACTION_SECURITY_SETTINGS)
                    startActivity((if (allow.resolveActivity(packageManager) != null) allow else fallback).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                }
                updateMessage("Allow Blacklevel to install apps, then try again")
                return
            }
            Thread {
                try {
                    val release = latestRelease()
                    val version = release.getString("tag_name").removePrefix("v")
                    val name = "BlacklevelHome-$version.apk"
                    val assets = release.getJSONArray("assets").let { list -> (0 until list.length()).map { list.getJSONObject(it) } }
                        .associate { it.getString("name") to it.getString("browser_download_url") }
                    val url = assets[name] ?: throw Exception("$version has no APK")
                    updateMessage("Downloading $version…")
                    val apk = URL(url).readBytes()
                    assets["SHA256SUMS.txt"]?.let { sums ->
                        val expected = String(URL(sums).readBytes()).lines().firstOrNull { it.endsWith(" $name") }?.substringBefore(" ")
                        val actual = MessageDigest.getInstance("SHA-256").digest(apk).joinToString("") { "%02x".format(it) }
                        if (expected != actual) throw Exception("The download didn't match its checksum")
                    }
                    install(apk)
                    updateMessage("Installing $version…")
                } catch (e: Exception) { updateMessage(e.message ?: "Update failed") }
            }.start()
        }

        private fun install(apk: ByteArray) {
            val installer = packageManager.packageInstaller
            val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
                setAppPackageName(packageName)
                // Android 12+ may skip the confirmation for an app updating itself
                if (Build.VERSION.SDK_INT >= 31) setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
            }
            val id = installer.createSession(params)
            installer.openSession(id).use { session ->
                session.openWrite("home.apk", 0, apk.size.toLong()).use { out -> out.write(apk); session.fsync(out) }
                val done = Intent(INSTALLED).setPackage(packageName)
                val flags = PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
                session.commit(PendingIntent.getBroadcast(this@HomeActivity, id, done, flags).intentSender)
            }
        }

        private fun latestRelease(): JSONObject {
            val conn = URL(RELEASES).openConnection() as HttpURLConnection
            conn.connectTimeout = 10000; conn.readTimeout = 15000
            conn.setRequestProperty("Accept", "application/vnd.github+json")
            return JSONObject(conn.inputStream.bufferedReader().use { it.readText() })
        }

        private fun newer(a: String, b: String): Boolean {
            val x = a.split(".").map { it.toIntOrNull() ?: 0 }
            val y = b.split(".").map { it.toIntOrNull() ?: 0 }
            for (i in 0 until maxOf(x.size, y.size)) {
                val l = x.getOrElse(i) { 0 }; val r = y.getOrElse(i) { 0 }
                if (l != r) return l > r
            }
            return false
        }
    }

    companion object {
        private const val RELEASES = "https://api.github.com/repos/itsonlyjames/blacklevel/releases/latest"
        private const val INSTALLED = "io.github.itsonlyjames.blacklevel.INSTALLED"
    }
}
