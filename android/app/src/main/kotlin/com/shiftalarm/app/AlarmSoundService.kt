package com.shiftalarm.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

/**
 * 鬧鐘響鈴前台服務：熄屏／Doze 下保證鈴聲照播。
 * 背景 startActivity 會被系統攔截（Android 10+ ＋ MIUI），所以鈴聲唔再依賴 AlarmActivity；
 * 改由呢個 foreground service 播 MediaPlayer（USAGE_ALARM），通知帶 fullScreenIntent＋關閉掣。
 */
class AlarmSoundService : Service() {

    private var player: MediaPlayer? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSound()
            return START_NOT_STICKY
        }

        val id = intent?.getIntExtra(AlarmScheduler.EXTRA_ALARM_ID, 0) ?: 0
        val title = intent?.getStringExtra(AlarmScheduler.EXTRA_TITLE) ?: "排班鬧鐘"
        val body = intent?.getStringExtra(AlarmScheduler.EXTRA_BODY) ?: ""
        val accentBg = intent?.getIntExtra(
            AlarmScheduler.EXTRA_ACCENT_BG, AlarmScheduler.DEFAULT_ACCENT_BG)
            ?: AlarmScheduler.DEFAULT_ACCENT_BG
        val accentFg = intent?.getIntExtra(
            AlarmScheduler.EXTRA_ACCENT_FG, AlarmScheduler.DEFAULT_ACCENT_FG)
            ?: AlarmScheduler.DEFAULT_ACCENT_FG
        val shiftName = intent?.getStringExtra(AlarmScheduler.EXTRA_SHIFT_NAME) ?: ""
        val startTime = intent?.getStringExtra(AlarmScheduler.EXTRA_START_TIME) ?: ""
        val date = intent?.getStringExtra(AlarmScheduler.EXTRA_DATE) ?: ""
        val note = intent?.getStringExtra(AlarmScheduler.EXTRA_NOTE) ?: ""

        // 關鍵：第一件事就 startForeground，之前唔做其他嘢——
        // startForegroundService() 之後幾秒內未調 startForeground()，
        // 系統就掟 ForegroundServiceDidNotStartInTimeException。
        // （舊版開頭調 stopSound()，入面有 stopSelf()，未做前台就自殺。）
        ensureChannel(this)
        val notif = try {
            buildNotification(id, title, body, accentBg, accentFg,
                shiftName, startTime, date, note)
        } catch (_: Exception) {
            null
        }
        try {
            // 正常路徑：前台服務＋通知（ServiceCompat 免版本分支）
            ServiceCompat.startForeground(
                this,
                id.ifZeroThen(1),
                notif!!,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            )
        } catch (_: Exception) {
            // 降級：startForeground 被拒都照發通知＋播聲，唔靜默死
            try {
                val nm = getSystemService(Context.NOTIFICATION_SERVICE)
                    as NotificationManager
                if (notif != null) nm.notify(id.ifZeroThen(1), notif)
            } catch (_: Exception) {
            }
        }

        // 之後先：停舊聲（只停 player，唔 stopSelf）、wakelock、播聲
        stopPlayerOnly()
        acquireWakeLock()
        startRinging()

        return START_NOT_STICKY
    }

    /**
     * 只停舊 player＋放 wakelock，唔 stopSelf、唔 stopForeground。
     * onStartCommand 開頭用——未做前台之前唔可以自殺，否則又掟 DidNotStartInTime。
     */
    private fun stopPlayerOnly() {
        try {
            player?.let {
                if (it.isPlaying) it.stop()
                it.release()
            }
        } catch (_: Exception) {
        }
        player = null
        try {
            wakeLock?.let { if (it.isHeld) it.release() }
        } catch (_: Exception) {
        }
        wakeLock = null
    }

    private fun startRinging() {
        try {
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            player = MediaPlayer().apply {
                setDataSource(applicationContext, uri)
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                isLooping = true
                // 非同步 prepare，免 main thread 阻塞 ANR
                setOnPreparedListener { it.start() }
                prepareAsync()
            }
        } catch (_: Exception) {
            // 播唔到都唔 crash，通知仲喺度
        }
    }

    private fun buildNotification(
        id: Int, title: String, body: String,
        accentBg: Int, accentFg: Int,
        shiftName: String, startTime: String, date: String, note: String
    ): Notification {
        // 兩個獨立 Intent/PI：分得出係系統自動彈（fullscreen）定用戶手動㩒通知（content）。
        // 唔好共用同一個再 putExtra 覆蓋——PendingIntent 會複用。
        fun activityIntent(source: String) = Intent(this, AlarmActivity::class.java).apply {
            putExtra(AlarmScheduler.EXTRA_ALARM_ID, id)
            putExtra(AlarmScheduler.EXTRA_TITLE, title)
            putExtra(AlarmScheduler.EXTRA_BODY, body)
            putExtra(AlarmScheduler.EXTRA_ACCENT_BG, accentBg)
            putExtra(AlarmScheduler.EXTRA_ACCENT_FG, accentFg)
            putExtra(AlarmScheduler.EXTRA_SHIFT_NAME, shiftName)
            putExtra(AlarmScheduler.EXTRA_START_TIME, startTime)
            putExtra(AlarmScheduler.EXTRA_DATE, date)
            putExtra(AlarmScheduler.EXTRA_NOTE, note)
            putExtra(AlarmScheduler.EXTRA_LAUNCH_SOURCE, source)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val fullPi = PendingIntent.getActivity(
            this, 1000 + id, activityIntent("fullscreen"),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val contentPi = PendingIntent.getActivity(
            this, 2000 + id, activityIntent("content"),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // 通知 action：經 BroadcastReceiver 處理，唔經 startService
        //（熄屏後台 startService 會被系統掟 IllegalStateException，停唔到聲）。
        val actionExtras = mapOf(
            AlarmScheduler.EXTRA_ALARM_ID to id,
            AlarmScheduler.EXTRA_TITLE to title,
            AlarmScheduler.EXTRA_BODY to body,
            AlarmScheduler.EXTRA_ACCENT_BG to accentBg,
            AlarmScheduler.EXTRA_ACCENT_FG to accentFg,
            AlarmScheduler.EXTRA_SHIFT_NAME to shiftName,
            AlarmScheduler.EXTRA_START_TIME to startTime,
            AlarmScheduler.EXTRA_DATE to date,
            AlarmScheduler.EXTRA_NOTE to note
        )
        val stopPi = PendingIntent.getBroadcast(
            this, 100 + id,
            Intent(this, AlarmActionReceiver::class.java).apply {
                action = AlarmActions.ACTION_STOP
                actionExtras.forEach { (k, v) ->
                    when (v) {
                        is Int -> putExtra(k, v)
                        is String -> putExtra(k, v)
                    }
                }
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val snoozePi = PendingIntent.getBroadcast(
            this, 200 + id,
            Intent(this, AlarmActionReceiver::class.java).apply {
                action = AlarmActions.ACTION_SNOOZE
                actionExtras.forEach { (k, v) ->
                    when (v) {
                        is Int -> putExtra(k, v)
                        is String -> putExtra(k, v)
                    }
                }
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, AlarmReceiver.CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setFullScreenIntent(fullPi, true)
            .setContentIntent(contentPi)
            .setVibrate(longArrayOf(0, 400, 200, 400))
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "停止", stopPi)
            .addAction(android.R.drawable.ic_lock_idle_alarm, "5 分鐘後再響", snoozePi)
            .setAutoCancel(true)
            .setOngoing(true)
            .build()
    }

    private fun acquireWakeLock() {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK, "$TAG:alarm"
            ).apply {
                // 10 分鐘 timeout 保險，唔會長 hold
                acquire(10 * 60 * 1000L)
            }
        } catch (_: Exception) {
        }
    }

    /** 完整停聲：停 player＋放 wakelock＋落前台＋自殺 */
    internal fun stopSound() {
        try {
            player?.let {
                if (it.isPlaying) it.stop()
                it.release()
            }
        } catch (_: Exception) {
        }
        player = null
        try {
            wakeLock?.let { if (it.isHeld) it.release() }
        } catch (_: Exception) {
        }
        wakeLock = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        instance = null
        try {
            player?.let {
                if (it.isPlaying) it.stop()
                it.release()
            }
        } catch (_: Exception) {
        }
        player = null
        try {
            wakeLock?.let { if (it.isHeld) it.release() }
        } catch (_: Exception) {
        }
        wakeLock = null
        super.onDestroy()
    }

    private fun Int.ifZeroThen(other: Int) = if (this == 0) other else this

    companion object {
        const val ACTION_STOP = "com.museai.shift_alarm.ACTION_STOP_SOUND"
        private const val TAG = "AlarmSoundService"

        /** 活緊嘅 service 實例：畀外部直接停聲，唔經 startService（熄屏後台會被掟）。 */
        @Volatile
        private var instance: AlarmSoundService? = null

        /** 直接停聲（null-safe）。instance 唔喺就乜都唔做。 */
        fun stopNow() {
            try {
                instance?.stopSound()
            } catch (_: Exception) {
            }
        }

        fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val nm =
                    context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                // 用戶可能手動調低過 channel 重要性——舊 code 唔會修復，
                // 刪咗重建，確保永遠係 HIGH（fullScreenIntent 必須）。
                val existing = nm.getNotificationChannel(AlarmReceiver.CHANNEL_ID)
                if (existing != null &&
                    existing.importance != NotificationManager.IMPORTANCE_HIGH
                ) {
                    nm.deleteNotificationChannel(AlarmReceiver.CHANNEL_ID)
                }
                if (nm.getNotificationChannel(AlarmReceiver.CHANNEL_ID) == null) {
                    nm.createNotificationChannel(
                        NotificationChannel(
                            AlarmReceiver.CHANNEL_ID,
                            "排班鬧鐘",
                            NotificationManager.IMPORTANCE_HIGH
                        ).apply {
                            description = "更次鬧鐘"
                            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                            // 勿擾下都響
                            setBypassDnd(true)
                            enableVibration(true)
                            vibrationPattern = longArrayOf(0, 400, 200, 400)
                        }
                    )
                }
            }
        }

        /**
         * 供外部（AlarmActivity 關閉掣／通知 action）停聲用。
         * 優先直接調活緊嘅 instance——熄屏後台 startService 會被系統掟
         * IllegalStateException，舊版就係咁停唔到聲。instance 唔喺先
         * fallback 發 ACTION_STOP intent。
         */
        fun stop(context: Context) {
            val svc = instance
            if (svc != null) {
                stopNow()
                return
            }
            val i = Intent(context, AlarmSoundService::class.java).apply {
                action = ACTION_STOP
            }
            try {
                ContextCompat.startForegroundService(context, i)
            } catch (_: Exception) {
                try {
                    context.startService(i)
                } catch (_: Exception) {
                }
            }
        }
    }
}
