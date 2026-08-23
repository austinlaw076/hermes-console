package com.hermesagent.hermes_android

import android.content.SharedPreferences
import kotlin.math.roundToInt
import org.json.JSONObject

private const val PREFIX = "hermes_widget_"
private const val SCHEMA_VERSION = 1
private const val ATOMIC_SNAPSHOT = "atomic_snapshot_v1"
internal const val STALE_AFTER_MS = 15 * 60 * 1000L
private val OPAQUE_ID = Regex("^[A-Za-z0-9._:@+-]+$")

internal enum class HermesWidgetConnectionState {
    UNCONFIGURED,
    NO_INSTANCE,
    CONNECTING,
    CONNECTED,
    ERROR,
    DISCONNECTED,
}

internal enum class HermesWidgetAgentState {
    IDLE,
    THINKING,
    STREAMING,
    TOOL_EXECUTION,
    WAITING_APPROVAL,
    ERROR,
    DISCONNECTED,
}

internal enum class HermesWidgetTheme {
    LIGHT,
    DARK,
    OLED,
}

internal data class HermesWidgetState(
    val configured: Boolean = false,
    val instanceId: String? = null,
    val instanceLabel: String? = null,
    val connectionState: HermesWidgetConnectionState =
        HermesWidgetConnectionState.UNCONFIGURED,
    val model: String? = null,
    val provider: String? = null,
    val sessionId: String? = null,
    val sessionTitle: String? = null,
    val agentState: HermesWidgetAgentState = HermesWidgetAgentState.DISCONNECTED,
    val toolName: String? = null,
    val contextUsed: Long? = null,
    val contextMax: Long? = null,
    val contextPercent: Int? = null,
    val inputTokens: Long? = null,
    val outputTokens: Long? = null,
    val cacheReadTokens: Long? = null,
    val cacheWriteTokens: Long? = null,
    val firstTokenLatencyMs: Long? = null,
    val lastActivityAtMs: Long? = null,
    val updatedAtMs: Long = 0,
    val theme: HermesWidgetTheme = HermesWidgetTheme.DARK,
    val showAdvancedMetrics: Boolean = true,
) {
    fun isStale(nowMs: Long): Boolean =
        updatedAtMs <= 0 || nowMs - updatedAtMs > STALE_AFTER_MS

    fun staleAtMs(): Long? =
        updatedAtMs
            .takeIf { it > 0 && it <= Long.MAX_VALUE - STALE_AFTER_MS - 1 }
            ?.plus(STALE_AFTER_MS + 1)

    val cachePercent: Int?
        get() {
            val read = cacheReadTokens ?: return null
            val input = inputTokens ?: return null
            val prompt = input + read + (cacheWriteTokens ?: 0)
            if (read <= 0 || prompt <= 0) return null
            return ((read.toDouble() / prompt.toDouble()) * 100)
                .roundToInt()
                .coerceIn(0, 100)
        }

    companion object {
        fun from(preferences: SharedPreferences): HermesWidgetState {
            val atomic = preferences.atomicSnapshotValues()
            if (atomic != null) parse(atomic)?.let { return it }
            return parse(preferences.legacySnapshotValues()) ?: HermesWidgetState()
        }

        private fun parse(values: Map<String, Any?>): HermesWidgetState? {
            if (values.safeLong("schema_version") != SCHEMA_VERSION.toLong()) return null
            val used = values.safeNonNegativeLong("context_used")
            val max = values.safePositiveLong("context_max")
            val supplied = values.safeNonNegativeLong("context_percent")?.toInt()
            val percent =
                if (used == null || max == null) {
                    null
                } else {
                    (supplied ?: ((used.toDouble() / max) * 100).roundToInt())
                        .coerceIn(0, 100)
                }
            return HermesWidgetState(
                configured = values["configured"] == true,
                instanceId = values.safeText("instance_id", 256, opaque = true),
                instanceLabel = values.safeText("instance_label", 64),
                connectionState =
                    enumValue(
                        values.safeText("connection_state", 32),
                        HermesWidgetConnectionState.UNCONFIGURED,
                    ),
                model = values.safeText("model", 96),
                provider = values.safeText("provider", 64),
                sessionId = values.safeText("session_id", 256, opaque = true),
                sessionTitle = values.safeText("session_title", 96),
                agentState =
                    enumValue(
                        values.safeText("agent_state", 32),
                        HermesWidgetAgentState.DISCONNECTED,
                    ),
                toolName = values.safeText("tool_name", 64),
                contextUsed = used,
                contextMax = max,
                contextPercent = percent,
                inputTokens = values.safeNonNegativeLong("input_tokens"),
                outputTokens = values.safeNonNegativeLong("output_tokens"),
                cacheReadTokens = values.safeNonNegativeLong("cache_read_tokens"),
                cacheWriteTokens = values.safeNonNegativeLong("cache_write_tokens"),
                firstTokenLatencyMs = values.safeNonNegativeLong("first_token_latency_ms"),
                lastActivityAtMs = values.safeNonNegativeLong("last_activity_at_ms"),
                updatedAtMs = values.safeNonNegativeLong("updated_at_ms") ?: 0,
                theme =
                    enumValue(
                        values.safeText("theme", 16),
                        HermesWidgetTheme.DARK,
                    ),
                showAdvancedMetrics = values["show_advanced_metrics"] as? Boolean ?: true,
            )
        }
    }
}

private fun key(name: String) = "$PREFIX$name"

private fun SharedPreferences.atomicSnapshotValues(): Map<String, Any?>? =
    try {
        val raw = getString(key(ATOMIC_SNAPSHOT), null) ?: return null
        val json = JSONObject(raw)
        buildMap {
            val names = json.keys()
            while (names.hasNext()) {
                val name = names.next()
                put(name, json.opt(name).takeUnless { it === JSONObject.NULL })
            }
        }
    } catch (_: Exception) {
        null
    }

private fun SharedPreferences.legacySnapshotValues(): Map<String, Any?> =
    try {
        buildMap {
            for ((storedKey, value) in all) {
                if (storedKey.startsWith(PREFIX)) {
                    put(storedKey.removePrefix(PREFIX), value)
                }
            }
        }
    } catch (_: RuntimeException) {
        emptyMap()
    }

private fun Map<String, Any?>.safeLong(name: String): Long? =
    when (val value = this[name]) {
        is Int -> value.toLong()
        is Long -> value
        is String -> value.toLongOrNull()
        else -> null
    }

private fun Map<String, Any?>.safeNonNegativeLong(name: String): Long? =
    safeLong(name)?.takeIf { it >= 0 }

private fun Map<String, Any?>.safePositiveLong(name: String): Long? =
    safeNonNegativeLong(name)?.takeIf { it > 0 }

private fun Map<String, Any?>.safeText(
    name: String,
    maxLength: Int,
    opaque: Boolean = false,
): String? =
    (this[name] as? String)
        ?.trim()
        ?.takeIf { it.isNotEmpty() && (!opaque || OPAQUE_ID.matches(it)) }
        ?.take(maxLength)

private inline fun <reified T : Enum<T>> enumValue(raw: String?, fallback: T): T {
    if (raw == null) return fallback
    val wire = raw.replace(Regex("([a-z])([A-Z])"), "$1_$2").uppercase()
    return enumValues<T>().firstOrNull { it.name == wire } ?: fallback
}
