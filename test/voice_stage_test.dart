import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:hermes_android/core/widgets/hermes_bot_face.dart';
import 'package:hermes_android/core/widgets/voice_stage.dart';

const _labels = VoiceStageLabels(
  finishListening: 'Terminar escucha',
  pause: 'Pausar',
  resume: 'Continuar',
  stopAndTalk: 'Parar y hablar',
  cancel: 'Cancelar',
  retry: 'Reintentar',
  review: 'Ver aprobacion',
  close: 'Cerrar',
);

final _face = HermesBlobatarFaceVisual.tryParse(
  shapeWire: 'blobatar:voice-test:organic',
  profileName: 'voice-test',
)!;

Widget _host(
  VoiceStageState state, {
  bool reducedMotion = false,
  bool tickerEnabled = true,
  ValueNotifier<double>? micLevel,
  VoidCallback? onFinishListening,
  VoidCallback? onPause,
  VoidCallback? onResume,
  VoidCallback? onStopAndTalk,
  VoidCallback? onCancel,
  VoidCallback? onRetry,
  VoidCallback? onReview,
  VoidCallback? onClose,
  String? statusLabel,
}) {
  return MaterialApp(
    theme: AppTheme.fromId('dark'),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: Scaffold(
        body: TickerMode(
          enabled: tickerEnabled,
          child: VoiceStage(
            state: state,
            statusLabel: statusLabel ?? 'Estado ${state.name}',
            labels: _labels,
            faceVisual: _face,
            micLevel: micLevel,
            onFinishListening: onFinishListening,
            onPause: onPause,
            onResume: onResume,
            onStopAndTalk: onStopAndTalk,
            onCancel: onCancel,
            onRetry: onRetry,
            onReview: onReview,
            onClose: onClose,
          ),
        ),
      ),
    ),
  );
}

void main() {
  test('el estado activo hereda el acento semántico del tema', () {
    final theme = AppTheme.fromId('dark').extension<HermesThemeColors>()!;
    expect(
      resolveVoiceAccentColor(VoiceStageState.listening, colors: theme),
      theme.accent,
    );
    expect(
      resolveVoiceAccentColor(VoiceStageState.waiting, colors: theme),
      theme.warning,
    );
    expect(
      resolveVoiceAccentColor(VoiceStageState.error, colors: theme),
      theme.error,
    );
  });

  testWidgets('los nueve estados pintan solo Blobatar, fase y controles', (
    tester,
  ) async {
    for (final state in VoiceStageState.values) {
      await tester.pumpWidget(_host(state, onClose: () {}));
      await tester.pump(const Duration(milliseconds: 17));

      final stage = find.byKey(const ValueKey('voice-stage'));
      final visual = find.byKey(const ValueKey('voice-stage-visual'));
      expect(stage, findsOneWidget);
      expect(visual, findsOneWidget);
      expect(find.byType(HermesBotFace), findsOneWidget);
      expect(find.text('Estado ${state.name}'), findsOneWidget);
      expect(find.text('Detalle interno de ${state.name}'), findsNothing);
      final face = tester.widget<HermesBotFace>(find.byType(HermesBotFace));
      expect(face.visual, same(_face));
      expect(face.animate, isTrue);
      expect(face.motionState, switch (state) {
        VoiceStageState.listening => HermesBotFaceMotionState.listening,
        VoiceStageState.speaking => HermesBotFaceMotionState.speaking,
        VoiceStageState.loading ||
        VoiceStageState.transcribing ||
        VoiceStageState.thinking ||
        VoiceStageState.toolCall => HermesBotFaceMotionState.thinking,
        _ => HermesBotFaceMotionState.idle,
      });

      expect(
        tester.getCenter(visual).dx,
        closeTo(tester.getCenter(stage).dx, 0.5),
      );
    }
  });

  testWidgets('la linea es enfocable sin anuncio automatico', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_host(VoiceStageState.thinking));

    expect(find.text('Estado thinking'), findsOneWidget);
    expect(find.bySemanticsLabel('Estado thinking'), findsOneWidget);
    final node = tester.getSemantics(
      find.byKey(const ValueKey('voice-stage-signal')),
    );
    expect(node.flagsCollection.isLiveRegion, isFalse);
    expect(node.value, isEmpty);
    semantics.dispose();
  });

  testWidgets(
    'comentario público gana sin exponer transcript ni datos técnicos',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          VoiceStageState.toolCall,
          statusLabel: 'Estoy revisando la integración.',
        ),
      );

      expect(find.text('Estoy revisando la integración.'), findsOneWidget);
      expect(find.text('Estado toolCall'), findsNothing);
      expect(find.textContaining('read_file'), findsNothing);
      expect(find.textContaining('/home/private'), findsNothing);
      expect(
        find.bySemanticsLabel('Estoy revisando la integración.'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('read_file')), findsNothing);
      expect(find.bySemanticsLabel(RegExp('/home/private')), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets('escucha reacciona al micro sin cambiar de Blobatar', (
    tester,
  ) async {
    final level = ValueNotifier<double>(0);
    addTearDown(level.dispose);
    await tester.pumpWidget(_host(VoiceStageState.listening, micLevel: level));

    final transform = find
        .ancestor(
          of: find.byType(HermesBotFace),
          matching: find.byType(Transform),
        )
        .first;
    final before = tester.widget<Transform>(transform).transform.clone();
    level.value = 1;
    await tester.pump();
    final after = tester.widget<Transform>(transform).transform;
    expect(after, isNot(before));
    expect(
      tester.widget<HermesBotFace>(find.byType(HermesBotFace)).visual,
      same(_face),
    );
  });

  testWidgets('Reduce Motion ignora la escala reactiva del micro', (
    tester,
  ) async {
    final level = ValueNotifier<double>(1);
    addTearDown(level.dispose);
    await tester.pumpWidget(
      _host(VoiceStageState.listening, reducedMotion: true, micLevel: level),
    );

    final transform = tester.widget<Transform>(
      find
          .ancestor(
            of: find.byType(HermesBotFace),
            matching: find.byType(Transform),
          )
          .first,
    );
    expect(transform.transform.getMaxScaleOnAxis(), 1);
  });

  testWidgets('los controles son iconos con Semantics y objetivo de 48 dp', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var finished = 0;
    var paused = 0;
    var closed = 0;

    await tester.pumpWidget(
      _host(
        VoiceStageState.listening,
        onFinishListening: () => finished += 1,
        onPause: () => paused += 1,
        onClose: () => closed += 1,
      ),
    );

    for (final (key, label) in const [
      ('voice-stage-finish-listening', 'Terminar escucha'),
      ('voice-stage-pause', 'Pausar'),
      ('voice-stage-close', 'Cerrar'),
    ]) {
      final action = find.byKey(ValueKey(key));
      expect(action, findsOneWidget);
      final size = tester.getSize(action);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(find.bySemanticsLabel(label), findsOneWidget);
      expect(find.text(label), findsNothing);
    }

    await tester.tap(
      find.byKey(const ValueKey('voice-stage-finish-listening')),
    );
    await tester.tap(find.byKey(const ValueKey('voice-stage-pause')));
    await tester.tap(find.byKey(const ValueKey('voice-stage-close')));
    expect((finished, paused, closed), (1, 1, 1));
    semantics.dispose();
  });

  testWidgets('cada fase expone solo sus acciones aplicables', (tester) async {
    await tester.pumpWidget(
      _host(
        VoiceStageState.thinking,
        onStopAndTalk: () {},
        onPause: () {},
        onCancel: () {},
      ),
    );
    expect(
      find.byKey(const ValueKey('voice-stage-stop-and-talk')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('voice-stage-pause')), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-stage-cancel')), findsOneWidget);

    await tester.pumpWidget(
      _host(VoiceStageState.waiting, onReview: () {}, onResume: () {}),
    );
    expect(find.byKey(const ValueKey('voice-stage-review')), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-stage-resume')), findsOneWidget);
    await tester.pumpWidget(_host(VoiceStageState.error, onRetry: () {}));
    expect(find.byKey(const ValueKey('voice-stage-retry')), findsOneWidget);
  });

  testWidgets('320 dp conserva Blobatar centrado y controles sin overflow', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 480);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      _host(
        VoiceStageState.speaking,
        statusLabel: List<String>.filled(
          8,
          'Estoy revisando la integración completa',
        ).join(' '),
        onStopAndTalk: () {},
        onPause: () {},
        onCancel: () {},
        onClose: () {},
      ),
    );

    final stage = find.byKey(const ValueKey('voice-stage'));
    final visual = find.byKey(const ValueKey('voice-stage-visual'));
    expect(
      tester.getCenter(visual).dx,
      closeTo(tester.getCenter(stage).dx, 0.5),
    );
    expect(tester.getSize(visual), const Size.square(150));
    expect(tester.takeException(), isNull);
  });
}
