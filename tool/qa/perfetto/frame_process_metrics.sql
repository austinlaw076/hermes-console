INCLUDE PERFETTO MODULE slices.with_context;

INCLUDE PERFETTO MODULE android.frames.timeline;

INCLUDE PERFETTO MODULE android.cpu.cpu_per_uid;

INCLUDE PERFETTO MODULE android.kernel_wakelocks;

WITH target_process AS (
  SELECT upid, pid, uid, android_appid, name
  FROM process
  WHERE pid = @TARGET_PID@
    AND uid = @TARGET_UID@
    AND android_appid = @TARGET_APP_ID@
    AND (name GLOB '@PACKAGE@*' OR cmdline GLOB '@PACKAGE@*')
), voice_window AS (
  SELECT
    MIN(scoped.ts) AS window_start,
    MAX(scoped.ts + MAX(scoped.dur, 0)) AS window_end
  FROM thread_or_process_slice AS scoped
  JOIN target_process USING (upid)
  WHERE (scoped.name = 'hermes.voice.turn'
     OR scoped.name GLOB 'hermes.voice.*')
    AND COALESCE(
      EXTRACT_ARG(scoped.arg_set_id, 'route'),
      EXTRACT_ARG(scoped.arg_set_id, 'debug.route')
    ) = '@ROUTE@'
    AND COALESCE(
      EXTRACT_ARG(scoped.arg_set_id, 'scenario'),
      EXTRACT_ARG(scoped.arg_set_id, 'debug.scenario')
    ) = '@SCENARIO@'
), frame_samples AS (
  SELECT
    frames.dur,
    CASE
      WHEN actual.jank_type IS NULL
        OR actual.jank_type IN ('None', 'NONE', '') THEN 0
      ELSE 1
    END AS is_janky,
    ROW_NUMBER() OVER (ORDER BY frames.dur) AS sample_rank,
    COUNT(*) OVER () AS sample_total
  FROM android_frames AS frames
  JOIN target_process USING (upid)
  CROSS JOIN voice_window
  LEFT JOIN actual_frame_timeline_slice AS actual
    ON actual.id = frames.actual_frame_timeline_id
  WHERE voice_window.window_start IS NOT NULL
    AND frames.ts < voice_window.window_end
    AND frames.ts + MAX(frames.dur, 0) > voice_window.window_start
), frame_aggregate AS (
  SELECT
    COUNT(*) AS sample_count,
    SUM(is_janky) AS janky_count,
    MIN(CASE
      WHEN sample_rank >= (95 * sample_total + 99) / 100 THEN dur
    END) AS p95_ns,
    MIN(CASE
      WHEN sample_rank >= (99 * sample_total + 99) / 100 THEN dur
    END) AS p99_ns,
    MAX(dur) AS maximum_ns
  FROM frame_samples
), sched_samples AS (
  SELECT
    MAX(0, MIN(sched.ts + sched.dur, voice_window.window_end)
      - MAX(sched.ts, voice_window.window_start)) AS dur,
    ROW_NUMBER() OVER (
      ORDER BY MAX(0, MIN(sched.ts + sched.dur, voice_window.window_end)
        - MAX(sched.ts, voice_window.window_start))
    ) AS sample_rank,
    COUNT(*) OVER () AS sample_total
  FROM sched
  JOIN thread USING (utid)
  JOIN target_process USING (upid)
  CROSS JOIN voice_window
  WHERE voice_window.window_start IS NOT NULL
    AND sched.ts < voice_window.window_end
    AND sched.ts + sched.dur > voice_window.window_start
), sched_aggregate AS (
  SELECT
    COUNT(*) AS sample_count,
    SUM(dur) AS total_ns,
    MIN(CASE
      WHEN sample_rank >= (95 * sample_total + 99) / 100 THEN dur
    END) AS p95_ns,
    MIN(CASE
      WHEN sample_rank >= (99 * sample_total + 99) / 100 THEN dur
    END) AS p99_ns,
    MAX(dur) AS maximum_ns
  FROM sched_samples
), uid_cpu_samples AS (
  SELECT
    counters.diff_ms,
    counters.cpu_ratio,
    ROW_NUMBER() OVER (ORDER BY counters.cpu_ratio) AS sample_rank,
    COUNT(*) OVER () AS sample_total
  FROM android_cpu_per_uid_track AS tracks
  JOIN android_cpu_per_uid_counter AS counters
    ON counters.track_id = tracks.id
  CROSS JOIN voice_window
  WHERE tracks.uid = @TARGET_UID@
    AND voice_window.window_start IS NOT NULL
    AND counters.ts BETWEEN voice_window.window_start AND voice_window.window_end
), uid_cpu_aggregate AS (
  SELECT
    COUNT(*) AS sample_count,
    SUM(diff_ms) AS total_ms,
    AVG(cpu_ratio) AS average_ratio,
    MIN(CASE
      WHEN sample_rank >= (95 * sample_total + 99) / 100 THEN cpu_ratio
    END) AS p95_ratio,
    MIN(CASE
      WHEN sample_rank >= (99 * sample_total + 99) / 100 THEN cpu_ratio
    END) AS p99_ratio,
    MAX(cpu_ratio) AS maximum_ratio
  FROM uid_cpu_samples
), memory_catalog(metric, track_name) AS (
  VALUES ('rss', 'mem.rss'), ('pss', 'mem.pss'), ('swap', 'mem.swap')
), memory_samples AS (
  SELECT
    catalog.metric,
    counters.ts,
    counters.value,
    ROW_NUMBER() OVER (
      PARTITION BY catalog.metric
      ORDER BY counters.value
    ) AS value_rank,
    ROW_NUMBER() OVER (
      PARTITION BY catalog.metric
      ORDER BY counters.ts DESC
    ) AS newest_first,
    COUNT(*) OVER (PARTITION BY catalog.metric) AS sample_total
  FROM memory_catalog AS catalog
  JOIN process_counter_track AS tracks ON tracks.name = catalog.track_name
  JOIN target_process USING (upid)
  JOIN counter AS counters ON counters.track_id = tracks.id
  CROSS JOIN voice_window
  WHERE voice_window.window_start IS NOT NULL
    AND counters.ts BETWEEN voice_window.window_start AND voice_window.window_end
), memory_aggregate AS (
  SELECT
    catalog.metric,
    COUNT(samples.value) AS sample_count,
    MAX(CASE WHEN samples.newest_first = 1 THEN samples.value END) AS final_value,
    MIN(CASE
      WHEN samples.value_rank >= (95 * samples.sample_total + 99) / 100
      THEN samples.value
    END) AS p95_value,
    MIN(CASE
      WHEN samples.value_rank >= (99 * samples.sample_total + 99) / 100
      THEN samples.value
    END) AS p99_value,
    MAX(samples.value) AS maximum_value
  FROM memory_catalog AS catalog
  LEFT JOIN memory_samples AS samples USING (metric)
  GROUP BY catalog.metric
), power_samples AS (
  SELECT
    tracks.id AS track_id,
    tracks.name AS metric,
    CASE
      WHEN tracks.type = 'power_rails' THEN 'power_rails'
      WHEN tracks.name GLOB 'batt.*' THEN 'battery'
      ELSE 'sysfs_power'
    END AS family,
    counters.ts,
    counters.value,
    ROW_NUMBER() OVER (
      PARTITION BY tracks.id
      ORDER BY counters.value
    ) AS value_rank,
    ROW_NUMBER() OVER (
      PARTITION BY tracks.id
      ORDER BY counters.ts DESC
    ) AS newest_first,
    COUNT(*) OVER (PARTITION BY tracks.id) AS sample_total,
    FIRST_VALUE(counters.value) OVER (
      PARTITION BY tracks.id
      ORDER BY counters.ts
    ) AS first_value
  FROM counter_track AS tracks
  JOIN counter AS counters ON counters.track_id = tracks.id
  CROSS JOIN voice_window
  WHERE voice_window.window_start IS NOT NULL
    AND counters.ts BETWEEN voice_window.window_start AND voice_window.window_end
    AND (
      tracks.type = 'power_rails'
      OR tracks.name GLOB 'batt.*'
      OR tracks.name GLOB 'power.*'
    )
), power_aggregate AS (
  SELECT
    family,
    metric,
    COUNT(*) AS sample_count,
    MAX(CASE WHEN newest_first = 1 THEN value - first_value END) AS delta_value,
    MIN(CASE
      WHEN value_rank >= (95 * sample_total + 99) / 100 THEN value
    END) AS p95_value,
    MIN(CASE
      WHEN value_rank >= (99 * sample_total + 99) / 100 THEN value
    END) AS p99_value,
    MAX(value) AS maximum_value
  FROM power_samples
  GROUP BY track_id, family, metric
), power_catalog(family) AS (
  VALUES ('battery'), ('power_rails'), ('sysfs_power')
), power_availability AS (
  SELECT
    catalog.family,
    COUNT(samples.value) AS sample_count
  FROM power_catalog AS catalog
  LEFT JOIN power_samples AS samples USING (family)
  GROUP BY catalog.family
), app_wakelock_samples AS (
  SELECT
    MAX(0, MIN(slices.ts + MAX(slices.dur, 0), voice_window.window_end)
      - MAX(slices.ts, voice_window.window_start)) AS overlap_ns
  FROM slice AS slices
  JOIN track AS tracks ON tracks.id = slices.track_id
  CROSS JOIN voice_window
  WHERE tracks.name = 'app_wakelock_events'
    AND voice_window.window_start IS NOT NULL
    AND slices.ts < voice_window.window_end
    AND slices.ts + MAX(slices.dur, 0) > voice_window.window_start
    AND (
      CAST(EXTRACT_ARG(slices.arg_set_id, 'owner_pid') AS INTEGER) = @TARGET_PID@
      OR CAST(EXTRACT_ARG(slices.arg_set_id, 'owner_uid') AS INTEGER) = @TARGET_UID@
      OR CAST(EXTRACT_ARG(slices.arg_set_id, 'work_uid') AS INTEGER) = @TARGET_UID@
    )
), kernel_wakelock_samples AS (
  SELECT
    MAX(0, MIN(kernel.ts + kernel.dur, voice_window.window_end)
      - MAX(kernel.ts, voice_window.window_start)) AS overlap_ns
  FROM android_kernel_wakelocks AS kernel
  CROSS JOIN voice_window
  WHERE voice_window.window_start IS NOT NULL
    AND kernel.ts < voice_window.window_end
    AND kernel.ts + kernel.dur > voice_window.window_start
), app_wakelock_aggregate AS (
  SELECT COUNT(*) AS sample_count, SUM(overlap_ns) AS total_ns,
         MAX(overlap_ns) AS maximum_ns
  FROM app_wakelock_samples
), kernel_wakelock_aggregate AS (
  SELECT COUNT(*) AS sample_count, SUM(overlap_ns) AS total_ns,
         MAX(overlap_ns) AS maximum_ns
  FROM kernel_wakelock_samples
), metric_rows AS (
  SELECT
    'frame' AS metric_group,
    'frametimeline' AS metric,
    'pid/package direct' AS attribution,
    sample_count,
    CASE WHEN sample_count > 0 THEN 1 ELSE 0 END AS available,
    CASE WHEN sample_count > 0 THEN janky_count ELSE NULL END AS value,
    CASE WHEN sample_count > 0 THEN 100.0 * janky_count / sample_count ELSE NULL END AS secondary_value,
    p95_ns / 1000000.0 AS p95,
    p99_ns / 1000000.0 AS p99,
    maximum_ns / 1000000.0 AS maximum,
    'frames;janky_percent;p95/p99/max ms' AS unit
  FROM frame_aggregate
  UNION ALL
  SELECT
    'cpu', 'sched', 'exact pid threads', sample_count,
    CASE WHEN sample_count > 0 THEN 1 ELSE 0 END,
    CASE WHEN sample_count > 0 THEN total_ns / 1000000.0 ELSE NULL END,
    CASE
      WHEN sample_count > 0
       AND (SELECT window_end - window_start FROM voice_window) > 0
      THEN 100.0 * total_ns /
        (SELECT window_end - window_start FROM voice_window)
      ELSE NULL
    END,
    p95_ns / 1000000.0, p99_ns / 1000000.0,
    maximum_ns / 1000000.0,
    'total ms;mean one-core percent;p95/p99/max slice ms'
  FROM sched_aggregate
  UNION ALL
  SELECT
    'cpu', 'uid_counter', 'exact package uid; may include shared-uid work',
    sample_count, CASE WHEN sample_count > 0 THEN 1 ELSE 0 END,
    CASE WHEN sample_count > 0 THEN total_ms ELSE NULL END,
    average_ratio, p95_ratio, p99_ratio, maximum_ratio,
    'total ms;mean/p95/p99/max core ratio'
  FROM uid_cpu_aggregate
  UNION ALL
  SELECT
    'memory', metric, 'exact pid process counters', sample_count,
    CASE WHEN sample_count > 0 THEN 1 ELSE 0 END,
    final_value, NULL, p95_value, p99_value, maximum_value,
    'Perfetto process-counter native unit'
  FROM memory_aggregate
  UNION ALL
  SELECT
    'power_availability', family,
    'device-global voice-window context; not app attribution',
    sample_count, CASE WHEN sample_count > 0 THEN 1 ELSE 0 END,
    NULL, NULL, NULL, NULL, NULL, 'availability only'
  FROM power_availability
  UNION ALL
  SELECT
    'power', metric, 'device-global voice-window context; not app attribution',
    sample_count, CASE WHEN sample_count > 0 THEN 1 ELSE 0 END,
    delta_value, NULL, p95_value, p99_value, maximum_value,
    'Perfetto counter native unit'
  FROM power_aggregate
  UNION ALL
  SELECT
    'wakelock', 'app', 'owner pid/uid or work uid direct', sample_count,
    CASE WHEN sample_count > 0 THEN 1 ELSE 0 END,
    CASE WHEN sample_count > 0 THEN total_ns / 1000000.0 ELSE NULL END,
    NULL, NULL, NULL, maximum_ns / 1000000.0, 'total/max overlap ms'
  FROM app_wakelock_aggregate
  UNION ALL
  SELECT
    'wakelock', 'kernel', 'device-global voice-window context; not app attribution',
    sample_count, CASE WHEN sample_count > 0 THEN 1 ELSE 0 END,
    CASE WHEN sample_count > 0 THEN total_ns / 1000000.0 ELSE NULL END,
    NULL, NULL, NULL, maximum_ns / 1000000.0, 'total/max overlap ms'
  FROM kernel_wakelock_aggregate
)
SELECT
  '@PACKAGE@' AS package,
  @TARGET_UID@ AS uid,
  @TARGET_PID@ AS pid,
  '@ROUTE@' AS route,
  '@SCENARIO@' AS scenario,
  metric_group,
  metric,
  attribution,
  sample_count,
  available,
  ROUND(value, 6) AS value,
  ROUND(secondary_value, 6) AS secondary_value,
  ROUND(p95, 6) AS p95,
  ROUND(p99, 6) AS p99,
  ROUND(maximum, 6) AS maximum,
  unit,
  (SELECT COUNT(*) FROM target_process) AS target_process_count,
  CASE WHEN (SELECT window_start FROM voice_window) IS NOT NULL THEN 1 ELSE 0 END
    AS voice_window_available
FROM metric_rows
ORDER BY metric_group, metric;
