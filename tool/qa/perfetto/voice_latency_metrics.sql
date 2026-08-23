INCLUDE PERFETTO MODULE slices.with_context;

WITH target_process AS (
  SELECT upid, pid, uid, android_appid, name
  FROM process
  WHERE pid = @TARGET_PID@
    AND uid = @TARGET_UID@
    AND android_appid = @TARGET_APP_ID@
    AND (name GLOB '@PACKAGE@*' OR cmdline GLOB '@PACKAGE@*')
), point_catalog(point, scenario_family, sort_order) AS (
  VALUES
    ('turn_started', 'all', 10),
    ('speech_last_above_threshold', 'normal_barge', 20),
    ('speech_endpoint', 'normal_barge', 30),
    ('speech_endpoint_unavailable', 'normal_barge', 31),
    ('stt_started', 'normal_barge', 40),
    ('stt_final', 'normal_barge', 50),
    ('client_optimistic', 'normal_barge', 55),
    ('submit_started', 'normal_barge', 60),
    ('submit_accepted', 'normal_barge', 70),
    ('backend_accepted', 'normal_barge', 80),
    ('backend_lifecycle_ack', 'normal_barge', 81),
    ('first_accepted_text', 'normal_barge', 90),
    ('backend_text_accepted', 'normal_barge', 91),
    ('first_raw_speech_suffix', 'normal_barge', 100),
    ('first_synthesizable_chunk_unavailable', 'normal_barge', 110),
    ('tts_first_feed', 'normal_barge', 120),
    ('pcm_first_received', 'normal_barge', 130),
    ('pcm_first_accepted', 'normal_barge', 140),
    ('pcm_audible_unavailable', 'normal_barge', 150),
    ('stop_requested', 'stop', 200),
    ('audio_stopped', 'stop_exit', 210),
    ('exit', 'exit', 220),
    ('mic_released', 'exit', 230),
    ('lease_released', 'exit', 240),
    ('lease_release_unavailable', 'exit', 241),
    ('turn_finished', 'all', 300)
), applicable_points AS (
  SELECT point, sort_order
  FROM point_catalog
  WHERE scenario_family = 'all'
    OR (scenario_family = 'normal_barge' AND '@SCENARIO@' IN ('normal', 'barge_in'))
    OR (scenario_family = 'stop' AND '@SCENARIO@' = 'stop')
    OR (scenario_family = 'exit' AND '@SCENARIO@' = 'exit')
    OR (scenario_family = 'stop_exit' AND '@SCENARIO@' IN ('stop', 'exit'))
), parsed_events AS (
  SELECT
    scoped.id,
    scoped.ts,
    COALESCE(
      EXTRACT_ARG(scoped.arg_set_id, 'run_id'),
      EXTRACT_ARG(scoped.arg_set_id, 'debug.run_id')
    ) AS run_id,
    CAST(COALESCE(
      EXTRACT_ARG(scoped.arg_set_id, 'turn'),
      EXTRACT_ARG(scoped.arg_set_id, 'debug.turn')
    ) AS INTEGER) AS turn_number,
    COALESCE(
      EXTRACT_ARG(scoped.arg_set_id, 'route'),
      EXTRACT_ARG(scoped.arg_set_id, 'debug.route')
    ) AS route,
    COALESCE(
      EXTRACT_ARG(scoped.arg_set_id, 'scenario'),
      EXTRACT_ARG(scoped.arg_set_id, 'debug.scenario')
    ) AS scenario,
    COALESCE(
      EXTRACT_ARG(scoped.arg_set_id, 'point'),
      EXTRACT_ARG(scoped.arg_set_id, 'debug.point'),
      REPLACE(scoped.name, 'hermes.voice.', '')
    ) AS point,
    CAST(COALESCE(
      EXTRACT_ARG(scoped.arg_set_id, 'elapsed_us'),
      EXTRACT_ARG(scoped.arg_set_id, 'debug.elapsed_us')
    ) AS INTEGER) AS elapsed_us,
    COALESCE(
      EXTRACT_ARG(scoped.arg_set_id, 'stt_topology'),
      EXTRACT_ARG(scoped.arg_set_id, 'debug.stt_topology')
    ) AS stt_topology,
    COALESCE(
      EXTRACT_ARG(scoped.arg_set_id, 'last_above'),
      EXTRACT_ARG(scoped.arg_set_id, 'debug.last_above')
    ) AS last_above,
    CAST(COALESCE(
      EXTRACT_ARG(scoped.arg_set_id, 'count'),
      EXTRACT_ARG(scoped.arg_set_id, 'debug.count')
    ) AS INTEGER) AS summary_count,
    CAST(COALESCE(
      EXTRACT_ARG(scoped.arg_set_id, 'dropped'),
      EXTRACT_ARG(scoped.arg_set_id, 'debug.dropped')
    ) AS INTEGER) AS summary_dropped,
    CAST(COALESCE(
      EXTRACT_ARG(scoped.arg_set_id, 'p50_us'),
      EXTRACT_ARG(scoped.arg_set_id, 'debug.p50_us')
    ) AS INTEGER) AS summary_p50_us,
    CAST(COALESCE(
      EXTRACT_ARG(scoped.arg_set_id, 'p95_us'),
      EXTRACT_ARG(scoped.arg_set_id, 'debug.p95_us')
    ) AS INTEGER) AS summary_p95_us,
    CAST(COALESCE(
      EXTRACT_ARG(scoped.arg_set_id, 'p99_us'),
      EXTRACT_ARG(scoped.arg_set_id, 'debug.p99_us')
    ) AS INTEGER) AS summary_p99_us,
    CAST(COALESCE(
      EXTRACT_ARG(scoped.arg_set_id, 'max_us'),
      EXTRACT_ARG(scoped.arg_set_id, 'debug.max_us')
    ) AS INTEGER) AS summary_max_us
  FROM thread_or_process_slice AS scoped
  JOIN target_process USING (upid)
  WHERE scoped.name GLOB 'hermes.voice.*'
    AND scoped.name != 'hermes.voice.turn'
), scoped_events AS (
  SELECT
    *,
    COALESCE(stt_topology, '__unavailable__') AS stt_dimension,
    COALESCE(last_above, '__unavailable__') AS last_above_dimension
  FROM parsed_events
  WHERE route = '@ROUTE@'
    AND scenario = '@SCENARIO@'
    AND elapsed_us IS NOT NULL
), dimensions AS (
  SELECT DISTINCT stt_dimension, last_above_dimension
  FROM scoped_events
  UNION ALL
  SELECT '__unavailable__', '__unavailable__'
  WHERE NOT EXISTS (SELECT 1 FROM scoped_events)
), point_samples AS (
  SELECT
    events.*,
    ROW_NUMBER() OVER (
      PARTITION BY events.stt_dimension, events.last_above_dimension, events.point
      ORDER BY events.elapsed_us
    ) AS sample_rank,
    COUNT(*) OVER (
      PARTITION BY events.stt_dimension, events.last_above_dimension, events.point
    ) AS sample_total
  FROM scoped_events AS events
  JOIN applicable_points USING (point)
), point_aggregates AS (
  SELECT
    stt_dimension,
    last_above_dimension,
    point,
    COUNT(*) AS sample_count,
    COUNT(DISTINCT run_id || ':' || CAST(turn_number AS TEXT)) AS turn_count,
    MIN(elapsed_us) AS minimum_us,
    MIN(CASE
      WHEN sample_rank >= (50 * sample_total + 99) / 100 THEN elapsed_us
    END) AS p50_us,
    MIN(CASE
      WHEN sample_rank >= (95 * sample_total + 99) / 100 THEN elapsed_us
    END) AS p95_us,
    MIN(CASE
      WHEN sample_rank >= (99 * sample_total + 99) / 100 THEN elapsed_us
    END) AS p99_us,
    MAX(elapsed_us) AS maximum_us
  FROM point_samples
  GROUP BY stt_dimension, last_above_dimension, point
), point_rows AS (
  SELECT
    1 AS group_order,
    applicable.sort_order,
    'point_elapsed' AS metric_kind,
    applicable.point AS metric,
    NULL AS from_point,
    applicable.point AS to_point,
    dimensions.stt_dimension,
    dimensions.last_above_dimension,
    NULL AS run_id,
    NULL AS turn_number,
    COALESCE(aggregates.sample_count, 0) AS sample_count,
    CASE WHEN aggregates.sample_count > 0 THEN 1 ELSE 0 END AS available,
    COALESCE(aggregates.sample_count, 0) AS event_count,
    NULL AS dropped_count,
    aggregates.turn_count,
    aggregates.minimum_us,
    aggregates.p50_us,
    aggregates.p95_us,
    aggregates.p99_us,
    aggregates.maximum_us,
    'offline_percentiles_from_point_events' AS source
  FROM dimensions
  CROSS JOIN applicable_points AS applicable
  LEFT JOIN point_aggregates AS aggregates
    ON aggregates.point = applicable.point
   AND aggregates.stt_dimension = dimensions.stt_dimension
   AND aggregates.last_above_dimension = dimensions.last_above_dimension
), segment_catalog(
  metric, from_point, to_point, scenario_family, sort_order
) AS (
  VALUES
    ('speech_last_above_to_endpoint', 'speech_last_above_threshold', 'speech_endpoint', 'normal_barge', 10),
    ('endpoint_to_stt_started', 'speech_endpoint', 'stt_started', 'normal_barge', 20),
    ('stt_started_to_endpoint', 'stt_started', 'speech_endpoint', 'normal_barge', 21),
    ('endpoint_to_stt_final', 'speech_endpoint', 'stt_final', 'normal_barge', 30),
    ('stt_started_to_stt_final', 'stt_started', 'stt_final', 'normal_barge', 40),
    ('stt_final_to_submit_started', 'stt_final', 'submit_started', 'normal_barge', 50),
    ('client_optimistic_to_backend_accepted', 'client_optimistic', 'backend_accepted', 'normal_barge', 60),
    ('submit_started_to_submit_accepted', 'submit_started', 'submit_accepted', 'normal_barge', 70),
    ('submit_accepted_to_backend_accepted', 'submit_accepted', 'backend_accepted', 'normal_barge', 80),
    ('submit_accepted_to_backend_lifecycle_ack', 'submit_accepted', 'backend_lifecycle_ack', 'normal_barge', 81),
    ('backend_accepted_to_first_accepted_text', 'backend_accepted', 'first_accepted_text', 'normal_barge', 90),
    ('backend_lifecycle_ack_to_backend_text_accepted', 'backend_lifecycle_ack', 'backend_text_accepted', 'normal_barge', 91),
    ('first_accepted_text_to_first_raw_speech_suffix', 'first_accepted_text', 'first_raw_speech_suffix', 'normal_barge', 100),
    ('backend_text_accepted_to_first_raw_speech_suffix', 'backend_text_accepted', 'first_raw_speech_suffix', 'normal_barge', 101),
    ('first_raw_speech_suffix_to_tts_first_feed', 'first_raw_speech_suffix', 'tts_first_feed', 'normal_barge', 110),
    ('tts_first_feed_to_pcm_first_received', 'tts_first_feed', 'pcm_first_received', 'normal_barge', 120),
    ('pcm_first_received_to_pcm_first_accepted', 'pcm_first_received', 'pcm_first_accepted', 'normal_barge', 130),
    ('stop_requested_to_audio_stopped', 'stop_requested', 'audio_stopped', 'stop', 200),
    ('exit_to_audio_stopped', 'exit', 'audio_stopped', 'exit', 210),
    ('exit_to_mic_released', 'exit', 'mic_released', 'exit', 220),
    ('exit_to_lease_released', 'exit', 'lease_released', 'exit', 230)
), applicable_segments AS (
  SELECT metric, from_point, to_point, sort_order
  FROM segment_catalog
  WHERE (scenario_family = 'normal_barge' AND '@SCENARIO@' IN ('normal', 'barge_in'))
     OR (scenario_family = 'stop' AND '@SCENARIO@' = 'stop')
     OR (scenario_family = 'exit' AND '@SCENARIO@' = 'exit')
), segment_samples_unranked AS (
  SELECT
    segments.metric,
    segments.from_point,
    segments.to_point,
    COALESCE(finish.stt_dimension, start.stt_dimension) AS stt_dimension,
    COALESCE(finish.last_above_dimension, start.last_above_dimension)
      AS last_above_dimension,
    start.run_id,
    start.turn_number,
    finish.elapsed_us - start.elapsed_us AS latency_us
  FROM applicable_segments AS segments
  JOIN scoped_events AS start ON start.point = segments.from_point
  JOIN scoped_events AS finish
    ON finish.point = segments.to_point
   AND finish.run_id = start.run_id
   AND finish.turn_number = start.turn_number
  WHERE finish.elapsed_us >= start.elapsed_us
), segment_samples AS (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY stt_dimension, last_above_dimension, metric
      ORDER BY latency_us
    ) AS sample_rank,
    COUNT(*) OVER (
      PARTITION BY stt_dimension, last_above_dimension, metric
    ) AS sample_total
  FROM segment_samples_unranked
), segment_aggregates AS (
  SELECT
    stt_dimension,
    last_above_dimension,
    metric,
    COUNT(*) AS sample_count,
    COUNT(DISTINCT run_id || ':' || CAST(turn_number AS TEXT)) AS turn_count,
    MIN(latency_us) AS minimum_us,
    MIN(CASE
      WHEN sample_rank >= (50 * sample_total + 99) / 100 THEN latency_us
    END) AS p50_us,
    MIN(CASE
      WHEN sample_rank >= (95 * sample_total + 99) / 100 THEN latency_us
    END) AS p95_us,
    MIN(CASE
      WHEN sample_rank >= (99 * sample_total + 99) / 100 THEN latency_us
    END) AS p99_us,
    MAX(latency_us) AS maximum_us
  FROM segment_samples
  GROUP BY stt_dimension, last_above_dimension, metric
), segment_rows AS (
  SELECT
    2 AS group_order,
    segments.sort_order,
    'segment_latency' AS metric_kind,
    segments.metric,
    segments.from_point,
    segments.to_point,
    dimensions.stt_dimension,
    dimensions.last_above_dimension,
    NULL AS run_id,
    NULL AS turn_number,
    COALESCE(aggregates.sample_count, 0) AS sample_count,
    CASE WHEN aggregates.sample_count > 0 THEN 1 ELSE 0 END AS available,
    COALESCE(aggregates.sample_count, 0) AS event_count,
    NULL AS dropped_count,
    aggregates.turn_count,
    aggregates.minimum_us,
    aggregates.p50_us,
    aggregates.p95_us,
    aggregates.p99_us,
    aggregates.maximum_us,
    'offline_percentiles_from_causal_pairs' AS source
  FROM dimensions
  CROSS JOIN applicable_segments AS segments
  LEFT JOIN segment_aggregates AS aggregates
    ON aggregates.metric = segments.metric
   AND aggregates.stt_dimension = dimensions.stt_dimension
   AND aggregates.last_above_dimension = dimensions.last_above_dimension
), histogram_catalog(point, sort_order) AS (
  VALUES ('suffix_append_latency', 10), ('pcm_accept_latency', 20)
), observed_histogram_rows AS (
  SELECT
    3 AS group_order,
    catalog.sort_order,
    'bounded_histogram' AS metric_kind,
    catalog.point AS metric,
    NULL AS from_point,
    NULL AS to_point,
    events.stt_dimension,
    events.last_above_dimension,
    events.run_id,
    events.turn_number,
    CASE WHEN events.summary_count >= 0 THEN events.summary_count ELSE 0 END
      AS sample_count,
    CASE
      WHEN events.summary_count > 0
       AND events.summary_p50_us IS NOT NULL
       AND events.summary_p95_us IS NOT NULL
       AND events.summary_p99_us IS NOT NULL
       AND events.summary_max_us IS NOT NULL THEN 1
      ELSE 0
    END AS available,
    1 AS event_count,
    events.summary_dropped AS dropped_count,
    1 AS turn_count,
    NULL AS minimum_us,
    events.summary_p50_us AS p50_us,
    events.summary_p95_us AS p95_us,
    events.summary_p99_us AS p99_us,
    events.summary_max_us AS maximum_us,
    'client_bounded_turn_summary' AS source
  FROM histogram_catalog AS catalog
  JOIN scoped_events AS events ON events.point = catalog.point
), missing_histogram_rows AS (
  SELECT
    3 AS group_order,
    catalog.sort_order,
    'bounded_histogram' AS metric_kind,
    catalog.point AS metric,
    NULL AS from_point,
    NULL AS to_point,
    dimensions.stt_dimension,
    dimensions.last_above_dimension,
    NULL AS run_id,
    NULL AS turn_number,
    0 AS sample_count,
    0 AS available,
    0 AS event_count,
    NULL AS dropped_count,
    NULL AS turn_count,
    NULL AS minimum_us,
    NULL AS p50_us,
    NULL AS p95_us,
    NULL AS p99_us,
    NULL AS maximum_us,
    'client_bounded_turn_summary' AS source
  FROM dimensions
  CROSS JOIN histogram_catalog AS catalog
  WHERE NOT EXISTS (
    SELECT 1
    FROM scoped_events AS events
    WHERE events.point = catalog.point
      AND events.stt_dimension = dimensions.stt_dimension
      AND events.last_above_dimension = dimensions.last_above_dimension
  )
), metric_rows AS (
  SELECT * FROM point_rows
  UNION ALL
  SELECT * FROM segment_rows
  UNION ALL
  SELECT * FROM observed_histogram_rows
  UNION ALL
  SELECT * FROM missing_histogram_rows
)
SELECT
  '@PACKAGE@' AS package,
  @TARGET_UID@ AS uid,
  @TARGET_PID@ AS pid,
  '@ROUTE@' AS route,
  '@SCENARIO@' AS scenario,
  metric_kind,
  metric,
  from_point,
  to_point,
  CASE
    WHEN stt_dimension = '__unavailable__' THEN NULL
    ELSE stt_dimension
  END AS stt_topology,
  CASE WHEN stt_dimension = '__unavailable__' THEN 0 ELSE 1 END
    AS stt_topology_available,
  CASE
    WHEN last_above_dimension = '__unavailable__' THEN NULL
    ELSE last_above_dimension
  END AS last_above,
  CASE WHEN last_above_dimension = '__unavailable__' THEN 0 ELSE 1 END
    AS last_above_available,
  run_id,
  turn_number,
  sample_count,
  available,
  event_count,
  dropped_count,
  turn_count,
  ROUND(minimum_us / 1000.0, 3) AS minimum_ms,
  ROUND(p50_us / 1000.0, 3) AS p50_ms,
  ROUND(p95_us / 1000.0, 3) AS p95_ms,
  ROUND(p99_us / 1000.0, 3) AS p99_ms,
  ROUND(maximum_us / 1000.0, 3) AS maximum_ms,
  source,
  (SELECT COUNT(*) FROM target_process) AS target_process_count
FROM metric_rows
ORDER BY group_order, sort_order, stt_dimension, last_above_dimension,
         run_id, turn_number;
