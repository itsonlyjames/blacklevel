package io.github.itsonlyjames.blacklevel

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.media.tv.TvContract
import android.media.tv.TvInputInfo
import android.media.tv.TvInputManager
import android.os.Bundle
import android.provider.Settings
import android.view.KeyEvent
import android.webkit.JavascriptInterface
import android.webkit.WebView
import org.json.JSONArray
import java.net.HttpURLConnection
import java.net.URL
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
    }
}
