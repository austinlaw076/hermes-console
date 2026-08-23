import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hermes_android/core/services/font_size_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'fija la escala interna en 110 % aunque exista una preferencia antigua',
    () async {
      SharedPreferences.setMockInitialValues({'font_size_scale': 1.4});
      final service = FontSizeService(await SharedPreferences.getInstance());

      expect(service.scale, 1.10);
      expect(FontSizeService.fixedScale, 1.10);
    },
  );

  test('la API heredada no cambia la densidad fija', () async {
    SharedPreferences.setMockInitialValues({});
    final service = FontSizeService(await SharedPreferences.getInstance());

    await service.setScale(0.9);

    expect(service.scale, 1.10);
    expect(FontSizeService.normalize(double.nan), 1.10);
  });
}
