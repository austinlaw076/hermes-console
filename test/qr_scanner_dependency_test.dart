import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('QR scanner dependency remains on the open-source ZXing stack', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final lockfile = File('pubspec.lock').readAsStringSync();
    final proguard = File('android/app/proguard-rules.pro').readAsStringSync();

    expect(
      pubspec,
      contains(RegExp(r'^\s*qr_code_scanner_plus:', multiLine: true)),
    );
    expect(
      pubspec,
      isNot(contains(RegExp(r'^\s*mobile_scanner:', multiLine: true))),
    );
    expect(
      lockfile,
      contains(RegExp(r'^\s*qr_code_scanner_plus:', multiLine: true)),
    );
    expect(
      lockfile,
      isNot(contains(RegExp(r'^\s*mobile_scanner:', multiLine: true))),
    );
    expect(proguard, contains('com.google.zxing'));
    expect(proguard, contains('com.journeyapps.barcodescanner'));
    expect(proguard, isNot(contains('com.google.mlkit')));
    expect(proguard, isNot(contains('com.google.android.gms')));
  });
}
