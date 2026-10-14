import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';

/// Texte d'erreur montrable à l'utilisateur (2026-10-14).
///
/// Avant : `'common_error'.tr(args: ['$e'])` affichait « Erreur : Exception:
/// Échec upload Drive (403) » — préfixe technique + texte parfois en français
/// pour tout le monde. Ici :
/// - pas de réseau / délai dépassé → message traduit « vérifiez votre connexion » ;
/// - réponse illisible du serveur (page HTML d'erreur…) → « erreur inconnue » ;
/// - sinon le message, sans le préfixe « Exception: ».
String errorText(Object e) {
  if (e is SocketException || e is TimeoutException || e is HttpException) {
    return 'ai_err_network'.tr();
  }
  if (e is FormatException) return 'common_unknown_error'.tr();
  final s = e.toString();
  // ClientException (package http) : erreur réseau, message anglais technique.
  if (s.startsWith('ClientException')) return 'ai_err_network'.tr();
  return s.replaceFirst(RegExp(r'^(Exception|Error|StateError|Bad state): '), '');
}
