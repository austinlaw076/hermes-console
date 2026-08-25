import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/utils/relative_time.dart';

void main() {
  final now = DateTime(2026, 7, 26, 21);
  double stamp(Duration age) => now.subtract(age).millisecondsSinceEpoch / 1000;

  test('usa unidades compactas en español sin texto inglés', () {
    expect(
      relativeTime(
        stamp(const Duration(seconds: 20)),
        languageCode: 'es',
        now: now,
      ),
      'ahora',
    );
    expect(
      relativeTime(
        stamp(const Duration(minutes: 36)),
        languageCode: 'es',
        now: now,
      ),
      '36 min',
    );
    expect(
      relativeTime(
        stamp(const Duration(hours: 2)),
        languageCode: 'es',
        now: now,
      ),
      '2 h',
    );
  });

  test('conserva el formato inglés para la locale inglesa', () {
    expect(
      relativeTime(
        stamp(const Duration(minutes: 36)),
        languageCode: 'en',
        now: now,
      ),
      '36m ago',
    );
  });

  test('usa formato tradicional de Hong Kong para zh_Hant', () {
    expect(
      relativeTime(
        stamp(const Duration(seconds: 20)),
        languageCode: 'zh_Hant',
        now: now,
      ),
      '剛剛',
    );
    expect(
      relativeTime(
        stamp(const Duration(minutes: 36)),
        languageCode: 'zh_Hant',
        now: now,
      ),
      '36 分鐘前',
    );
    expect(
      relativeTime(
        stamp(const Duration(hours: 2)),
        languageCode: 'zh_Hant',
        now: now,
      ),
      '2 小時前',
    );
  });
}
