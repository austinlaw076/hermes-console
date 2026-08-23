import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/companion/models/companion_animation_state.dart';
import 'package:hermes_android/core/widgets/hermes_spark_mascot.dart';

void main() {
  group('companionStateForMood', () {
    const expected = <HermesSparkMood, CompanionAnimationState>{
      HermesSparkMood.idle: CompanionAnimationState.idle,
      HermesSparkMood.thinking: CompanionAnimationState.run,
      HermesSparkMood.connecting: CompanionAnimationState.waiting,
      HermesSparkMood.waiting: CompanionAnimationState.waiting,
      HermesSparkMood.success: CompanionAnimationState.wave,
      HermesSparkMood.error: CompanionAnimationState.failed,
      HermesSparkMood.offline: CompanionAnimationState.idle,
      HermesSparkMood.jump: CompanionAnimationState.jump,
    };

    test('cubre todos los HermesSparkMood', () {
      expect(expected.keys.toSet(), HermesSparkMood.values.toSet());
    });

    for (final entry in expected.entries) {
      test('${entry.key.name} → ${entry.value.name}', () {
        expect(companionStateForMood(entry.key), entry.value);
      });
    }
  });

  group('companionStateFromId', () {
    test('reconoce ids válidos', () {
      expect(companionStateFromId('idle'), CompanionAnimationState.idle);
      expect(companionStateFromId('failed'), CompanionAnimationState.failed);
    });

    test('devuelve null para ids desconocidos', () {
      expect(companionStateFromId('bogus'), isNull);
    });
  });

  group('CompanionAnimationStateX.loopsByDefault', () {
    test('idle/run/waiting ciclan; wave/failed/jump/review no', () {
      expect(CompanionAnimationState.idle.loopsByDefault, isTrue);
      expect(CompanionAnimationState.run.loopsByDefault, isTrue);
      expect(CompanionAnimationState.waiting.loopsByDefault, isTrue);
      expect(CompanionAnimationState.wave.loopsByDefault, isFalse);
      expect(CompanionAnimationState.failed.loopsByDefault, isFalse);
      expect(CompanionAnimationState.jump.loopsByDefault, isFalse);
      expect(CompanionAnimationState.review.loopsByDefault, isFalse);
    });
  });
}
