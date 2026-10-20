import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:reportnew1cld/shared/services/notification_service.dart';

// (2026-10-20) Les notifications d'équipe étaient toujours en français : l'app
// transmet désormais sa langue au serveur avec le jeton de l'appareil.
void main() {
  tearDown(() => Intl.defaultLocale = null);

  test('langue transmise = code court de la langue de l\'app', () {
    Intl.defaultLocale = 'de_DE';
    expect(NotificationService.notifLang(), 'de');
    Intl.defaultLocale = 'pt-PT';
    expect(NotificationService.notifLang(), 'pt');
    Intl.defaultLocale = 'en';
    expect(NotificationService.notifLang(), 'en');
  });
}
