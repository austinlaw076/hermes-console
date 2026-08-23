import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_android/core/services/voice/tts_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_tts');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    resetSystemTtsDiscoveryForTesting();
  });

  test('elige el motor instalado cuando no hay predeterminado', () {
    expect(
      selectSystemTtsEngine(const ['app.grapheneos.speechservices'], null),
      'app.grapheneos.speechservices',
    );
  });

  test('descubre y cachea un motor TTS disponible', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'getEngines' => ['app.grapheneos.speechservices'],
            'getDefaultEngine' => null,
            'getLanguages' => ['es-ES'],
            'setEngine' ||
            'setLanguage' ||
            'awaitSpeakCompletion' ||
            'stop' ||
            'speak' => 1,
            _ => null,
          };
        });

    final engine = await systemTtsEngine();
    final cached = await systemTtsEngine();

    expect(engine, 'app.grapheneos.speechservices');
    expect(cached, engine);
    expect(calls.where((call) => call.method == 'getEngines'), hasLength(1));
  });

  test(
    'una ausencia inicial no impide descubrir un motor instalado después',
    () async {
      var discoveries = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            return switch (call.method) {
              'getEngines' =>
                ++discoveries == 1
                    ? <String>[]
                    : ['app.grapheneos.speechservices'],
              'getDefaultEngine' => null,
              _ => null,
            };
          });

      expect(await systemTtsEngine(), isNull);
      expect(await systemTtsEngine(), 'app.grapheneos.speechservices');
      expect(discoveries, 2);
    },
  );
}
