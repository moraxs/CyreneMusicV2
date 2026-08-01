package com.example.cyrene_music_reborn

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/// 媒体通知按钮事件接收器。
///
/// 通知上的播放/暂停/上一首/下一首按钮通过 PendingIntent 触发本接收器，
/// 再由本接收器调用 [MediaNotificationPlugin.onTransportControl] 触发
/// MediaSession transport controls，最终走 MediaSession.Callback →
/// MethodChannel → Flutter。
class MediaNotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        val plugin = MediaNotificationPluginHolder.plugin ?: return
        when (action) {
            ACTION_PLAY -> plugin.onTransportControl("play")
            ACTION_PAUSE -> plugin.onTransportControl("pause")
            ACTION_PLAY_PAUSE -> plugin.onTransportControl("playPause")
            ACTION_NEXT -> plugin.onTransportControl("next")
            ACTION_PREVIOUS -> plugin.onTransportControl("previous")
            ACTION_STOP -> plugin.onTransportControl("stop")
        }
    }

    companion object {
        const val ACTION_PLAY = "com.cyrene.media.play"
        const val ACTION_PAUSE = "com.cyrene.media.pause"
        const val ACTION_PLAY_PAUSE = "com.cyrene.media.playPause"
        const val ACTION_NEXT = "com.cyrene.media.next"
        const val ACTION_PREVIOUS = "com.cyrene.media.previous"
        const val ACTION_STOP = "com.cyrene.media.stop"
    }
}

/// 全局持有 [MediaNotificationPlugin] 引用，供 [MediaNotificationReceiver] 访问。
/// 由 [MainActivity] 在插件注册时赋值。
object MediaNotificationPluginHolder {
    @Volatile
    var plugin: MediaNotificationPlugin? = null
}
