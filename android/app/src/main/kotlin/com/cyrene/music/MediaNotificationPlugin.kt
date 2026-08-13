package com.cyrene.music

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import androidx.media.app.NotificationCompat.MediaStyle
import androidx.core.app.NotificationCompat
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.support.v4.media.session.MediaSessionCompat
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ConcurrentHashMap

/// 系统通知栏媒体控制器插件。
///
/// 通过 MethodChannel (`com.cyrene.media/notification`) 与 Flutter 端的
/// `MediaNotificationService` 通信：
/// - 接收：updateTrack / updatePlayback / updatePosition / updateRepeatMode / hide / ready
/// - 回传：play / pause / playPause / next / previous / seek / stop
///
/// 内部维护一个 [MediaSessionCompat]，通知使用 [MediaStyle] 关联 session token，
/// 以响应系统媒体键与锁屏控制。
class MediaNotificationPlugin : FlutterPlugin, MethodCallHandler {
    companion object {
        private const val CHANNEL_NAME = "com.cyrene.media/notification"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "media_playback"
    }

    private var context: Context? = null
    private var channel: MethodChannel? = null
    private var session: MediaSessionCompat? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // 当前媒体状态
    private var title: String = ""
    private var artist: String = ""
    private var album: String = ""
    private var artUrl: String = ""
    private var durationMs: Long = 0L
    private var positionMs: Long = 0L
    private var isPlaying: Boolean = false
    private var repeatModeName: String = "all"
    private var lastPositionUpdateTime: Long = 0L

    // 封面缓存（url → Bitmap），避免每次更新通知都重新下载
    private val artCache = ConcurrentHashMap<String, Bitmap>()
    private var currentArtBitmap: Bitmap? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME).also {
            it.setMethodCallHandler(this)
        }
        MediaNotificationPluginHolder.plugin = this
        ensureSession()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        session?.release()
        session = null
        context?.let { cancelNotification(it) }
        if (MediaNotificationPluginHolder.plugin === this) {
            MediaNotificationPluginHolder.plugin = null
        }
        context = null
    }

    /// 由 [MediaNotificationReceiver] 调用：触发 MediaSession transport controls，
    /// 进而走 [MediaSessionCompat.Callback] → [sendToFlutter] → MethodChannel → Flutter。
    fun onTransportControl(action: String) {
        val s = session ?: return
        val controls = s.controller.transportControls
        when (action) {
            "play" -> controls.play()
            "pause" -> controls.pause()
            "playPause" -> {
                if (isPlaying) controls.pause() else controls.play()
            }
            "next" -> controls.skipToNext()
            "previous" -> controls.skipToPrevious()
            "stop" -> controls.stop()
        }
    }

    private fun ensureSession() {
        val ctx = context ?: return
        if (session == null) {
            session = MediaSessionCompat(ctx, "CyreneMusic").apply {
                setFlags(
                    MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or
                        MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS,
                )
                setCallback(object : MediaSessionCompat.Callback() {
                    override fun onPlay() = sendToFlutter("play")
                    override fun onPause() = sendToFlutter("pause")
                    override fun onSkipToNext() = sendToFlutter("next")
                    override fun onSkipToPrevious() = sendToFlutter("previous")
                    override fun onSeekTo(pos: Long) {
                        mainHandler.post { channel?.invokeMethod("seek", pos) }
                    }
                    override fun onStop() = sendToFlutter("stop")
                })
                isActive = true
            }
        }
        ensureNotificationChannel(ctx)
    }

    private fun ensureNotificationChannel(ctx: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (manager.getNotificationChannel(CHANNEL_ID) == null) {
                val chan = NotificationChannel(
                    CHANNEL_ID,
                    "音乐播放",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "媒体播放控制"
                    setShowBadge(false)
                }
                manager.createNotificationChannel(chan)
            }
        }
    }

    // ==================== MethodChannel 入口 ====================

    override fun onMethodCall(call: MethodCall, result: Result) {
        val args = (call.arguments as? Map<*, *>) ?: emptyMap<Any, Any?>()
        when (call.method) {
            "ready" -> {
                ensureSession()
                result.success(null)
            }
            "updateTrack" -> {
                title = args["title"]?.toString() ?: ""
                artist = args["artist"]?.toString() ?: ""
                album = args["album"]?.toString() ?: ""
                artUrl = args["artUrl"]?.toString() ?: ""
                durationMs = (args["durationMs"] as? Number)?.toLong() ?: 0L
                positionMs = (args["positionMs"] as? Number)?.toLong() ?: 0L
                isPlaying = args["isPlaying"] as? Boolean ?: false
                lastPositionUpdateTime = SystemClock.elapsedRealtime()
                loadArtAsync(artUrl) { bmp ->
                    currentArtBitmap = bmp
                    updateMediaSession()
                    updateNotification()
                }
                result.success(null)
            }
            "updatePlayback" -> {
                isPlaying = args["isPlaying"] as? Boolean ?: false
                positionMs = (args["positionMs"] as? Number)?.toLong() ?: 0L
                lastPositionUpdateTime = SystemClock.elapsedRealtime()
                updateMediaSession()
                updateNotification()
                result.success(null)
            }
            "updatePosition" -> {
                positionMs = (args["positionMs"] as? Number)?.toLong() ?: 0L
                lastPositionUpdateTime = SystemClock.elapsedRealtime()
                updateMediaSessionPlaybackState()
                result.success(null)
            }
            "updateRepeatMode" -> {
                repeatModeName = args["repeatMode"]?.toString() ?: "all"
                updateMediaSessionPlaybackState()
                result.success(null)
            }
            "hide" -> {
                context?.let { cancelNotification(it) }
                session?.isActive = false
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // ==================== MediaSession 状态同步 ====================

    private fun updateMediaSession() {
        val s = session ?: return
        s.setMetadata(buildMetadata())
        updateMediaSessionPlaybackState()
    }

    private fun updateMediaSessionPlaybackState() {
        val s = session ?: return
        val state = if (isPlaying)
            PlaybackStateCompat.STATE_PLAYING
        else
            PlaybackStateCompat.STATE_PAUSED

        val actions = (
            PlaybackStateCompat.ACTION_PLAY or
                PlaybackStateCompat.ACTION_PAUSE or
                PlaybackStateCompat.ACTION_PLAY_PAUSE or
                PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
                PlaybackStateCompat.ACTION_SEEK_TO or
                PlaybackStateCompat.ACTION_STOP
            )

        val builder = PlaybackStateCompat.Builder()
            .setActions(actions)
            .setState(state, positionMs, 1.0f, lastPositionUpdateTime)

        s.setPlaybackState(builder.build())
        s.setRepeatMode(repeatModeToCompat(repeatModeName))
    }

    private fun buildMetadata(): MediaMetadataCompat {
        val builder = MediaMetadataCompat.Builder()
            .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
            .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist)
            .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, album)
            .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, durationMs)
        currentArtBitmap?.let { bmp ->
            builder.putBitmap(MediaMetadataCompat.METADATA_KEY_ART, bmp)
        }
        return builder.build()
    }

    /// 把 Flutter 端的循环模式名称映射到 [PlaybackStateCompat] 常量。
    private fun repeatModeToCompat(name: String): Int = when (name) {
        "off" -> PlaybackStateCompat.REPEAT_MODE_NONE
        "one" -> PlaybackStateCompat.REPEAT_MODE_ONE
        "all", "shuffle" -> PlaybackStateCompat.REPEAT_MODE_ALL
        else -> PlaybackStateCompat.REPEAT_MODE_ALL
    }

    // ==================== 通知栏 ====================

    private fun updateNotification() {
        val ctx = context ?: return
        val s = session ?: return
        val notification = buildNotification(ctx, s)
        val manager = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, notification)
    }

    private fun cancelNotification(ctx: Context) {
        val manager = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(NOTIFICATION_ID)
    }

    private fun buildNotification(ctx: Context, s: MediaSessionCompat): Notification {
        val contentIntent = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
        val contentPI = contentIntent?.let {
            PendingIntent.getActivity(
                ctx, 0, it,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        }

        val playPauseAction = NotificationCompat.Action(
            if (isPlaying) android.R.drawable.ic_media_pause
            else android.R.drawable.ic_media_play,
            if (isPlaying) "暂停" else "播放",
            buildTransportPI(ctx, if (isPlaying) "pause" else "play"),
        )
        val prevAction = NotificationCompat.Action(
            android.R.drawable.ic_media_previous,
            "上一首",
            buildTransportPI(ctx, "previous"),
        )
        val nextAction = NotificationCompat.Action(
            android.R.drawable.ic_media_next,
            "下一首",
            buildTransportPI(ctx, "next"),
        )

        val builder = NotificationCompat.Builder(ctx, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(artist)
            .setSubText(album.takeIf { it.isNotEmpty() })
            .setContentIntent(contentPI)
            .setShowWhen(false)
            .setOnlyAlertOnce(true)
            .setOngoing(isPlaying)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .addAction(prevAction)
            .addAction(playPauseAction)
            .addAction(nextAction)
            .setStyle(
                MediaStyle()
                    .setMediaSession(s.sessionToken)
                    .setShowActionsInCompactView(0, 1, 2),
            )

        currentArtBitmap?.let { builder.setLargeIcon(it) }
        return builder.build()
    }

    /// 构造一个触发 [MediaNotificationReceiver] 的广播 PendingIntent，
    /// 接收器再通过 MediaSession 的 transport controls 触发回调。
    private fun buildTransportPI(ctx: Context, action: String): PendingIntent {
        val intent = Intent(ctx, MediaNotificationReceiver::class.java).apply {
            this.action = "com.cyrene.media.$action"
        }
        return PendingIntent.getBroadcast(
            ctx, action.hashCode(), intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    private fun sendToFlutter(method: String) {
        mainHandler.post { channel?.invokeMethod(method, null) }
    }

    // ==================== 封面异步加载 ====================

    private fun loadArtAsync(url: String, callback: (Bitmap?) -> Unit) {
        if (url.isEmpty()) {
            callback(null)
            return
        }
        artCache[url]?.let { callback(it); return }
        Thread {
            val bmp = downloadBitmap(url)
            if (bmp != null) artCache[url] = bmp
            mainHandler.post { callback(bmp) }
        }.start()
    }

    private fun downloadBitmap(urlStr: String): Bitmap? {
        return try {
            val conn = URL(urlStr).openConnection() as HttpURLConnection
            conn.connectTimeout = 8000
            conn.readTimeout = 8000
            conn.requestMethod = "GET"
            conn.instanceFollowRedirects = true
            conn.inputStream.use { input ->
                BitmapFactory.decodeStream(input)
            }
        } catch (e: Exception) {
            null
        }
    }
}
