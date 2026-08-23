import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hermes_android/core/models/run_template.dart';
import 'package:hermes_android/core/services/run_template_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('empieza sin plantillas propias', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = await RunTemplateStore.load(prefs);
    expect(store.custom, isEmpty);
  });

  test('añade, persiste y recarga una plantilla propia', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = await RunTemplateStore.load(prefs);
    final t = RunTemplate(
      id: RunTemplateStore.newId(),
      name: 'Mía',
      prompt: 'Haz {algo}',
    );
    await store.add(t);
    expect(store.custom, hasLength(1));

    // Una segunda carga (otra instancia) ve la plantilla persistida.
    final reloaded = await RunTemplateStore.load(prefs);
    expect(reloaded.custom.single.name, 'Mía');
    expect(reloaded.custom.single.prompt, 'Haz {algo}');
  });

  test('update modifica solo la plantilla indicada', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = await RunTemplateStore.load(prefs);
    final t = RunTemplate(id: 'x1', name: 'A', prompt: 'p');
    await store.add(t);
    await store.update(t.copyWith(name: 'B'));
    expect(store.custom.single.name, 'B');
  });

  test('remove borra la plantilla', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = await RunTemplateStore.load(prefs);
    final t = RunTemplate(id: 'x1', name: 'A', prompt: 'p');
    await store.add(t);
    await store.remove('x1');
    expect(store.custom, isEmpty);
  });

  test('datos corruptos no rompen la carga', () async {
    SharedPreferences.setMockInitialValues({
      'run_templates_custom_v1': 'no-es-json',
    });
    final prefs = await SharedPreferences.getInstance();
    final store = await RunTemplateStore.load(prefs);
    expect(store.custom, isEmpty);
  });

  test('isReadyToLaunch distingue prompts listos de los abiertos', () {
    const ready = RunTemplate(id: 'a', name: 'a', prompt: 'Haz esto ya');
    const open = RunTemplate(id: 'b', name: 'b', prompt: 'Completa esto:');
    expect(ready.isReadyToLaunch, isTrue);
    expect(open.isReadyToLaunch, isFalse);
  });
}
