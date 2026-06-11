package com.emp0ry.mirushin

import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.app.UiModeManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.drawable.Icon
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.SystemClock
import android.util.Rational
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.InputMethodManager
import android.webkit.WebView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.net.HttpURLConnection
import java.net.URL

class MainActivity : FlutterActivity() {

    companion object {
        private const val ACTION_PLAY_PAUSE = "com.emp0ry.mirushin.PIP_PLAY_PAUSE"
        private const val ACTION_NEXT       = "com.emp0ry.mirushin.PIP_NEXT"
        private const val RC_PLAY_PAUSE     = 1
        private const val RC_NEXT           = 2
    }

    private var mediaChannel: MethodChannel? = null
    private var pipChannel: MethodChannel? = null
    private var session: MediaSession? = null
    private var noisyReceiver: BroadcastReceiver? = null
    private var pipActionReceiver: BroadcastReceiver? = null

    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private var artworkUrl = ""
    private var artworkBitmap: Bitmap? = null
    private var artworkJob: Job? = null

    // Last known PiP params so we can restore them when updating actions.
    private var pipRatioW = 16
    private var pipRatioH = 9
    private var pipIsPlaying = true
    private var pipHasNext = false

    // Android TVs frequently report a small logical resolution (high density),
    // which makes a phone-designed UI look zoomed-in on the big screen. Override
    // the density so Flutter lays out at a sane ~1280dp-wide logical canvas.
    // Flutter reads its devicePixelRatio from the activity's resources, so this
    // takes effect for the whole UI. No-op on phones/tablets.
    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(adjustDensityForTelevision(base))
    }

    private fun adjustDensityForTelevision(context: Context): Context {
        val config = context.resources.configuration
        val isTv =
            (config.uiMode and Configuration.UI_MODE_TYPE_MASK) ==
                Configuration.UI_MODE_TYPE_TELEVISION ||
                context.packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
                context.packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK_ONLY)
        if (!isTv) return context

        val metrics = context.resources.displayMetrics
        val widthPx = maxOf(metrics.widthPixels, metrics.heightPixels)
        if (widthPx <= 0) return context

        val targetWidthDp = 1280f
        val overridden = Configuration(config)
        overridden.densityDpi =
            (160f * widthPx / targetWidthDp).toInt().coerceIn(120, 640)
        overridden.fontScale = 1f
        return context.createConfigurationContext(overridden)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── Media session channel ──────────────────────────────────────────
        val mch = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, "mirushin/media_session"
        )
        mediaChannel = mch
        mch.setMethodCallHandler { call, result ->
            when (call.method) {
                "updateNowPlaying" -> {
                    @Suppress("UNCHECKED_CAST")
                    (call.arguments as? Map<String, Any>)?.let { updateNowPlaying(it) }
                    result.success(null)
                }
                "clearNowPlaying" -> {
                    clearSession()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // ── PiP channel ────────────────────────────────────────────────────
        val pch = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, "mirushin/pip"
        )
        pipChannel = pch
        pch.setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                "enter" -> {
                    val args = call.arguments as? Map<*, *>
                    val ratioW    = (args?.get("ratioW")    as? Number)?.toInt()  ?: 16
                    val ratioH    = (args?.get("ratioH")    as? Number)?.toInt()  ?: 9
                    val isPlaying = (args?.get("isPlaying") as? Boolean) ?: true
                    val hasNext   = (args?.get("hasNext")   as? Boolean) ?: false
                    enterPip(ratioW, ratioH, isPlaying, hasNext)
                    result.success(null)
                }
                "updateParams" -> {
                    val args      = call.arguments as? Map<*, *>
                    val isPlaying = (args?.get("isPlaying") as? Boolean) ?: pipIsPlaying
                    val hasNext   = (args?.get("hasNext")   as? Boolean) ?: pipHasNext
                    pipIsPlaying  = isPlaying
                    pipHasNext    = hasNext
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && isInPictureInPictureMode) {
                        setPictureInPictureParams(buildPipParams(pipRatioW, pipRatioH, isPlaying, hasNext))
                    }
                    result.success(null)
                }
                "bringToForeground" -> {
                    val intent = Intent(this, MainActivity::class.java).apply {
                        flags = Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                    }
                    startActivity(intent)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // ── Device / form-factor channel ───────────────────────────────────
        val dch = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, "mirushin/device"
        )
        dch.setMethodCallHandler { call, result ->
            when (call.method) {
                "isTelevision" -> result.success(isRunningOnTelevision())
                "showSoftKeyboard" -> result.success(showSoftKeyboard())
                "hideSoftKeyboard" -> result.success(hideSoftKeyboard())
                "tapFocusedWebView" -> {
                    val args = call.arguments as? Map<*, *>
                    val x = (args?.get("x") as? Number)?.toFloat() ?: -1f
                    val y = (args?.get("y") as? Number)?.toFloat() ?: -1f
                    result.success(tapFocusedWebView(x, y))
                }
                else -> result.notImplemented()
            }
        }

        registerPipActionReceiver()
    }

    /** True when the app is running on an Android TV / leanback device. */
    private fun isRunningOnTelevision(): Boolean {
        val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
        if (uiModeManager?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION) {
            return true
        }
        return packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK_ONLY)
    }

    private fun showSoftKeyboard(): Boolean {
        val focused = currentFocus ?: window.decorView.findFocus() ?: return false
        focused.requestFocus()
        focused.requestFocusFromTouch()
        val inputMethodManager =
            getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
                ?: return false
        focused.post {
            inputMethodManager.showSoftInput(focused, InputMethodManager.SHOW_IMPLICIT)
        }
        return true
    }

    private fun hideSoftKeyboard(): Boolean {
        val focused = currentFocus ?: window.decorView.findFocus() ?: return false
        val inputMethodManager =
            getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
                ?: return false
        return inputMethodManager.hideSoftInputFromWindow(focused.windowToken, 0)
    }

    private fun tapFocusedWebView(x: Float, y: Float): Boolean {
        if (x < 0f || y < 0f) return false
        val webView = (currentFocus as? WebView) ?: findWebView(window.decorView) ?: return false
        if (webView.width <= 0 || webView.height <= 0) return false
        val localX = x.coerceIn(1f, (webView.width - 1).toFloat())
        val localY = y.coerceIn(1f, (webView.height - 1).toFloat())
        webView.requestFocus()
        webView.requestFocusFromTouch()

        val downTime = SystemClock.uptimeMillis()
        val down = MotionEvent.obtain(
            downTime, downTime, MotionEvent.ACTION_DOWN, localX, localY, 0
        )
        val up = MotionEvent.obtain(
            downTime, SystemClock.uptimeMillis(), MotionEvent.ACTION_UP, localX, localY, 0
        )
        val handledDown = webView.dispatchTouchEvent(down)
        val handledUp = webView.dispatchTouchEvent(up)
        down.recycle()
        up.recycle()
        return handledDown || handledUp
    }

    private fun findWebView(view: View?): WebView? {
        if (view == null) return null
        if (view is WebView) return view
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                val found = findWebView(view.getChildAt(i))
                if (found != null) return found
            }
        }
        return null
    }

    // ── PiP enter ─────────────────────────────────────────────────────────

    private fun enterPip(ratioW: Int, ratioH: Int, isPlaying: Boolean, hasNext: Boolean) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        pipRatioW   = ratioW
        pipRatioH   = ratioH
        pipIsPlaying = isPlaying
        pipHasNext   = hasNext
        enterPictureInPictureMode(buildPipParams(ratioW, ratioH, isPlaying, hasNext))
    }

    private fun buildPipParams(
        ratioW: Int, ratioH: Int, isPlaying: Boolean, hasNext: Boolean
    ): PictureInPictureParams {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return PictureInPictureParams.Builder().build()
        }
        val w = ratioW.coerceIn(1, 239)
        val h = ratioH.coerceIn(1, 239)
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(w, h))

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setSeamlessResizeEnabled(true)
        }

        val actions = mutableListOf<RemoteAction>()

        val ppIcon  = if (isPlaying) android.R.drawable.ic_media_pause
                      else           android.R.drawable.ic_media_play
        val ppLabel = if (isPlaying) "Pause" else "Play"
        val ppIntent = PendingIntent.getBroadcast(
            this, RC_PLAY_PAUSE, Intent(ACTION_PLAY_PAUSE),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        actions += RemoteAction(Icon.createWithResource(this, ppIcon), ppLabel, ppLabel, ppIntent)

        if (hasNext) {
            val nextIntent = PendingIntent.getBroadcast(
                this, RC_NEXT, Intent(ACTION_NEXT),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            actions += RemoteAction(
                Icon.createWithResource(this, android.R.drawable.ic_media_next),
                "Next", "Next episode", nextIntent
            )
        }

        builder.setActions(actions)
        return builder.build()
    }

    // ── PiP lifecycle ──────────────────────────────────────────────────────

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean, newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipChannel?.invokeMethod("pipModeChanged", isInPictureInPictureMode)
    }

    private fun registerPipActionReceiver() {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                when (intent.action) {
                    ACTION_PLAY_PAUSE -> mediaChannel?.invokeMethod("togglePlay", null)
                    ACTION_NEXT       -> mediaChannel?.invokeMethod("next",       null)
                }
            }
        }
        pipActionReceiver = receiver
        val filter = IntentFilter().apply {
            addAction(ACTION_PLAY_PAUSE)
            addAction(ACTION_NEXT)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(receiver, filter)
        }
    }

    // ── Media session / Now Playing ────────────────────────────────────────

    private fun updateNowPlaying(args: Map<String, Any>) {
        val title        = args["title"]       as? String  ?: ""
        val subtitle     = args["subtitle"]    as? String  ?: ""
        val newArtwork   = args["artworkUrl"]  as? String  ?: ""
        val posMs        = (args["positionMs"] as? Number)?.toLong()  ?: 0L
        val durMs        = (args["durationMs"] as? Number)?.toLong()  ?: 0L
        val isPlaying    = args["isPlaying"]   as? Boolean ?: false

        if (session == null) {
            val s = MediaSession(this, "MiruShin")
            s.setCallback(object : MediaSession.Callback() {
                override fun onPlay()            { mediaChannel?.invokeMethod("play",   null) }
                override fun onPause()           { mediaChannel?.invokeMethod("pause",  null) }
                override fun onSkipToNext()      { mediaChannel?.invokeMethod("next",   null) }
                override fun onSeekTo(pos: Long) { mediaChannel?.invokeMethod("seekTo", pos.toInt()) }
                override fun onStop()            { mediaChannel?.invokeMethod("stop",   null) }
            })
            s.isActive = true
            session = s
            registerNoisyReceiver()
        }

        fun applyMetadata(bitmap: Bitmap?) {
            val builder = MediaMetadata.Builder()
                .putString(MediaMetadata.METADATA_KEY_TITLE,    title)
                .putString(MediaMetadata.METADATA_KEY_ARTIST,   subtitle)
                .putLong(  MediaMetadata.METADATA_KEY_DURATION, durMs)
            if (bitmap != null) builder.putBitmap(MediaMetadata.METADATA_KEY_ART, bitmap)
            session?.setMetadata(builder.build())
        }

        applyMetadata(artworkBitmap)

        if (newArtwork.isNotEmpty() && newArtwork != artworkUrl) {
            artworkUrl    = newArtwork
            artworkBitmap = null
            artworkJob?.cancel()
            artworkJob = scope.launch {
                val bmp = withContext(Dispatchers.IO) { downloadBitmap(newArtwork) }
                if (isActive && bmp != null && artworkUrl == newArtwork) {
                    artworkBitmap = bmp
                    applyMetadata(bmp)
                }
            }
        }

        val stateCode = if (isPlaying) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED
        val pbState = PlaybackState.Builder()
            .setActions(
                PlaybackState.ACTION_PLAY        or
                PlaybackState.ACTION_PAUSE       or
                PlaybackState.ACTION_PLAY_PAUSE  or
                PlaybackState.ACTION_SKIP_TO_NEXT or
                PlaybackState.ACTION_SEEK_TO
            )
            .setState(stateCode, posMs, 1f)
            .build()
        session?.setPlaybackState(pbState)
    }

    private fun downloadBitmap(url: String): Bitmap? = try {
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.connectTimeout = 6_000
        conn.readTimeout    = 12_000
        conn.connect()
        BitmapFactory.decodeStream(conn.inputStream)
    } catch (_: Exception) { null }

    private fun registerNoisyReceiver() {
        val filter   = IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                mediaChannel?.invokeMethod("audioRouteChanged", true)
            }
        }
        noisyReceiver = receiver
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(receiver, filter)
        }
    }

    private fun clearSession() {
        artworkJob?.cancel()
        artworkUrl    = ""
        artworkBitmap = null
        session?.isActive = false
        session?.release()
        session = null
        noisyReceiver?.let { try { unregisterReceiver(it) } catch (_: Exception) {} }
        noisyReceiver = null
    }

    override fun onDestroy() {
        clearSession()
        pipActionReceiver?.let { try { unregisterReceiver(it) } catch (_: Exception) {} }
        pipActionReceiver = null
        scope.cancel()
        super.onDestroy()
    }
}
