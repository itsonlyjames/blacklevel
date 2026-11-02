package io.github.itsonlyjames.blacklevel

import android.app.Activity
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.PorterDuff
import android.graphics.Rect
import android.graphics.Typeface
import android.os.Build
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
// this draws it on a surface over the page, which still draws the dark background and fades Home out underneath.
// The surface is 1080p like the rest of Android. A 4K one was sharper, but on the A80J any full-panel 4K layer
// switches the TV's display hardware into a mode it doesn't leave until a reboot, which shrinks HDMI inputs into
// the top-left quarter of the screen. Lit letters have no glow, since a glow scaled up 2× reads as soft focus.
// It only draws while something is fading; between changes the last frame stays up.
// Android builds the surface afresh each time it's shown (it's gone while hidden), which takes a moment and
// briefly disturbs the window, so the page only shows it once the screen has gone fully dark (wordclock.js).
// Its first frame is an empty one, and the fade begins once that's on screen, with the words' delays counted
// from then, so a slow surface never cuts into the fade.
class WordClock(private val activity: Activity, parent: FrameLayout) : SurfaceHolder.Callback, Choreographer.FrameCallback {
    private val view = SurfaceView(activity).apply {
        setZOrderOnTop(true)
        holder.setFormat(PixelFormat.TRANSLUCENT)
        isFocusable = false
        visibility = View.GONE
    }

    // the page's own 1920×1080 units; never the panel's 4K (see above)
    private val w = 1920
    private val h = 1080
    private val s = 1f
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
    private val dot = Paint(Paint.ANTI_ALIAS_FLAG)

    // lit colour for the page's Soft / Medium / Bright
    private val styles = mapOf("soft" to 0xD4C9B5, "medium" to 0xF5EAD5, "bright" to 0xFFFBE6)
    private var style = styles.getValue("medium")
    private fun setStyle(name: String) { style = styles[name] ?: styles.getValue("medium") }

    // each letter and dot fades from one level to another (0 unlit … 1 lit), starting at a set time
    private class Fade(var from: Float = 0f, var to: Float = 0f, var start: Double = 0.0, var ms: Double) {
        fun at(now: Double): Float {
            val t = ((now - start) / ms).coerceIn(0.0, 1.0).toFloat()
            return from + (to - from) * t * t * (3 - 2 * t) // ease in and out
        }
        fun go(target: Float, now: Double, delayMs: Double, overMs: Double = ms) {
            if (target == to) return
            from = at(now); to = target; start = now + delayMs; ms = overMs
        }
        fun moving(now: Double) = from != to && now < start + ms
    }
    private var letters = ""
    private var fades = arrayOf<Fade>()
    private val dots = Array(4) { Fade(ms = 1200.0) }
    private var showDots = false
    private val master = Fade(ms = 2000.0)
    private var hiding = false
    private var waiting = false // shown, but its empty first frame isn't up yet
    private var committed = false // the window has drawn a frame with the surface in it
    private var shownAt = 0.0

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
        master.from = 0f; master.to = 0f; master.ms = 2000.0
        waiting = true; shownAt = now()
        view.visibility = View.VISIBLE
        // the surface only reaches the screen with the window's next frame, and a still page draws none,
        // so ask for one now, and only count the fade from once that frame (and the surface in it) is up
        committed = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q
        if (!committed) view.viewTreeObserver.registerFrameCommitCallback { committed = true; kick() }
        (view.parent as View).invalidate()
        handler.removeCallbacks(drift); handler.postDelayed(drift, 60_000)
        kick()
    }

    // {on: [[letter, delay in s], …], dots: n, showDots, level}
    fun light(o: JSONObject) {
        val t = now()
        val on = HashMap<Int, Double>()
        val list = o.getJSONArray("on")
        for (k in 0 until list.length()) list.getJSONArray(k).let { on[it.getInt(0)] = it.getDouble(1) }
        // words go out in 1.2s and come in over 2.4s; the page starts the new ones once the old are out
        fades.forEachIndexed { i, f -> if (i in on) f.go(1f, t, on.getValue(i) * 1000, 2400.0) else f.go(0f, t, 0.0, 1200.0) }
        val n = o.optInt("dots")
        dots.forEachIndexed { i, f -> f.go(if (i < n) 1f else 0f, t, 0.0) }
        showDots = o.optBoolean("showDots")
        setStyle(o.optString("level"))
        kick()
    }

    fun hide() {
        if (view.visibility != View.VISIBLE || hiding) return
        hiding = true
        master.go(0f, now(), 0.0, 300.0) // the page brings Home back once this has cleared
        handler.removeCallbacks(drift)
        kick()
    }

    // leaving Home: no fade, it's not on screen
    fun hideNow() {
        hiding = false; waiting = false
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
        if (waiting) {
            if (!committed) { Choreographer.getInstance().postFrameCallback(this); return }
            // the empty frame is up: start the fade now, and the words' own delays from now rather than from show()
            waiting = false
            val late = t - shownAt
            fades.forEach { it.start += late }; dots.forEach { it.start += late }
            master.go(1f, t, 0.0)
            Choreographer.getInstance().postFrameCallback(this); return
        }
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

        // unlit letters fade out as lit ones fade in over them
        v.forEachIndexed { i, a ->
            val glyph = letters[i].toString(); val x = cx(i); val y = cy(i) + capHeight / 2f
            if (a < 1f) { off.alpha = (255 * m * (1 - a)).toInt(); c.drawText(glyph, x, y, off) }
            if (a <= 0f) return@forEachIndexed
            lit.color = rgba(style, a * m); c.drawText(glyph, x, y, lit)
        }

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
