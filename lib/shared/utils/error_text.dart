import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;

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
  // Firebase (Auth, Firestore…) : message technique en anglais → traduit.
  if (e is FirebaseException) {
    const network = {'network-request-failed', 'unavailable', 'deadline-exceeded'};
    if (network.contains(e.code)) return 'ai_err_network'.tr();
    if (e.code == 'too-many-requests') return 'auth_err_too_many'.tr();
    return '${'common_unknown_error'.tr()} (${e.code})';
  }
  final s = e.toString();
  // ClientException (package http) : erreur réseau, message anglais technique.
  if (s.startsWith('ClientException')) return 'ai_err_network'.tr();
  return s.replaceFirst(RegExp(r'^(Exception|Error|StateError|Bad state): '), '');
}
