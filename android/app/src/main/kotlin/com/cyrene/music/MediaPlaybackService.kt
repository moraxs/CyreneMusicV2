package com.cyrene.music

import android.app.Notification
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

/// 媒体播放前台服务（`foregroundServiceType="mediaPlayback"`）。
///
/// 只做一件事：播放期间把进程抬成前台服务，让系统别动它。没有它的时候，
/// App 退到后台后就是个普通后台进程——一首歌放完、声音一停，HyperOS 立刻
/// 断掉它的网络（下一首解析报 `Failed host lookup`），随后 GreezeManager 以
/// `reason=AUDIO_APP` 把整个进程冻结。表现就是「切到了下一首但没在播」。
///
/// 通知本身仍由 [MediaNotificationPlugin] 构建、用同一个 ID 更新；本服务只是
/// 拿它去 `startForeground`。前台期间顺带持有 CPU 与 Wi‑Fi 锁：锁屏时切歌那
/// 几秒没有音频输出，CPU 可能休眠、Wi‑Fi 可能进省电，下一首的请求会卡住
/// （同 Media3 的 `WAKE_MODE_NETWORK`）。
class MediaPlaybackService : Service() {
    companion object {
        private const val TAG = "MediaPlaybackService"

        /// 当前要挂在前台的通知。必须在 [start] 之前写好：系统要求
        /// `startForegroundService` 之后 5 秒内调到 `startForeground`。
        @Volatile
        private var pendingNotification: Notification? = null
        private var notificationId: Int = 0

        @Volatile
        private var instance: MediaPlaybackService? = null

        /// 服务已拉起但 `onStartCommand` 还没跑到时收到了停止请求。直接
        /// `stopService` 会撞上「startForegroundService 后没调 startForeground」
        /// 的崩溃，所以记下来，等它先进前台再自己退。
        @Volatile
        private var stopRequested = false

        /// 已调 `startForegroundService`、`onCreate` 还没到。
        @Volatile
        private var starting = false

        /// 进入前台。Android 12+ 不允许从后台启动前台服务（通知按钮、媒体键
        /// 这类用户操作除外），失败时返回 false，调用方退回普通通知即可。
        fun start(context: Context, id: Int, notification: Notification): Boolean {
            pendingNotification = notification
            notificationId = id
            stopRequested = false
            // 暂停后退出前台的服务实例还活着：让它自己重新进前台，不再起一个。
            instance?.let { return it.enterForeground() }
            if (starting) return true
            return try {
                starting = true
                ContextCompat.startForegroundService(
                    context,
                    Intent(context, MediaPlaybackService::class.java),
                )
                true
            } catch (e: Exception) {
                starting = false
                Log.w(TAG, "无法启动前台服务（可能处于后台）", e)
                false
            }
        }

        /// 退出前台。[removeNotification] 为 false 时通知留在通知栏、可被划掉，
        /// 服务退成普通后台服务、留着下次重新进前台（长时间暂停）；为 true 时
        /// 通知一起撤掉、服务结束（关闭播放）。
        fun stop(removeNotification: Boolean) {
            val service = instance
            if (service == null) {
                if (starting) stopRequested = true
                return
            }
            service.exitForeground(removeNotification)
            if (removeNotification) service.stopSelf()
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var inForeground = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        starting = false
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // 不管后面怎样都得先进前台：startForegroundService 之后不调
        // startForeground 会被系统判超时崩溃。进不去就直接退。
        if (!enterForeground()) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (stopRequested) {
            stopRequested = false
            exitForeground(removeNotification = false)
        }
        // 进程被杀后不要自动拉起：没有 Flutter 引擎，起来也播不了。
        return START_NOT_STICKY
    }

    /// 已在前台时什么也不做——通知由插件用同一 ID 直接 notify 更新。
    private fun enterForeground(): Boolean {
        if (inForeground) return true
        val notification = pendingNotification ?: return false
        try {
            ServiceCompat.startForeground(
                this,
                notificationId,
                notification,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
                } else {
                    0
                },
            )
        } catch (e: Exception) {
            // Android 12+ 后台调 startForeground 同样会被拒（ForegroundServiceStartNotAllowedException）。
            Log.w(TAG, "startForeground 失败", e)
            return false
        }
        inForeground = true
        acquireLocks()
        return true
    }

    override fun onDestroy() {
        releaseLocks()
        if (instance === this) instance = null
        starting = false
        super.onDestroy()
    }

    /// 用户从最近任务划掉 App：一并结束，别留个播不了的前台通知。
    override fun onTaskRemoved(rootIntent: Intent?) {
        exitForeground(removeNotification = true)
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    private fun exitForeground(removeNotification: Boolean) {
        releaseLocks()
        inForeground = false
        ServiceCompat.stopForeground(
            this,
            if (removeNotification) {
                ServiceCompat.STOP_FOREGROUND_REMOVE
            } else {
                ServiceCompat.STOP_FOREGROUND_DETACH
            },
        )
    }

    private fun acquireLocks() {
        if (wakeLock == null) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "CyreneMusic:playback",
            ).apply {
                setReferenceCounted(false)
                acquire()
            }
        }
        if (wifiLock == null) {
            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            @Suppress("DEPRECATION")
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                WifiManager.WIFI_MODE_FULL_LOW_LATENCY
            } else {
                WifiManager.WIFI_MODE_FULL_HIGH_PERF
            }
            wifiLock = wm?.createWifiLock(mode, "CyreneMusic:playback")?.apply {
                setReferenceCounted(false)
                acquire()
            }
        }
    }

    private fun releaseLocks() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        wifiLock?.let { if (it.isHeld) it.release() }
        wifiLock = null
    }
}
