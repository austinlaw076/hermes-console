import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/theme/motion.dart';
import 'package:hermes_android/core/widgets/motion_entrance.dart';

void main() {
  Widget host({required bool disableAnimations}) => MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: const Directionality(
      textDirection: TextDirection.ltr,
      child: MotionEntrance(child: Text('hola')),
    ),
  );

  testWidgets('anima de casi invisible a visible', (tester) async {
    await tester.pumpWidget(host(disableAnimations: false));
    await tester.pump(); // dispara el post-frame callback → arranca forward

    final start = tester.widget<FadeTransition>(find.byType(FadeTransition));
    expect(start.opacity.value, lessThan(1.0));

    await tester.pump(Motion.base);
    final end = tester.widget<FadeTransition>(find.byType(FadeTransition));
    expect(end.opacity.value, 1.0);
  });

  testWidgets('con reduce motion aparece instantáneo', (tester) async {
    await tester.pumpWidget(host(disableAnimations: true));
    await tester.pump();

    final fade = tester.widget<FadeTransition>(find.byType(FadeTransition));
    expect(fade.opacity.value, 1.0);
  });
}
