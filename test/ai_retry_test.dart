import 'package:flutter_test/flutter_test.dart';
import 'package:reportnew1cld/shared/services/ai_service.dart';

// (2026-10-20) Une dictée (jusqu'à 15 min) était PERDUE si l'IA échouait : la
// feuille se fermait. Désormais elle reste ouverte pour les échecs réessayables.
void main() {
  test('réessayable : réseau, service IA indisponible', () {
    expect(const AiActionResult(error: 'network_error: timeout').isRetryable, isTrue);
    expect(const AiActionResult(error: 'AI service error: kie.ai code=524').isRetryable, isTrue);
    expect(const AiActionResult(error: 'unknown_error').isRetryable, isTrue);
  });

  test('PAS réessayable : succès, quota, abonnement, déconnecté', () {
    expect(const AiActionResult().isRetryable, isFalse);
    expect(const AiActionResult(error: 'quota_exceeded').isRetryable, isFalse);
    expect(const AiActionResult(error: 'subscription_required').isRetryable, isFalse);
    expect(const AiActionResult(error: 'not_authenticated').isRetryable, isFalse);
  });
}
