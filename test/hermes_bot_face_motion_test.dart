import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/widgets/hermes_bot_face.dart';

void main() {
  final visual = HermesBlobatarFaceVisual.tryParse(
    shapeWire: 'blobatar:manager:organic',
    profileName: 'manager',
  )!;

  test('idle channels are seeded, deterministic and observable', () {
    const instant = Duration(milliseconds: 1234);
    final first = hermesBlobatarMotionSnapshot('manager', instant);
    final again = hermesBlobatarMotionSnapshot('manager', instant);
    final other = hermesBlobatarMotionSnapshot('designer', instant);

    expect(first.breatheScaleX, again.breatheScaleX);
    expect(first.breatheScaleY, again.breatheScaleY);
    expect(first.bobY, again.bobY);
    expect(first.blinkScaleY, again.blinkScaleY);
    expect(first.eyeOffsetX, again.eyeOffsetX);
    expect(first.eyeOffsetY, again.eyeOffsetY);
    expect(first.headTiltRadians, again.headTiltRadians);
    expect(
      <double>[
        first.breatheScaleX,
        first.breatheScaleY,
        first.bobY,
        first.eyeOffsetX,
        first.eyeOffsetY,
        first.headTiltRadians,
      ],
      isNot(<double>[
        other.breatheScaleX,
        other.breatheScaleY,
        other.bobY,
        other.eyeOffsetX,
        other.eyeOffsetY,
        other.headTiltRadians,
      ]),
    );

    final frames = <HermesBotFaceMotionSnapshot>[
      for (var milliseconds = 0; milliseconds <= 8000; milliseconds += 10)
        hermesBlobatarMotionSnapshot(
          'manager',
          Duration(milliseconds: milliseconds),
        ),
    ];
    expect(
      frames.map((frame) => frame.breatheScaleX).toSet().length,
      greaterThan(20),
    );
    expect(frames.map((frame) => frame.bobY).toSet().length, greaterThan(20));
    expect(
      frames.map((frame) => frame.blinkScaleY).reduce((a, b) => a < b ? a : b),
      lessThan(0.2),
    );
    expect(
      frames.any(
        (frame) => frame.eyeOffsetX.abs() > 0.5 || frame.eyeOffsetY.abs() > 0.5,
      ),
      isTrue,
    );
  });

  test('activity poses change expression without changing visual identity', () {
    const instant = Duration(milliseconds: 1234);
    final idle = hermesBlobatarMotionSnapshot('manager', instant);
    final listening = hermesBlobatarMotionSnapshot(
      'manager',
      instant,
      state: HermesBotFaceMotionState.listening,
    );
    final thinking = hermesBlobatarMotionSnapshot(
      'manager',
      instant,
      state: HermesBotFaceMotionState.thinking,
    );
    final speaking = hermesBlobatarMotionSnapshot(
      'manager',
      instant,
      state: HermesBotFaceMotionState.speaking,
    );

    expect(listening.eyeScaleX, greaterThan(idle.eyeScaleX));
    expect(listening.eyeScaleY, greaterThan(idle.eyeScaleY));
    expect(thinking.eyeOffsetY, lessThan(-0.5));
    expect(thinking.eyeScaleY, lessThan(idle.eyeScaleY));
    expect(thinking.headTiltRadians.abs(), greaterThan(0.02));
    expect(speaking.breatheScaleY, isNot(idle.breatheScaleY));
    expect(speaking.eyeScaleY, lessThanOrEqualTo(1));
    expect(visual.shapeWire, 'blobatar:manager:organic');
    expect(visual.resolvedKind, 'organic');
  });

  test('speaking pulse is continuous and bounded', () {
    final frames = <HermesBotFaceMotionSnapshot>[
      for (var milliseconds = 0; milliseconds <= 1000; milliseconds += 20)
        hermesBlobatarMotionSnapshot(
          'manager',
          Duration(milliseconds: milliseconds),
          state: HermesBotFaceMotionState.speaking,
        ),
    ];

    expect(
      frames.map((frame) => frame.breatheScaleY).toSet().length,
      greaterThan(10),
    );
    expect(
      frames.every(
        (frame) =>
            frame.breatheScaleX >= 1 &&
            frame.breatheScaleX <= 1.014 &&
            frame.breatheScaleY >= 0.98 &&
            frame.breatheScaleY <= 1 &&
            frame.headTiltRadians.abs() <= 0.0091,
      ),
      isTrue,
    );
  });

  testWidgets('motion is opt-in and isolated behind a repaint boundary', (
    tester,
  ) async {
    await tester.pumpWidget(_FaceHarness(visual: visual));

    expect(
      find.byKey(const ValueKey('hermes-bot-face-repaint-boundary')),
      findsOneWidget,
    );
    final staticPainter = _painter(tester);
    expect(staticPainter.motionEnabled, isFalse);
    expect(staticPainter.clock, isA<AlwaysStoppedAnimation<double>>());
    expect(staticPainter.clock.value, 0);
    await tester.pump(const Duration(seconds: 2));
    expect(staticPainter.clock.value, 0);

    await tester.pumpWidget(_FaceHarness(visual: visual, animate: true));
    final movingPainter = _painter(tester);
    final movingStart = movingPainter.clock.value;
    expect(movingPainter.motionEnabled, isTrue);
    expect(movingPainter.clock.isAnimating, isTrue);
    await tester.pump(const Duration(milliseconds: 700));
    expect(movingPainter.clock.value, greaterThan(movingStart));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('activity state updates the painter without restarting motion', (
    tester,
  ) async {
    await tester.pumpWidget(_FaceHarness(visual: visual, animate: true));
    final idlePainter = _painter(tester);
    await tester.pump(const Duration(milliseconds: 240));
    final beforeUpdate = idlePainter.clock.value as double;

    await tester.pumpWidget(
      _FaceHarness(
        visual: visual,
        animate: true,
        motionState: HermesBotFaceMotionState.thinking,
      ),
    );
    final thinkingPainter = _painter(tester);
    expect(thinkingPainter.motionState, HermesBotFaceMotionState.thinking);
    expect(thinkingPainter.clock.value, greaterThanOrEqualTo(beforeUpdate));
    expect(thinkingPainter.clock.isAnimating, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('MediaQuery disableAnimations holds the official static frame', (
    tester,
  ) async {
    await tester.pumpWidget(
      _FaceHarness(visual: visual, animate: true, disableAnimations: true),
    );

    final painter = _painter(tester);
    expect(painter.motionEnabled, isFalse);
    expect(painter.clock, isA<AlwaysStoppedAnimation<double>>());
    await tester.pump(const Duration(seconds: 3));
    expect(painter.clock.value, 0);
  });

  testWidgets('TickerMode false stops motion and restores the static frame', (
    tester,
  ) async {
    await tester.pumpWidget(
      _FaceHarness(visual: visual, animate: true, tickerEnabled: false),
    );

    final painter = _painter(tester);
    expect(painter.motionEnabled, isFalse);
    expect(painter.clock, isA<AlwaysStoppedAnimation<double>>());
    await tester.pump(const Duration(seconds: 3));
    expect(painter.clock.value, 0);
  });
}

class _FaceHarness extends StatelessWidget {
  final HermesBlobatarFaceVisual visual;
  final bool animate;
  final bool disableAnimations;
  final bool tickerEnabled;
  final HermesBotFaceMotionState motionState;

  const _FaceHarness({
    required this.visual,
    this.animate = false,
    this.disableAnimations = false,
    this.tickerEnabled = true,
    this.motionState = HermesBotFaceMotionState.idle,
  });

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: TickerMode(
        enabled: tickerEnabled,
        child: Center(
          child: HermesBotFace(
            visual: visual,
            size: 96,
            animate: animate,
            motionState: motionState,
          ),
        ),
      ),
    ),
  );
}

dynamic _painter(WidgetTester tester) => tester
    .widget<CustomPaint>(
      find.byKey(const ValueKey('hermes-controlled-bot-face')),
    )
    .painter;
