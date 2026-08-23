import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/splash_screen.dart';
import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:hermes_android/core/theme/theme_contrast.dart';
import 'package:hermes_android/core/widgets/animated_hermes_logo.dart';

void main() {
  ColorFilter expectedTint(Color accent) {
    const source = Color(0xFFF0A848);
    final sourceHue = HSVColor.fromColor(source).hue;
    final targetHue = HSVColor.fromColor(accent).hue;
    final angle = (targetHue - sourceHue) * 3.141592653589793 / 180;
    final cosine = math.cos(angle);
    final sine = math.sin(angle);
    return ColorFilter.matrix([
      0.213 + cosine * 0.787 - sine * 0.213,
      0.715 - cosine * 0.715 - sine * 0.715,
      0.072 - cosine * 0.072 + sine * 0.928,
      0,
      0,
      0.213 - cosine * 0.213 + sine * 0.143,
      0.715 + cosine * 0.285 + sine * 0.140,
      0.072 - cosine * 0.072 - sine * 0.283,
      0,
      0,
      0.213 - cosine * 0.213 - sine * 0.787,
      0.715 - cosine * 0.715 + sine * 0.715,
      0.072 + cosine * 0.928 + sine * 0.072,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ]);
  }

  testWidgets('orbit advances while platform animations are enabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.fromId('crimson'),
        home: const Scaffold(
          body: AnimatedHermesLogo(animate: true, orbit: true, glow: false),
        ),
      ),
    );

    final orbitPaint = find.descendant(
      of: find.byType(AnimatedHermesLogo),
      matching: find.byType(CustomPaint),
    );
    final before = tester.widget<CustomPaint>(orbitPaint).painter;
    await tester.pump(const Duration(milliseconds: 240));
    final after = tester.widget<CustomPaint>(orbitPaint).painter;
    expect(after, isNot(same(before)));
  });

  testWidgets('themed logo keeps the transparent canvas transparent', (
    tester,
  ) async {
    const accent = Color(0xFFFF4F91);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.fromId('crimson'),
        home: const Scaffold(
          body: Center(
            child: SizedBox.square(
              dimension: 200,
              child: AnimatedHermesLogo(
                size: 200,
                animate: false,
                orbit: false,
                glow: false,
                color: accent,
              ),
            ),
          ),
        ),
      ),
    );

    final filtered = tester.widget<ColorFiltered>(
      find.byKey(const Key('animated_hermes_logo_tint')),
    );
    expect(filtered.colorFilter, expectedTint(accent));
    expect(
      find.descendant(
        of: find.byKey(const Key('animated_hermes_logo_tint')),
        matching: find.byType(Image),
      ),
      findsOneWidget,
    );
  });

  testWidgets('light theme uses the opaque dimensional cutout once', (
    tester,
  ) async {
    final theme = AppTheme.fromId('claude-light');
    final colors = theme.hermes;

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: AnimatedHermesLogo(
            animate: false,
            glow: false,
            color: colors.accent,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const Key('animated_hermes_logo_light_artwork')),
      findsOneWidget,
    );
    final filtered = tester.widget<ColorFiltered>(
      find.byKey(const Key('animated_hermes_logo_light_artwork')),
    );
    expect(filtered.colorFilter, expectedTint(colors.accent));
    expect(
      find.descendant(
        of: find.byKey(const Key('animated_hermes_logo_light_artwork')),
        matching: find.byType(Image),
      ),
      findsOneWidget,
    );
    final images = tester.widgetList<Image>(find.byType(Image));
    expect(
      // El provider puede venir envuelto en ResizeImage (cacheWidth/Height de
      // decodificado acotado); la aserción sigue siendo sobre el asset origen.
      images.map((image) {
        final provider = image.image;
        final asset = provider is ResizeImage
            ? provider.imageProvider
            : provider;
        return (asset as AssetImage).assetName;
      }),
      everyElement('assets/branding/hermes_logo_light.png'),
    );
    final emblem = tester.widget<Container>(
      find.byKey(const Key('animated_hermes_logo_emblem')),
    );
    final decoration = emblem.decoration! as BoxDecoration;
    expect(decoration.color, isNull);
    expect(decoration.gradient, isNull);
  });

  testWidgets('splash tints the complete brand with the active theme', (
    tester,
  ) async {
    final theme = AppTheme.fromId('crimson');
    final colors = theme.hermes;
    final expected =
        ThemeContrast.meets(colors.accent, colors.background, minimum: 3)
        ? colors.accent
        : colors.accentText;
    var completed = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: SplashScreen(onDone: () => completed = true),
      ),
    );
    await tester.pump();

    final logo = tester.widget<AnimatedHermesLogo>(
      find.byType(AnimatedHermesLogo),
    );
    expect(logo.color, expected);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byKey(const ValueKey('splash-progress-bar')), findsOneWidget);
    final fill = tester.widget<Container>(
      find.byKey(const ValueKey('splash-progress-fill')),
    );
    expect(fill.color, expected);
    expect(find.byKey(const Key('animated_hermes_logo_tint')), findsOneWidget);

    final beforePercent = tester
        .widget<Text>(find.byKey(const ValueKey('splash-progress-percent')))
        .data;
    await tester.pump(const Duration(milliseconds: 450));
    final midwayPercent = tester
        .widget<Text>(find.byKey(const ValueKey('splash-progress-percent')))
        .data;
    expect(midwayPercent, isNot(beforePercent));

    await tester.pump(const Duration(milliseconds: 2550));
    expect(completed, isFalse);
    final leaving = tester.widget<AnimatedOpacity>(
      find.byKey(const Key('splash-content-opacity')),
    );
    expect(leaving.opacity, 0);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, colors.background);
    await tester.pump(const Duration(milliseconds: 460));
    expect(completed, isTrue);
  });

  testWidgets('splash projects real startup milestones as a percentage', (
    tester,
  ) async {
    final progress = ValueNotifier<double>(0.34);
    addTearDown(progress.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SplashScreen(ready: false, progress: progress, onDone: () {}),
      ),
    );
    await tester.pump();

    expect(find.text('34%'), findsOneWidget);
    progress.value = 0.92;
    await tester.pump();
    expect(find.text('92%'), findsOneWidget);
  });

  testWidgets(
    'splash keeps 1 2 and 3 digit percentages aligned in a stable slot',
    (tester) async {
      final progress = ValueNotifier<double>(0.01);
      addTearDown(progress.dispose);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.10)),
          child: MaterialApp(
            home: SplashScreen(ready: false, progress: progress, onDone: () {}),
          ),
        ),
      );
      await tester.pump();

      final barFinder = find.byKey(const ValueKey('splash-progress-bar'));
      final trackFinder = find.byKey(const ValueKey('splash-progress-track'));
      final slotFinder = find.byKey(
        const ValueKey('splash-progress-percent-slot'),
      );
      final percentFinder = find.byKey(
        const ValueKey('splash-progress-percent'),
      );

      final initialBar = tester.getRect(barFinder);
      final initialTrack = tester.getRect(trackFinder);
      final initialSlot = tester.getRect(slotFinder);
      final initialPercent = tester.getRect(percentFinder);
      expect(initialBar.width, 168);
      expect(initialTrack.width, 120);
      expect(initialSlot.width, 40);
      expect(initialSlot.left - initialTrack.right, 8);
      expect(initialPercent.left, closeTo(initialSlot.left, 0.01));
      expect(initialPercent.center.dy, closeTo(initialTrack.center.dy, 0.5));

      for (final milestone in <double>[0.10, 1.0]) {
        progress.value = milestone;
        await tester.pump();

        final bar = tester.getRect(barFinder);
        final track = tester.getRect(trackFinder);
        final slot = tester.getRect(slotFinder);
        final percent = tester.getRect(percentFinder);
        expect(bar, initialBar);
        expect(track, initialTrack);
        expect(slot, initialSlot);
        expect(percent.left, closeTo(initialPercent.left, 0.01));
        expect(percent.right, lessThanOrEqualTo(slot.right));
        expect(percent.center.dy, closeTo(track.center.dy, 0.5));
      }

      expect(find.text('100%'), findsOneWidget);
    },
  );

  testWidgets('splash waits for Home readiness after its minimum duration', (
    tester,
  ) async {
    var completed = false;
    var ready = false;

    Widget app() => MaterialApp(
      home: SplashScreen(ready: ready, onDone: () => completed = true),
    );

    await tester.pumpWidget(app());
    await tester.pump(const Duration(milliseconds: 3360));

    expect(completed, isFalse);
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const Key('splash-content-opacity')),
          )
          .opacity,
      1,
    );

    ready = true;
    await tester.pumpWidget(app());
    await tester.pump();
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const Key('splash-content-opacity')),
          )
          .opacity,
      0,
    );
    await tester.pump(const Duration(milliseconds: 460));
    expect(completed, isTrue);
  });
}
