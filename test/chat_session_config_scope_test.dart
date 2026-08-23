import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('el selector del chat no contiene mutaciones globales de modelo', () {
    final source = File('lib/core/screens/chat_screen.dart').readAsStringSync();

    expect(source, isNot(contains('.setActiveModel(')));
    expect(source, isNot(contains('bridge.setModel(')));
    expect(source, isNot(contains('/api/model/set')));
    expect(source, contains('_chat.setSessionModel('));
    expect(source, contains('sessionConfig: firstSubmitConfig'));
  });
}
