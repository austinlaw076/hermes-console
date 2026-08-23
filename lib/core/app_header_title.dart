import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Título del header configurable (Ajustes › Título del header), REACTIVO.
///
/// Antes cada pantalla leía `prefs.getString('header_title')` en su build/init,
/// así que al cambiarlo en Ajustes el Home (que quedaba detrás) no se enteraba
/// hasta un rebuild posterior ("tuve que hacerlo 2 veces"). Con un notifier
/// global, cambiarlo se refleja al instante en Home/Sesiones/Chat.
final ValueNotifier<String> headerTitleNotifier =
    ValueNotifier<String>(kDefaultHeaderTitle);

const String kDefaultHeaderTitle = 'HERMES CONSOLE';
const String kHeaderTitlePrefKey = 'header_title';

String _normalize(String? raw) {
  final t = (raw ?? '').trim();
  return t.isEmpty ? kDefaultHeaderTitle : t;
}

/// Carga el valor persistido al arrancar la app.
void loadHeaderTitle(SharedPreferences prefs) {
  headerTitleNotifier.value = _normalize(prefs.getString(kHeaderTitlePrefKey));
}

/// Persiste y notifica el nuevo título (reactivo en todas las pantallas).
Future<void> setHeaderTitle(SharedPreferences prefs, String value) async {
  final v = _normalize(value);
  await prefs.setString(kHeaderTitlePrefKey, v);
  headerTitleNotifier.value = v;
}
