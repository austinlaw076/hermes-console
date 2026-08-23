import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;
import 'dart:math';

const String _voiceLatencyFlavor = String.fromEnvironment(
  'HERMES_FLAVOR',
  defaultValue: 'full',
);
const bool _voiceLatencyRequested = bool.fromEnvironment(
  'HERMES_VOICE_PERF_TRACE',
  defaultValue: false,
);

bool voiceLatencyTraceAllowed({
  required String flavor,
  required bool requested,
}) => flavor == 'qa' && requested;

const bool kVoiceLatencyTraceEnabled =
    _voiceLatencyFlavor == 'qa' && _voiceLatencyRequested;

enum VoiceLatencyRoute { phone, server }

enum VoiceLatencyScenario { normal, bargeIn, stop, exit }

enum VoiceSttTopology { streaming, recordThenTranscribe }

enum VoiceLatencyAvailability { measured, unavailable }

/// Fixed, content-free points accepted by the QA trace.
///
/// There is deliberately no free-form event name or argument map in the public
/// API. A caller cannot attach transcript, session, model, URL, credentials or
/// PCM data to a trace event.
enum VoiceLatencyPoint {
  turnStarted,
  clientOptimistic,
  speechLastAboveThreshold,
  speechEndpoint,
  speechEndpointUnavailable,
  sttStarted,
  sttFinal,
  submitStarted,
  submitAccepted,
  backendAccepted,
  firstAcceptedText,
  backendLifecycleAck,
  backendTextAccepted,
  firstRawSpeechSuffix,
  suffixAppendLatency,
  firstSynthesizableChunkUnavailable,
  ttsFirstFeed,
  pcmFirstReceived,
  pcmFirstAccepted,
  pcmAcceptLatency,
  pcmAudibleUnavailable,
  stopRequested,
  audioStopped,
  exitRequested,
  micReleased,
  leaseReleased,
  leaseReleaseUnavailable,
  turnFinished,
}

typedef VoiceLatencyClock = int Function();
typedef VoiceLatencyObserver = void Function(VoiceLatencyRecord record);

final class VoiceLatencyRecord {
  VoiceLatencyRecord._({
    required this.runId,
    required this.turn,
    required this.route,
    required this.scenario,
    required this.point,
    required this.elapsedMicros,
    required this.sttTopology,
    required this.lastAboveAvailability,
    Map<String, int>? summary,
  }) : arguments = UnmodifiableMapView<String, Object>(<String, Object>{
         'run_id': runId,
         'turn': turn,
         'route': route._traceName,
         'scenario': scenario._traceName,
         'point': point._traceName,
         'elapsed_us': elapsedMicros,
         if (sttTopology != null) 'stt_topology': sttTopology._traceName,
         if (lastAboveAvailability != null)
           'last_above': lastAboveAvailability._traceName,
         ...?summary,
       });

  final String runId;
  final int turn;
  final VoiceLatencyRoute route;
  final VoiceLatencyScenario scenario;
  final VoiceLatencyPoint point;
  final int elapsedMicros;
  final VoiceSttTopology? sttTopology;
  final VoiceLatencyAvailability? lastAboveAvailability;

  /// The complete and immutable Timeline argument allowlist.
  final Map<String, Object> arguments;

  bool get isContent =>
      point == VoiceLatencyPoint.firstAcceptedText ||
      point == VoiceLatencyPoint.backendTextAccepted;

  String get timelineName => 'hermes.voice.${point._traceName}';
}

/// Monotonic QA-only voice latency instrumentation.
///
/// Production construction is compile-time gated by both the `qa` flavor and
/// `HERMES_VOICE_PERF_TRACE=true`. Tests use [VoiceLatencyTrace.testing] with a
/// deterministic clock and observer; neither path writes files or logs.
final class VoiceLatencyTrace {
  VoiceLatencyTrace._({
    required this._enabled,
    required this.runId,
    required this._nowMicros,
    this._onRecord,
    required this._emitTimeline,
    required this.histogramCapacity,
  });

  factory VoiceLatencyTrace.testing({
    required String runId,
    required VoiceLatencyClock nowMicros,
    required VoiceLatencyObserver onRecord,
    int histogramCapacity = defaultHistogramCapacity,
    bool emitTimeline = false,
  }) {
    if (!_opaqueRunId.hasMatch(runId)) {
      throw ArgumentError.value(runId, 'runId', 'Expected 16 lowercase hex');
    }
    return VoiceLatencyTrace._(
      enabled: true,
      runId: runId,
      nowMicros: nowMicros,
      onRecord: onRecord,
      emitTimeline: emitTimeline,
      histogramCapacity: _validatedHistogramCapacity(histogramCapacity),
    );
  }

  static const int defaultHistogramCapacity = 512;
  static const int maxHistogramCapacity = 4096;
  static final VoiceLatencyTrace instance = _production();
  static final Object _zoneKey = Object();
  static final RegExp _opaqueRunId = RegExp(r'^[a-f0-9]{16}$');

  static VoiceLatencyTrace get current =>
      Zone.current[_zoneKey] as VoiceLatencyTrace? ?? instance;

  static VoiceLatencyTrace _production() {
    if (!kVoiceLatencyTraceEnabled) {
      return VoiceLatencyTrace._(
        enabled: false,
        runId: '',
        nowMicros: () => developer.Timeline.now,
        emitTimeline: false,
        histogramCapacity: defaultHistogramCapacity,
      );
    }
    return VoiceLatencyTrace._(
      enabled: true,
      runId: _newOpaqueRunId(),
      nowMicros: () => developer.Timeline.now,
      emitTimeline: true,
      histogramCapacity: defaultHistogramCapacity,
    );
  }

  final bool _enabled;
  final String runId;
  final VoiceLatencyClock _nowMicros;
  final VoiceLatencyObserver? _onRecord;
  final bool _emitTimeline;
  final int histogramCapacity;

  int _nextTurn = 0;
  VoiceLatencyTurn? _activeTurn;

  bool get enabled => _enabled;

  R runScoped<R>(R Function() body) =>
      runZoned<R>(body, zoneValues: <Object, Object>{_zoneKey: this});

  VoiceLatencyTurn? get currentTurn {
    final turn = _activeTurn;
    return turn == null || turn.finished ? null : turn;
  }

  VoiceLatencyTurn beginTurn({
    required VoiceLatencyRoute route,
    required VoiceLatencyScenario scenario,
    VoiceSttTopology? sttTopology,
    VoiceLatencyAvailability? lastAboveAvailability,
  }) {
    if ((sttTopology == null) != (lastAboveAvailability == null)) {
      throw ArgumentError(
        'STT topology and last-above availability must be declared together.',
      );
    }
    if (!_enabled) {
      return VoiceLatencyTurn._disabled(
        route,
        scenario,
        sttTopology,
        lastAboveAvailability,
      );
    }
    _activeTurn?.finish();
    final turn = VoiceLatencyTurn._(
      owner: this,
      turn: ++_nextTurn,
      route: route,
      scenario: scenario,
      sttTopology: sttTopology,
      lastAboveAvailability: lastAboveAvailability,
      startedMicros: _nowMicros(),
      histogramCapacity: histogramCapacity,
    );
    _activeTurn = turn;
    turn._start();
    return turn;
  }

  VoiceLatencyRecord _record(VoiceLatencyTurn turn, VoiceLatencyPoint point) =>
      _recordAt(turn, point, _nowMicros());

  VoiceLatencyRecord _recordAt(
    VoiceLatencyTurn turn,
    VoiceLatencyPoint point,
    int sampled, {
    Map<String, int>? summary,
  }) {
    final eventMicros = sampled < turn._lastMicros ? turn._lastMicros : sampled;
    turn._lastMicros = eventMicros;
    final record = VoiceLatencyRecord._(
      runId: runId,
      turn: turn.turn,
      route: turn.route,
      scenario: turn.scenario,
      point: point,
      elapsedMicros: eventMicros - turn._startedMicros,
      sttTopology: turn.sttTopology,
      lastAboveAvailability: turn.lastAboveAvailability,
      summary: summary,
    );
    _onRecord?.call(record);
    return record;
  }

  static String _newOpaqueRunId() {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var index = 0; index < 8; index++) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  static int _validatedHistogramCapacity(int capacity) {
    if (capacity <= 0 || capacity > maxHistogramCapacity) {
      throw RangeError.range(
        capacity,
        1,
        maxHistogramCapacity,
        'histogramCapacity',
      );
    }
    return capacity;
  }
}

final class VoiceLatencyTurn {
  VoiceLatencyTurn._({
    required this._owner,
    required this.turn,
    required this.route,
    required this.scenario,
    required this.sttTopology,
    required this.lastAboveAvailability,
    required int startedMicros,
    required int histogramCapacity,
  }) : _startedMicros = startedMicros,
       _lastMicros = startedMicros,
       _suffixAppendLatency = _BoundedLatencyHistogram(histogramCapacity),
       _pcmAcceptLatency = _BoundedLatencyHistogram(histogramCapacity),
       _enabled = true;

  VoiceLatencyTurn._disabled(
    this.route,
    this.scenario,
    this.sttTopology,
    this.lastAboveAvailability,
  ) : _owner = null,
      turn = 0,
      _startedMicros = 0,
      _lastMicros = 0,
      _suffixAppendLatency = null,
      _pcmAcceptLatency = null,
      _enabled = false;

  final VoiceLatencyTrace? _owner;
  final bool _enabled;
  final int turn;
  final VoiceLatencyRoute route;
  final VoiceLatencyScenario scenario;
  final VoiceSttTopology? sttTopology;
  final VoiceLatencyAvailability? lastAboveAvailability;
  final int _startedMicros;
  final Set<VoiceLatencyPoint> _emitted = <VoiceLatencyPoint>{};
  final _BoundedLatencyHistogram? _suffixAppendLatency;
  final _BoundedLatencyHistogram? _pcmAcceptLatency;

  int _lastMicros;
  int? _pendingSpeechAboveThresholdMicros;
  developer.TimelineTask? _task;
  bool _finished = false;

  bool get finished => _finished;

  void _start() {
    final owner = _owner;
    if (!_enabled || owner == null) return;
    _emitted.add(VoiceLatencyPoint.turnStarted);
    final record = owner._record(this, VoiceLatencyPoint.turnStarted);
    if (owner._emitTimeline) {
      final task = developer.TimelineTask(filterKey: 'hermes_voice_latency');
      _task = task;
      task.start('hermes.voice.turn', arguments: record.arguments);
      task.instant(record.timelineName, arguments: record.arguments);
    }
  }

  /// Retains the latest voiced sample without emitting one Timeline event per
  /// audio frame. [speechEndpoint] flushes exactly that final sample first.
  bool observeSpeechAboveThreshold() {
    final owner = _owner;
    if (!_enabled ||
        owner == null ||
        _finished ||
        lastAboveAvailability == VoiceLatencyAvailability.unavailable) {
      return false;
    }
    final sampled = owner._nowMicros();
    final bounded = sampled < _startedMicros ? _startedMicros : sampled;
    final previous = _pendingSpeechAboveThresholdMicros;
    if (previous == null || bounded >= previous) {
      _pendingSpeechAboveThresholdMicros = bounded;
    }
    return true;
  }

  VoiceLatencySample beginSuffixAppendLatency() =>
      _beginLatencySample(_LatencyHistogramKind.suffixAppend);

  VoiceLatencySample beginPcmAcceptLatency() =>
      _beginLatencySample(_LatencyHistogramKind.pcmAccept);

  VoiceLatencySample _beginLatencySample(_LatencyHistogramKind kind) {
    final owner = _owner;
    if (!_enabled || owner == null || _finished) {
      return VoiceLatencySample._disabled();
    }
    return VoiceLatencySample._(this, kind, owner._nowMicros());
  }

  bool _acceptLatencySample(_LatencyHistogramKind kind, int startedMicros) {
    final owner = _owner;
    if (!_enabled || owner == null || _finished) return false;
    final endedMicros = owner._nowMicros();
    final latencyMicros = endedMicros <= startedMicros
        ? 0
        : endedMicros - startedMicros;
    switch (kind) {
      case _LatencyHistogramKind.suffixAppend:
        _suffixAppendLatency?.add(latencyMicros);
        break;
      case _LatencyHistogramKind.pcmAccept:
        _pcmAcceptLatency?.add(latencyMicros);
        break;
    }
    return true;
  }

  /// Emits a point once when its typed causal prerequisites are satisfied.
  bool mark(VoiceLatencyPoint point) {
    final owner = _owner;
    if (!_enabled || owner == null || _finished || _emitted.contains(point)) {
      return false;
    }
    if (!_accepts(point)) return false;
    if (point == VoiceLatencyPoint.speechEndpoint) {
      final voicedAt = _pendingSpeechAboveThresholdMicros;
      if (voicedAt != null &&
          !_emitted.contains(VoiceLatencyPoint.speechLastAboveThreshold)) {
        _emitted.add(VoiceLatencyPoint.speechLastAboveThreshold);
        final speech = owner._recordAt(
          this,
          VoiceLatencyPoint.speechLastAboveThreshold,
          voicedAt,
        );
        _task?.instant(speech.timelineName, arguments: speech.arguments);
      }
    }
    _emitted.add(point);
    final record = owner._record(this, point);
    _task?.instant(record.timelineName, arguments: record.arguments);
    return true;
  }

  void finish() {
    final owner = _owner;
    if (!_enabled || owner == null || _finished) return;
    _finished = true;
    _emitHistogramSummary(
      VoiceLatencyPoint.suffixAppendLatency,
      _suffixAppendLatency,
    );
    _emitHistogramSummary(
      VoiceLatencyPoint.pcmAcceptLatency,
      _pcmAcceptLatency,
    );
    _emitted.add(VoiceLatencyPoint.turnFinished);
    final record = owner._record(this, VoiceLatencyPoint.turnFinished);
    _task?.instant(record.timelineName, arguments: record.arguments);
    // TimelineTask.finish injects its filterKey into the supplied map. Records
    // stay immutable for observers/privacy, so give the SDK a mutable copy.
    _task?.finish(arguments: Map<String, Object>.of(record.arguments));
    _task = null;
  }

  void _emitHistogramSummary(
    VoiceLatencyPoint point,
    _BoundedLatencyHistogram? histogram,
  ) {
    final owner = _owner;
    final summary = histogram?.summary;
    if (owner == null || summary == null) return;
    _emitted.add(point);
    final record = owner._recordAt(
      this,
      point,
      owner._nowMicros(),
      summary: summary,
    );
    _task?.instant(record.timelineName, arguments: record.arguments);
  }

  bool _accepts(VoiceLatencyPoint point) {
    if (point == VoiceLatencyPoint.turnStarted ||
        point == VoiceLatencyPoint.turnFinished) {
      return false;
    }
    switch (scenario) {
      case VoiceLatencyScenario.stop:
        if (point == VoiceLatencyPoint.stopRequested) return true;
        return point == VoiceLatencyPoint.audioStopped &&
            _emitted.contains(VoiceLatencyPoint.stopRequested);
      case VoiceLatencyScenario.exit:
        if (point == VoiceLatencyPoint.exitRequested) return true;
        if (!_emitted.contains(VoiceLatencyPoint.exitRequested)) return false;
        if (point == VoiceLatencyPoint.audioStopped) return true;
        if (point == VoiceLatencyPoint.micReleased) return true;
        if (point == VoiceLatencyPoint.leaseReleased ||
            point == VoiceLatencyPoint.leaseReleaseUnavailable) {
          return _emitted.contains(VoiceLatencyPoint.audioStopped) &&
              _emitted.contains(VoiceLatencyPoint.micReleased) &&
              !_emitted.contains(VoiceLatencyPoint.leaseReleased) &&
              !_emitted.contains(VoiceLatencyPoint.leaseReleaseUnavailable);
        }
        return false;
      case VoiceLatencyScenario.normal:
      case VoiceLatencyScenario.bargeIn:
        if (point == VoiceLatencyPoint.stopRequested ||
            point == VoiceLatencyPoint.audioStopped ||
            point == VoiceLatencyPoint.exitRequested ||
            point == VoiceLatencyPoint.micReleased ||
            point == VoiceLatencyPoint.leaseReleased ||
            point == VoiceLatencyPoint.leaseReleaseUnavailable) {
          return false;
        }
        if (point == VoiceLatencyPoint.suffixAppendLatency ||
            point == VoiceLatencyPoint.pcmAcceptLatency) {
          return false;
        }
        if (point == VoiceLatencyPoint.speechLastAboveThreshold) return false;
        if (point == VoiceLatencyPoint.speechEndpoint ||
            point == VoiceLatencyPoint.speechEndpointUnavailable) {
          if (_emitted.contains(VoiceLatencyPoint.speechEndpoint) ||
              _emitted.contains(VoiceLatencyPoint.speechEndpointUnavailable)) {
            return false;
          }
          return sttTopology != VoiceSttTopology.streaming ||
              _emitted.contains(VoiceLatencyPoint.sttStarted);
        }
        if (point == VoiceLatencyPoint.sttStarted) {
          return sttTopology != VoiceSttTopology.recordThenTranscribe ||
              _emitted.contains(VoiceLatencyPoint.speechEndpoint) ||
              _emitted.contains(VoiceLatencyPoint.speechEndpointUnavailable);
        }
        if (point == VoiceLatencyPoint.sttFinal && sttTopology != null) {
          return _emitted.contains(VoiceLatencyPoint.sttStarted) &&
              (_emitted.contains(VoiceLatencyPoint.speechEndpoint) ||
                  _emitted.contains(
                    VoiceLatencyPoint.speechEndpointUnavailable,
                  ));
        }
        if (point == VoiceLatencyPoint.submitAccepted) {
          return _emitted.contains(VoiceLatencyPoint.submitStarted);
        }
        if (point == VoiceLatencyPoint.backendAccepted) {
          return _emitted.contains(VoiceLatencyPoint.submitAccepted);
        }
        if (point == VoiceLatencyPoint.firstAcceptedText) {
          return _emitted.contains(VoiceLatencyPoint.backendAccepted);
        }
        if (point == VoiceLatencyPoint.backendLifecycleAck ||
            point == VoiceLatencyPoint.backendTextAccepted) {
          return _emitted.contains(VoiceLatencyPoint.submitAccepted);
        }
        if (point == VoiceLatencyPoint.firstRawSpeechSuffix) {
          return _emitted.contains(VoiceLatencyPoint.firstAcceptedText) ||
              _emitted.contains(VoiceLatencyPoint.backendTextAccepted);
        }
        if (point == VoiceLatencyPoint.ttsFirstFeed) {
          return _emitted.contains(VoiceLatencyPoint.firstRawSpeechSuffix);
        }
        if (point == VoiceLatencyPoint.pcmFirstReceived) {
          return _emitted.contains(VoiceLatencyPoint.ttsFirstFeed);
        }
        if (point == VoiceLatencyPoint.pcmFirstAccepted) {
          return _emitted.contains(VoiceLatencyPoint.pcmFirstReceived);
        }
        if (point == VoiceLatencyPoint.pcmAudibleUnavailable) {
          return _emitted.contains(VoiceLatencyPoint.pcmFirstAccepted);
        }
        if (point == VoiceLatencyPoint.firstSynthesizableChunkUnavailable) {
          return _emitted.contains(VoiceLatencyPoint.firstRawSpeechSuffix);
        }
        return true;
    }
  }
}

enum _LatencyHistogramKind { suffixAppend, pcmAccept }

final class VoiceLatencySample {
  VoiceLatencySample._(this._turn, this._kind, this._startedMicros);

  VoiceLatencySample._disabled()
    : _turn = null,
      _kind = _LatencyHistogramKind.suffixAppend,
      _startedMicros = 0;

  final VoiceLatencyTurn? _turn;
  final _LatencyHistogramKind _kind;
  final int _startedMicros;
  bool _accepted = false;

  /// Closes this receive->accept pair once. A missing positive boundary leaves
  /// the sample unreported instead of turning cancellation or rejection into 0.
  bool accept() {
    if (_accepted) return false;
    _accepted = true;
    return _turn?._acceptLatencySample(_kind, _startedMicros) ?? false;
  }
}

final class _BoundedLatencyHistogram {
  _BoundedLatencyHistogram(this.capacity);

  final int capacity;
  final List<int> _values = <int>[];
  int _count = 0;
  int _dropped = 0;

  void add(int latencyMicros) {
    _count++;
    if (_values.length >= capacity) {
      _dropped++;
      return;
    }
    _values.add(latencyMicros);
  }

  Map<String, int>? get summary {
    if (_count == 0 || _values.isEmpty) return null;
    final sorted = List<int>.of(_values)..sort();
    int percentile(double quantile) {
      final rank = (quantile * sorted.length)
          .ceil()
          .clamp(1, sorted.length)
          .toInt();
      return sorted[rank - 1];
    }

    return <String, int>{
      'count': _count,
      'dropped': _dropped,
      'p50_us': percentile(0.50),
      'p95_us': percentile(0.95),
      'p99_us': percentile(0.99),
      'max_us': sorted.last,
    };
  }
}

/// Closes an Exit trace only after the foreground owner reconciliation ran.
///
/// The current plugin API does not expose the resulting service-type set, so a
/// caller must pass `releaseConfirmed: false` unless it has an authoritative
/// platform acknowledgement. In that case the trace records unavailable,
/// never a guessed release timestamp.
bool completeVoiceLeaseTrace(
  VoiceLatencyTurn? turn, {
  required bool releaseConfirmed,
}) {
  if (turn == null || turn.scenario != VoiceLatencyScenario.exit) return false;
  final marked = turn.mark(
    releaseConfirmed
        ? VoiceLatencyPoint.leaseReleased
        : VoiceLatencyPoint.leaseReleaseUnavailable,
  );
  if (marked) turn.finish();
  return marked;
}

extension on VoiceLatencyRoute {
  String get _traceName => switch (this) {
    VoiceLatencyRoute.phone => 'phone',
    VoiceLatencyRoute.server => 'server',
  };
}

extension on VoiceLatencyScenario {
  String get _traceName => switch (this) {
    VoiceLatencyScenario.normal => 'normal',
    VoiceLatencyScenario.bargeIn => 'barge_in',
    VoiceLatencyScenario.stop => 'stop',
    VoiceLatencyScenario.exit => 'exit',
  };
}

extension on VoiceSttTopology {
  String get _traceName => switch (this) {
    VoiceSttTopology.streaming => 'streaming',
    VoiceSttTopology.recordThenTranscribe => 'record_then_transcribe',
  };
}

extension on VoiceLatencyAvailability {
  String get _traceName => switch (this) {
    VoiceLatencyAvailability.measured => 'measured',
    VoiceLatencyAvailability.unavailable => 'unavailable',
  };
}

extension on VoiceLatencyPoint {
  String get _traceName => switch (this) {
    VoiceLatencyPoint.turnStarted => 'turn_started',
    VoiceLatencyPoint.clientOptimistic => 'client_optimistic',
    VoiceLatencyPoint.speechLastAboveThreshold => 'speech_last_above_threshold',
    VoiceLatencyPoint.speechEndpoint => 'speech_endpoint',
    VoiceLatencyPoint.speechEndpointUnavailable =>
      'speech_endpoint_unavailable',
    VoiceLatencyPoint.sttStarted => 'stt_started',
    VoiceLatencyPoint.sttFinal => 'stt_final',
    VoiceLatencyPoint.submitStarted => 'submit_started',
    VoiceLatencyPoint.submitAccepted => 'submit_accepted',
    VoiceLatencyPoint.backendAccepted => 'backend_accepted',
    VoiceLatencyPoint.firstAcceptedText => 'first_accepted_text',
    VoiceLatencyPoint.backendLifecycleAck => 'backend_lifecycle_ack',
    VoiceLatencyPoint.backendTextAccepted => 'backend_text_accepted',
    VoiceLatencyPoint.firstRawSpeechSuffix => 'first_raw_speech_suffix',
    VoiceLatencyPoint.suffixAppendLatency => 'suffix_append_latency',
    VoiceLatencyPoint.firstSynthesizableChunkUnavailable =>
      'first_synthesizable_chunk_unavailable',
    VoiceLatencyPoint.ttsFirstFeed => 'tts_first_feed',
    VoiceLatencyPoint.pcmFirstReceived => 'pcm_first_received',
    VoiceLatencyPoint.pcmFirstAccepted => 'pcm_first_accepted',
    VoiceLatencyPoint.pcmAcceptLatency => 'pcm_accept_latency',
    VoiceLatencyPoint.pcmAudibleUnavailable => 'pcm_audible_unavailable',
    VoiceLatencyPoint.stopRequested => 'stop_requested',
    VoiceLatencyPoint.audioStopped => 'audio_stopped',
    VoiceLatencyPoint.exitRequested => 'exit',
    VoiceLatencyPoint.micReleased => 'mic_released',
    VoiceLatencyPoint.leaseReleased => 'lease_released',
    VoiceLatencyPoint.leaseReleaseUnavailable => 'lease_release_unavailable',
    VoiceLatencyPoint.turnFinished => 'turn_finished',
  };
}
