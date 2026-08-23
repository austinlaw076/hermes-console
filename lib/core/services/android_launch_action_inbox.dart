import 'dart:async';

import 'package:flutter/services.dart';

import '../models/new_session_launch_action.dart';

/// One-shot bridge for cold-start and warm-start Android launch actions.
class AndroidLaunchActionInbox {
  static const channelName = 'hermes/new_session_launch';

  final MethodChannel _channel;
  final StreamController<NewSessionLaunchAction> _events =
      StreamController<NewSessionLaunchAction>.broadcast();
  bool _initialized = false;

  AndroidLaunchActionInbox({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  Stream<NewSessionLaunchAction> get events => _events.stream;

  Future<NewSessionLaunchAction?> initialize() async {
    if (_initialized) return null;
    _initialized = true;
    _channel.setMethodCallHandler(_handleNativeCall);
    final raw = await _channel.invokeMethod<Object?>('takePendingLaunchAction');
    return NewSessionLaunchAction.tryParse(raw);
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method != 'launchActionReceived') return;
    final action = NewSessionLaunchAction.tryParse(call.arguments);
    if (action != null && !_events.isClosed) _events.add(action);
  }

  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    await _events.close();
  }
}
