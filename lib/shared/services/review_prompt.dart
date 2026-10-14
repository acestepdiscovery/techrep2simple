import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Demande de note dans le store (2026-10-14).
///
/// Fenêtre OFFICIELLE de notation (Apple / Google), proposée à un utilisateur
/// qui a déjà obtenu de la valeur : après son 3ᵉ, 10ᵉ puis 20ᵉ export PDF
/// réussi. Le système décide lui-même s'il l'affiche (Apple : 3 fois par an au
/// maximum ; Google : quota) → jamais de harcèlement, et aucun texte à traduire.
class ReviewPrompt {
  static const _key = 'review_successful_exports';
  static const milestones = {3, 10, 20};

  /// À appeler APRÈS un export PDF réussi (partage effectué).
  static Future<void> onSuccessfulExport() async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final n = (prefs.getInt(_key) ?? 0) + 1;
      await prefs.setInt(_key, n);
      if (!milestones.contains(n)) return;
      // Laisser la feuille de partage se refermer avant de proposer la note.
      await Future<void>.delayed(const Duration(seconds: 2));
      final review = InAppReview.instance;
      if (await review.isAvailable()) await review.requestReview();
    } catch (e) {
      debugPrint('[ReviewPrompt] $e');
    }
  }
}
