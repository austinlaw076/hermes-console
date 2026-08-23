import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/bridge_version.dart';

void main() {
  group('BridgeVersion.compare', () {
    test('ordena versiones numéricas', () {
      expect(BridgeVersion.compare('1.7.3', '1.8.0'), lessThan(0));
      expect(BridgeVersion.compare('1.8.0', '1.7.3'), greaterThan(0));
      expect(BridgeVersion.compare('1.8.0', '1.8.0'), 0);
      expect(BridgeVersion.compare('1.10.0', '1.9.9'), greaterThan(0));
      expect(BridgeVersion.compare('2.0', '1.9.9'), greaterThan(0));
    });

    test('tolera longitudes distintas y basura', () {
      expect(BridgeVersion.compare('1.8', '1.8.0'), 0);
      expect(BridgeVersion.compare('1.8.0', '1.8'), 0);
      expect(BridgeVersion.compare('x.y.z', '0.0.0'), 0);
    });
  });

  group('BridgeVersion.isOutdated', () {
    test('null/vacío no se considera desactualizado', () {
      expect(BridgeVersion.isOutdated(null), isFalse);
      expect(BridgeVersion.isOutdated(''), isFalse);
      expect(BridgeVersion.isOutdated('   '), isFalse);
    });

    test('una versión anterior a la empaquetada está desactualizada', () {
      expect(BridgeVersion.isOutdated('1.0.0'), isTrue);
    });

    test('la versión empaquetada (o superior) no está desactualizada', () {
      expect(BridgeVersion.isOutdated(BridgeVersion.expected), isFalse);
      expect(BridgeVersion.isOutdated('99.0.0'), isFalse);
    });
  });
}
