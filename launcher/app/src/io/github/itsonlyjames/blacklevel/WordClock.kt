package io.github.itsonlyjames.blacklevel

import android.app.Activity
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.PorterDuff
import android.graphics.RadialGradient
import android.graphics.Rect
import android.graphics.Shader
import android.graphics.Typeface
import android.os.Handler
import android.os.Looper
import android.view.Choreographer
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.widget.FrameLayout
import org.json.JSONObject
import kotlin.random.Random

// The word clock's letters, drawn natively. The page decides what's lit and when (assets/wordclock.js);
// this draws it on a surface sized to the panel, over the page. Android draws the rest of Home at 1080p and
// the TV scales that up 2×, which leaves thin letters soft; a surface at the panel's own size reaches it at
// full 4K. The page still draws the dark background and fades Home out underneath.
// It only draws while something is fading; between changes the last frame stays up.
class WordClock(private val activity: Activity, parent: FrameLayout) : SurfaceHolder.Callback, Choreographer.FrameCallback {
    private val view = SurfaceView(activity).apply {
        setZOrderOnTop(true)
        holder.setFormat(PixelFormat.TRANSLUCENT)
        isFocusable = false
        visibility = View.GONE
    }

    // the panel's own size; the layout is in the page's 1920×1080 units, times s
    @Suppress("DEPRECATION")
    private val mode = activity.windowManager.defaultDisplay.mode
    private val w = mode.physicalWidth
    private val h = mode.physicalHeight
    private val s = w / 1920f
    private val cw = 92 * s
    private val ch = 84 * s

    init {
        parent.addView(view, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        view.holder.setFixedSize(w, h)
        view.holder.addCallback(this)
    }

    private fun font(weight: Int) = Typeface.Builder(activity.assets, "fonts/HankenGrotesk.ttf")
        .setFontVariationSettings("'wght' $weight").build()
    private val off = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = font(300); textSize = 44 * s; color = 0xFF12100E.toInt(); textAlign = Paint.Align.CENTER
    }
    private val lit = Paint(off).apply { typeface = font(440) }
    private val capHeight = Rect().also { lit.getTextBounds("H", 0, 1, it) }.height()
    private val poolRadius = 75 * s
    private val pool = Paint(Paint.ANTI_ALIAS_FLAG)
    private val dot = Paint(Paint.ANTI_ALIAS_FLAG)

    // lit colour, halo strength, pool strength (the page's Soft / Medium / Bright)
    private class Style(val color: Int, val glow: Float, val pool: Float)
    private val styles = mapOf(
        "soft" to Style(0xD4C9B5, .3f, .05f),
        "medium" to Style(0xF5EAD5, .45f, .085f),
        "bright" to Style(0xFFFBE6, .6f, .11f),
    )
    private var style = styles.getValue("medium")
    private fun setStyle(name: String) {
        style = styles[name] ?: styles.getValue("medium")
        pool.shader = RadialGradient(0f, 0f, poolRadius, rgba(0xC89257, style.pool), Color.TRANSPARENT, Shader.TileMode.CLAMP)
    }
    init { setStyle("medium") }

    // each letter and dot fades from one level to another (0 unlit … 1 lit), starting at a set time
    private class Fade(var from: Float = 0f, var to: Float = 0f, var start: Double = 0.0, var ms: Double) {
        fun at(now: Double): Float {
            val t = ((now - start) / ms).coerceIn(0.0, 1.0).toFloat()
            return from + (to - from) * t * t * (3 - 2 * t) // ease in and out
        }
        fun go(target: Float, now: Double, delayMs: Double) {
            if (target == to) return
            from = at(now); to = target; start = now + delayMs
        }
        fun moving(now: Double) = from != to && now < start + ms
    }
    private var letters = ""
    private var fades = arrayOf<Fade>()
    private val dots = Array(4) { Fade(ms = 1200.0) }
    private var showDots = false
    private val master = Fade(ms = 2000.0)
    private var hiding = false

    private var surface: SurfaceHolder? = null
    private var running = false
    private fun now() = System.nanoTime() / 1e6

    // burn-in: the lit words move every five minutes anyway; the grid also wanders a pixel or two a minute
    private var dx = 0f
    private var dy = 0f
    private val handler = Handler(Looper.getMainLooper())
    private val drift = object : Runnable {
        override fun run() {
            dx = (dx + Random.nextInt(-2, 3)).coerceIn(-12 * s, 12 * s)
            dy = (dy + Random.nextInt(-2, 3)).coerceIn(-12 * s, 12 * s)
            kick(); handler.postDelayed(this, 60_000)
        }
    }

    fun show(rows: String) {
        letters = rows
        fades = Array(rows.length) { Fade(ms = 2400.0) }
        dots.forEach { it.from = 0f; it.to = 0f }
        hiding = false
        master.from = 0f; master.to = 0f; master.ms = 2000.0; master.go(1f, now(), 0.0)
        view.visibility = View.VISIBLE
        handler.removeCallbacks(drift); handler.postDelayed(drift, 60_000)
        kick()
    }

    // {on: [[letter, delay in s], …], dots: n, showDots, level}
    fun light(o: JSONObject) {
        val t = now()
        val on = HashMap<Int, Double>()
        val list = o.getJSONArray("on")
        for (k in 0 until list.length()) list.getJSONArray(k).let { on[it.getInt(0)] = it.getDouble(1) }
        fades.forEachIndexed { i, f -> f.go(if (i in on) 1f else 0f, t, (on[i] ?: 0.0) * 1000) }
        val n = o.optInt("dots")
        dots.forEachIndexed { i, f -> f.go(if (i < n) 1f else 0f, t, 0.0) }
        showDots = o.optBoolean("showDots")
        setStyle(o.optString("level"))
        kick()
    }

    fun hide() {
        if (view.visibility != View.VISIBLE || hiding) return
        hiding = true
        master.go(0f, now(), 0.0); master.ms = 500.0
        handler.removeCallbacks(drift)
        kick()
    }

    // leaving Home: no fade, it's not on screen
    fun hideNow() {
        hiding = false
        handler.removeCallbacks(drift)
        view.visibility = View.GONE
    }

    private fun kick() {
        if (running || surface == null) return
        running = true
        Choreographer.getInstance().postFrameCallback(this)
    }

    override fun doFrame(nanos: Long) {
        val holder = surface
        if (holder == null) { running = false; return }
        val t = now()
        val c = holder.lockHardwareCanvas()
        try { draw(c, t) } finally { holder.unlockCanvasAndPost(c) }
        if (hiding && !master.moving(t)) { running = false; hideNow(); return }
        if (master.moving(t) || fades.any { it.moving(t) } || dots.any { it.moving(t) }) Choreographer.getInstance().postFrameCallback(this)
        else running = false
    }

    private fun rgba(rgb: Int, a: Float) = (((a.coerceIn(0f, 1f) * 255).toInt()) shl 24) or (rgb and 0xFFFFFF)

    private fun draw(c: Canvas, t: Double) {
        c.drawColor(Color.TRANSPARENT, PorterDuff.Mode.CLEAR)
        val m = master.at(t)
        if (m <= 0f || letters.isEmpty()) return
        val x0 = (w - 11 * cw) / 2 + dx
        val y0 = (h - (letters.length / 11) * ch) / 2 + dy
        val v = FloatArray(letters.length) { fades[it].at(t) }
        val cx = { i: Int -> x0 + (i % 11 + .5f) * cw }
        val cy = { i: Int -> y0 + (i / 11 + .5f) * ch }

        // a faint pool of warm light behind each lit letter, under all the letters
        v.forEachIndexed { i, a ->
            if (a <= 0f) return@forEachIndexed
            pool.alpha = (255 * a * m).toInt()
            c.save(); c.translate(cx(i), cy(i)); c.drawCircle(0f, 0f, poolRadius, pool); c.restore()
        }
        // unlit letters fade out as lit ones fade in over them: a soft warm glow, a tight halo, a crisp edge.
        // At 4K the edge stays sharp under the glow, so it can be the full Lantern glow
        val g = style.glow
        v.forEachIndexed { i, a ->
            val glyph = letters[i].toString(); val x = cx(i); val y = cy(i) + capHeight / 2f
            if (a < 1f) { off.alpha = (255 * m * (1 - a)).toInt(); c.drawText(glyph, x, y, off) }
            if (a <= 0f) return@forEachIndexed
            val k = a * m
            lit.color = rgba(style.color, k)
            lit.setShadowLayer(22 * s, 0f, 0f, rgba(0xE1AC6E, g * k)); c.drawText(glyph, x, y, lit)
            lit.setShadowLayer(6 * s, 0f, 0f, rgba(0xE9BB82, g * .7f * k)); c.drawText(glyph, x, y, lit)
            lit.setShadowLayer(1 * s, 0f, 0f, rgba(0xFFF7E2, .9f * k)); c.drawText(glyph, x, y, lit)
        }
        lit.clearShadowLayer()

        // minute dots: one per minute past the five, below the grid
        if (showDots) {
            val r = 3.5f * s; val gap = 18 * s
            val left = w / 2f - (4 * 2 * r + 3 * gap) / 2 + dx + r
            val y = y0 + (letters.length / 11) * ch + 52.5f * s
            dots.forEachIndexed { i, f ->
                val a = f.at(t)
                dot.color = blend(0x12100E, 0xCAA77D, a); dot.alpha = (255 * m).toInt()
                c.drawCircle(left + i * (2 * r + gap), y, r, dot)
            }
        }
    }

    private fun blend(a: Int, b: Int, t: Float): Int {
        fun ch(shift: Int) = (((a shr shift) and 0xFF) * (1 - t) + ((b shr shift) and 0xFF) * t).toInt() shl shift
        return ch(16) or ch(8) or ch(0) or (0xFF shl 24)
    }

    override fun surfaceCreated(holder: SurfaceHolder) {}
    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) { surface = holder; kick() }
    override fun surfaceDestroyed(holder: SurfaceHolder) { surface = null }
}
