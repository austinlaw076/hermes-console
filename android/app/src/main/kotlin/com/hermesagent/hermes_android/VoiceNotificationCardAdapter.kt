package com.hermesagent.hermes_android

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.widget.RemoteViews

/**
 * It decorates the notification already owned by flutter_foreground_task. It
 * never starts a service, creates a channel, allocates another notification id
 * or handles voice state. The compact view and native actions remain those of
 * the plugin; only the expanded body is replaced with redacted RemoteViews.
 */
internal object VoiceNotificationCardAdapter {
    private const val TAG = "HermesVoiceCard"
    private const val SERVICE_NOTIFICATION_ID = 256
    private val RETRY_DELAYS_MS =
        longArrayOf(24L, 48L, 96L, 160L, 250L, 400L, 650L, 1_000L)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var startedAtElapsedRealtime: Long? = null
    private var cachedActions: CardActions? = null
    private var requestGeneration = 0L

    /**
     * flutter_foreground_task acknowledges updateService() after enqueueing a
     * startService intent, not after NotificationManager receives the rebuilt
     * notification. Decorating immediately can therefore recover and repost
     * stale actions (for example, "Pause" beside a paused card) or run before
     * the first notification exists. Wait for the expected primary action and
     * let the newest request supersede retries from an older voice state.
     */
    fun apply(
        context: Context,
        paused: Boolean,
        expectedPrimaryAction: String,
        stateLabel: String,
        microphoneLabel: String,
        openHintLabel: String,
        orbDescription: String,
        durationDescription: String,
    ): Map<String, Any> {
        val appContext = context.applicationContext
        val generation = synchronized(this) {
            requestGeneration += 1
            requestGeneration
        }
        return try {
            val attempt = decorateIfReady(
                appContext,
                paused,
                expectedPrimaryAction,
                stateLabel,
                microphoneLabel,
                openHintLabel,
                orbDescription,
                durationDescription,
            )
            if (attempt.notification != null) {
                Log.d(TAG, "apply succeeded (immediate)")
                return snapshot(attempt.notification) + ("applied" to true)
            }
            scheduleRetry(
                appContext,
                paused,
                expectedPrimaryAction,
                stateLabel,
                microphoneLabel,
                openHintLabel,
                orbDescription,
                durationDescription,
                generation,
                retryIndex = 0,
            )
            Log.d(TAG, "apply deferred (${attempt.reason})")
            mapOf(
                "applied" to false,
                "scheduled" to true,
                "reason" to attempt.reason,
            )
        } catch (error: Exception) {
            // Categorical only: never log notification extras or user content.
            Log.w(TAG, "apply failed (${error.javaClass.simpleName})")
            mapOf(
                "applied" to false,
                "scheduled" to false,
                "reason" to error.javaClass.simpleName,
            )
        }
    }

    private fun decorateIfReady(
        context: Context,
        paused: Boolean,
        expectedPrimaryAction: String,
        stateLabel: String,
        microphoneLabel: String,
        openHintLabel: String,
        orbDescription: String,
        durationDescription: String,
    ): DecorationAttempt {
        val manager = context.getSystemService(NotificationManager::class.java)
        val active = manager.activeNotifications.firstOrNull {
            it.id == SERVICE_NOTIFICATION_ID && it.packageName == context.packageName
        } ?: return DecorationAttempt(reason = "notification_not_active")

        val advertisedActions = active.notification.actions
        val primaryAction = advertisedActions
            ?.firstOrNull()
            ?.title
            ?.toString()
        if (primaryAction != null && primaryAction != expectedPrimaryAction) {
            return DecorationAttempt(reason = "actions_not_ready")
        }
        val actions = if (primaryAction == expectedPrimaryAction) {
            val primary = advertisedActions.firstOrNull()
            val end = advertisedActions.getOrNull(1)
            val primaryIntent = primary?.actionIntent
            val endIntent = end?.actionIntent
            if (primary == null || end == null || primaryIntent == null || endIntent == null) {
                return DecorationAttempt(reason = "actions_not_ready")
            }
            CardActions(
                primaryLabel = primary.title,
                primaryIntent = primaryIntent,
                endLabel = end.title,
                endIntent = endIntent,
            ).also { resolved ->
                synchronized(this) { cachedActions = resolved }
            }
        } else {
            synchronized(this) {
                cachedActions?.takeIf {
                    it.primaryLabel.toString() == expectedPrimaryAction
                }
            } ?: return DecorationAttempt(reason = "actions_not_ready")
        }

        val startedAt = synchronized(this) {
            startedAtElapsedRealtime
                ?: SystemClock.elapsedRealtime().also { startedAtElapsedRealtime = it }
        }
        val bigView = RemoteViews(
            context.packageName,
            R.layout.notification_voice_expanded,
        ).apply {
            setImageViewResource(
                R.id.voice_notification_orb,
                if (paused) {
                    R.drawable.notification_voice_orb_paused
                } else {
                    R.drawable.notification_voice_orb_active
                },
            )
            setTextViewText(
                R.id.voice_notification_state,
                stateLabel.ifEmpty {
                    context.getString(
                        if (paused) {
                            R.string.voice_notification_paused
                        } else {
                            R.string.voice_notification_active
                        },
                    )
                },
            )
            setTextViewText(
                R.id.voice_notification_mic,
                microphoneLabel.ifEmpty {
                    context.getString(
                        if (paused) {
                            R.string.voice_notification_mic_paused
                        } else {
                            R.string.voice_notification_mic_active
                        },
                    )
                },
            )
            setTextViewText(
                R.id.voice_notification_open_hint,
                openHintLabel.ifEmpty {
                    context.getString(R.string.voice_notification_open_hint)
                },
            )
            setContentDescription(
                R.id.voice_notification_orb,
                orbDescription.ifEmpty {
                    context.getString(R.string.voice_notification_orb)
                },
            )
            setContentDescription(
                R.id.voice_notification_duration,
                durationDescription.ifEmpty {
                    context.getString(R.string.voice_notification_duration)
                },
            )
            setChronometer(
                R.id.voice_notification_duration,
                startedAt,
                null,
                !paused,
            )
            setTextViewText(
                R.id.voice_notification_primary_action,
                actions.primaryLabel,
            )
            setOnClickPendingIntent(
                R.id.voice_notification_primary_action,
                actions.primaryIntent,
            )
            setTextViewText(
                R.id.voice_notification_end_action,
                actions.endLabel,
            )
            setOnClickPendingIntent(
                R.id.voice_notification_end_action,
                actions.endIntent,
            )
        }

        val updated = Notification.Builder
            .recoverBuilder(context, active.notification)
            .setStyle(Notification.DecoratedCustomViewStyle())
            .setCustomBigContentView(bigView)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setActions()
            .build()

        manager.notify(active.tag, SERVICE_NOTIFICATION_ID, updated)
        return DecorationAttempt(notification = updated)
    }

    private fun scheduleRetry(
        context: Context,
        paused: Boolean,
        expectedPrimaryAction: String,
        stateLabel: String,
        microphoneLabel: String,
        openHintLabel: String,
        orbDescription: String,
        durationDescription: String,
        generation: Long,
        retryIndex: Int,
    ) {
        if (retryIndex >= RETRY_DELAYS_MS.size) {
            Log.w(TAG, "apply retries exhausted (notification not ready)")
            return
        }
        mainHandler.postDelayed(
            {
                val current = synchronized(this) { generation == requestGeneration }
                if (!current) return@postDelayed
                try {
                    val attempt = decorateIfReady(
                        context,
                        paused,
                        expectedPrimaryAction,
                        stateLabel,
                        microphoneLabel,
                        openHintLabel,
                        orbDescription,
                        durationDescription,
                    )
                    if (attempt.notification == null) {
                        scheduleRetry(
                            context,
                            paused,
                            expectedPrimaryAction,
                            stateLabel,
                            microphoneLabel,
                            openHintLabel,
                            orbDescription,
                            durationDescription,
                            generation,
                            retryIndex + 1,
                        )
                    } else {
                        Log.d(TAG, "apply succeeded (retry ${retryIndex + 1})")
                    }
                } catch (error: Exception) {
                    Log.w(TAG, "retry failed (${error.javaClass.simpleName})")
                }
            },
            RETRY_DELAYS_MS[retryIndex],
        )
    }

    private data class DecorationAttempt(
        val notification: Notification? = null,
        val reason: String = "",
    )

    private data class CardActions(
        val primaryLabel: CharSequence,
        val primaryIntent: PendingIntent,
        val endLabel: CharSequence,
        val endIntent: PendingIntent,
    )

    fun inspect(context: Context): Map<String, Any> {
        return try {
            val manager = context.getSystemService(NotificationManager::class.java)
            val notification = manager.activeNotifications.firstOrNull {
                it.id == SERVICE_NOTIFICATION_ID && it.packageName == context.packageName
            }?.notification ?: return mapOf("active" to false)
            snapshot(notification) + ("active" to true)
        } catch (error: Exception) {
            mapOf(
                "active" to false,
                "reason" to error.javaClass.simpleName,
            )
        }
    }

    fun clear() {
        synchronized(this) {
            requestGeneration += 1
            startedAtElapsedRealtime = null
            cachedActions = null
        }
    }

    private fun snapshot(notification: Notification): Map<String, Any> = mapOf(
        "active" to true,
        "customBigContentView" to (notification.bigContentView != null),
        "actionCount" to (notification.actions?.size ?: 0),
        "category" to (notification.category ?: ""),
        "visibility" to notification.visibility,
    )
}
