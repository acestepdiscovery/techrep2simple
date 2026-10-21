// (2026-10-21) Chaque appel IA envoie la langue de l'app ET son numéro de build :
// le serveur peut réserver un bonus IA temporaire aux versions à jour
// (`ai_bonus_min_build` dans config/app_control). Sans `app_build`, une version
// à jour serait traitée comme une ancienne → pas de bonus.
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:reportnew1cld/core/config/app_build.dart';
import 'package:reportnew1cld/shared/services/ai_service.dart';

void main() {
  tearDown(() => Intl.defaultLocale = null);

  test('app_build = numéro de build de cette version', () {
    final b = AiService.withDefaults({'action': 'improve_report'});
    expect(b['app_build'], kAppBuildNumber);
    expect(b['app_build'], greaterThanOrEqualTo(23));
  });

  test('langue de l\'app par défaut, sans le pays', () {
    Intl.defaultLocale = 'de_DE';
    expect(AiService.withDefaults({})['lang'], 'de');
  });

  test('une langue passée explicitement est gardée', () {
    Intl.defaultLocale = 'de_DE';
    expect(AiService.withDefaults({'lang': 'pt'})['lang'], 'pt');
  });

  test('les champs de la requête ne sont pas touchés', () {
    final b = AiService.withDefaults({'action': 'audio_to_report', 'audio_mime': 'video/mp4'});
    expect(b['action'], 'audio_to_report');
    expect(b['audio_mime'], 'video/mp4');
  });
}
