import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:hermes_android/core/widgets/theme_color_picker.dart';

void main() {
  testWidgets('elige color con barra de espectro y tonos sin sliders RGB/HSV', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Color? selected;
    Color? livePreview;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.fromId('dark'),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  selected = await showHermesColorPicker(
                    context,
                    initialColor: const Color(0xFFFF0000),
                    title: 'Acento',
                    invalidFormatLabel: 'Formato inválido',
                    onPreviewChanged: (color) => livePreview = color,
                  );
                },
                child: const Text('Elegir color'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Elegir color'));
    await tester.pumpAndSettle();

    expect(find.byType(Slider), findsNothing);
    expect(find.byKey(const Key('theme_color_wheel')), findsNothing);
    expect(find.byKey(const Key('theme_color_spectrum')), findsOneWidget);
    expect(find.byKey(const Key('theme_color_hex')), findsOneWidget);
    expect(find.byKey(const Key('theme_color_shade_0')), findsOneWidget);
    expect(find.byKey(const Key('theme_color_shade_3')), findsOneWidget);
    expect(find.byKey(const Key('theme_color_shade_4')), findsNothing);

    final spectrum = tester.getRect(
      find.byKey(const Key('theme_color_spectrum')),
    );
    await tester.tapAt(
      Offset(spectrum.left + spectrum.width * 0.25, spectrum.bottom - 6),
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('theme_color_shade_2')));
    await tester.tap(find.byKey(const Key('theme_color_shade_2')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('theme_color_confirm')));
    await tester.tap(find.byKey(const Key('theme_color_confirm')));
    await tester.pumpAndSettle();

    expect(selected, isNotNull);
    expect(livePreview, selected);
    final hsv = HSVColor.fromColor(selected!);
    expect(hsv.hue, closeTo(90, 2));
    expect(hsv.saturation, greaterThan(0.75));
    expect(hsv.value, closeTo(0.34, 0.02));
  });
}
