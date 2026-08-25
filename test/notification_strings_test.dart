import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/l10n/app_locale_resolve.dart';
import 'package:hermes_android/core/services/notifications/notification_strings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NotifL10n', () {
    test('es/en/zh no mezclan idiomas', () {
      const es = NotifL10n.spanish();
      const en = NotifL10n.english();
      const zh = NotifL10n.zhHant();
      expect(es.approvalTitle, 'Hermes necesita tu permiso');
      expect(en.approvalTitle, 'Hermes needs your permission');
      expect(zh.approvalTitle, 'Hermes 需要你的批准');
      expect(es.runCompleted, 'Ejecución completada');
      expect(en.runCompleted, 'Run completed');
      expect(zh.runCompleted, '執行完成');
      expect(es.actApprove, 'Aprobar');
      expect(en.actApprove, 'Approve');
      expect(zh.actApprove, '批准');
      expect(es.voiceCardListening, 'Escuchando');
      expect(en.voiceCardListening, 'Listening');
      expect(zh.voiceCardListening, '正在聽');
      expect(es.es, isTrue);
      expect(en.es, isFalse);
      expect(zh.kind, AppLocaleKind.zhHant);
    });

    test('replyTitle nombra la sesión cuando se conoce', () {
      const es = NotifL10n.spanish();
      const en = NotifL10n.english();
      const zh = NotifL10n.zhHant();
      expect(es.replyTitle('Backup'), 'Hermes respondió en Backup');
      expect(es.replyTitle(null), 'Hermes respondió');
      expect(zh.replyTitle('Backup'), 'Hermes 已在 Backup 回覆');
      expect(es.replyReadyBody, 'Respuesta lista. Toca para abrir.');
      expect(en.replyReadyBody, 'Reply ready. Tap to open.');
      expect(zh.replyReadyBody, '回覆已就緒。點一下開啟。');
    });

    test('of() resuelve el idioma desde app_locale', () async {
      SharedPreferences.setMockInitialValues({'app_locale': 'es'});
      expect(NotifL10n.of(await SharedPreferences.getInstance()).es, isTrue);
      SharedPreferences.setMockInitialValues({'app_locale': 'en'});
      expect(NotifL10n.of(await SharedPreferences.getInstance()).es, isFalse);
      SharedPreferences.setMockInitialValues({'app_locale': 'zh_Hant'});
      expect(
        NotifL10n.of(await SharedPreferences.getInstance()).kind,
        AppLocaleKind.zhHant,
      );
    });
  });
}
