import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/theme/motion.dart';

void main() {
  Future<Duration> effectiveUnder(WidgetTester tester, bool disable) async {
    late Duration result;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: disable),
        child: Builder(
          builder: (context) {
            result = Motion.duration(context, Motion.base);
            return const SizedBox();
          },
        ),
      ),
    );
    return result;
  }

  testWidgets('con reduce motion la duración efectiva es cero', (tester) async {
    expect(await effectiveUnder(tester, true), Duration.zero);
  });

  testWidgets('sin reduce motion la duración efectiva es la nominal', (
    tester,
  ) async {
    expect(await effectiveUnder(tester, false), Motion.base);
  });

  test('todas las duraciones del catálogo están dentro del presupuesto', () {
    for (final d in [Motion.fast, Motion.base, Motion.page]) {
      expect(d.inMilliseconds, lessThanOrEqualTo(300));
    }
  });

  testWidgets('reduced() lee disableAnimations del MediaQuery', (tester) async {
    late bool reduced;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Builder(
          builder: (context) {
            reduced = Motion.reduced(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(reduced, isTrue);
  });
}
