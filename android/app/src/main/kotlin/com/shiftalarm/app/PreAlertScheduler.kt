package com.shiftalarm.app

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * 響鬧預告排程器。
 *
 * 針對啟用且非純通知類型的鬧鐘，於預定觸發時刻前 60 分鐘排定預告廣播，
 * 由 [PreAlertReceiver] 發布狀態欄倒計時 ongoing 通知。
 */
object PreAlertScheduler {
    /** 預告 id 命名空間偏移，須與 Dart `AlarmService.preAlertIdOffset` 一致。 */
    const val PRE_ALERT_ID_OFFSET = 900000

    /** 預告提前量（分鐘），須與 Dart `AlarmService.preAlertLeadMinutes` 一致。 */
    const val LEAD_MINUTES = 60

    const val EXTRA_PRE_ALERT_DATE = "pre_alert_date"
    const val EXTRA_TRIGGER_AT = "pre_alert_trigger_at"

    private const val KEY_IDS = AlarmIdRegistry.KEY_PRE_ALERT
    private const val LEAD_MILLIS = LEAD_MINUTES * 60_000L
    private const val IMMEDIATE_FIRE_DELAY_MILLIS = 1_000L

    fun preAlertId(alarmId: Int): Int = alarmId + PRE_ALERT_ID_OFFSET

    fun schedule(
        context: Context,
        alarmId: Int,
        triggerAtMillis: Long,
        title: String,
        body: String,
        date: String = "",
        shiftName: String = "",
        startTime: String = "",
        note: String = ""
    ) {
        val now = System.currentTimeMillis()
        val leadAt = triggerAtMillis - LEAD_MILLIS
        val preId = preAlertId(alarmId)

        if (PreAlertDismissStore.isDismissed(context, preId, triggerAtMillis)) {
            return
        }

        if (triggerAtMillis <= now) {
            cancelNotification(context, alarmId)
            return
        }

        val inWindow = leadAt <= now
        try {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(context, PreAlertReceiver::class.java).apply {
                putExtra(AlarmScheduler.EXTRA_ALARM_ID, alarmId)
                putExtra(AlarmScheduler.EXTRA_TITLE, title)
                putExtra(AlarmScheduler.EXTRA_BODY, body)
                putExtra(EXTRA_TRIGGER_AT, triggerAtMillis)
                putExtra(EXTRA_PRE_ALERT_DATE, date)
                putExtra(AlarmScheduler.EXTRA_SHIFT_NAME, shiftName)
                putExtra(AlarmScheduler.EXTRA_START_TIME, startTime)
                putExtra(AlarmScheduler.EXTRA_NOTE, note)
            }
            val pi = PendingIntent.getBroadcast(
                context,
                preId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            if (inWindow) {
                am.set(
                    AlarmManager.RTC_WAKEUP,
                    now + IMMEDIATE_FIRE_DELAY_MILLIS,
                    pi
                )
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, leadAt, pi)
            } else {
                am.setExact(AlarmManager.RTC_WAKEUP, leadAt, pi)
            }

            AlarmIdRegistry.remember(context, KEY_IDS, preId)
            AlarmDebugLog.append(
                context,
                if (inWindow) {
                    "[PRE_ALERT_SCHED] id=$alarmId mode=immediate triggerAt=$triggerAtMillis"
                } else {
                    "[PRE_ALERT_SCHED] id=$alarmId mode=exact leadAt=$leadAt"
                }
            )
        } catch (e: Exception) {
            AlarmDebugLog.append(context, "[PRE_ALERT_FAIL] id=$alarmId $e")
        }
    }

    fun cancel(context: Context, alarmId: Int) {
        val preId = preAlertId(alarmId)
        cancelAlarmById(context, preId)
        cancelNotification(context, alarmId)
        AlarmIdRegistry.forgetId(context, KEY_IDS, preId)
    }

    fun cancelNotification(context: Context, alarmId: Int) {
        try {
            val nm = context.getSystemService(
                Context.NOTIFICATION_SERVICE
            ) as NotificationManager
            nm.cancel(preAlertId(alarmId))
        } catch (_: Exception) {
        }
    }

    fun rescheduleAll(context: Context, specs: List<Map<String, Any?>>) {
        val now = System.currentTimeMillis()
        val keep = mutableSetOf<Int>()
        for (spec in specs) {
            try {
                val alarmId = (spec["alarmId"] as? Number)?.toInt() ?: continue
                val triggerAtMillis =
                    (spec["triggerAtMillis"] as? Number)?.toLong() ?: continue
                if (triggerAtMillis > now) {
                    keep.add(preAlertId(alarmId))
                }
                schedule(
                    context = context,
                    alarmId = alarmId,
                    triggerAtMillis = triggerAtMillis,
                    title = spec["title"] as? String ?: "",
                    body = spec["body"] as? String ?: "",
                    date = spec["date"] as? String ?: "",
                    shiftName = spec["shiftName"] as? String ?: "",
                    startTime = spec["startTime"] as? String ?: "",
                    note = spec["note"] as? String ?: ""
                )
            } catch (_: Exception) {
            }
        }
        prune(context, keep)
    }

    fun prune(context: Context, keepIds: Set<Int>) {
        AlarmIdRegistry.prune(context, KEY_IDS, keepIds) { staleId ->
            cancelAlarmById(context, staleId)
            try {
                val nm = context.getSystemService(
                    Context.NOTIFICATION_SERVICE
                ) as NotificationManager
                nm.cancel(staleId)
            } catch (_: Exception) {
            }
        }
    }

    fun markDismissed(context: Context, alarmId: Int, triggerAtMillis: Long) {
        PreAlertDismissStore.markDismissed(
            context,
            preAlertId(alarmId),
            alarmId,
            triggerAtMillis
        )
    }

    private fun cancelAlarmById(context: Context, preId: Int) {
        try {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val pi = PendingIntent.getBroadcast(
                context,
                preId,
                Intent(context, PreAlertReceiver::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            am.cancel(pi)
            pi.cancel()
        } catch (_: Exception) {
        }
    }
}
