import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Stockage PERMANENT des images choisies par l'utilisateur (2026-10-14).
///
/// Le sélecteur d'images (image_picker) dépose ses fichiers dans le CACHE /
/// dossier temporaire de l'app, que le système VIDE quand il veut (iOS : tmp
/// purgé régulièrement ; Android : manque de place ou « vider le cache »).
/// Avant, l'app gardait ces chemins tels quels → les photos des rapports et le
/// logo finissaient par disparaître sans prévenir (PDF régénéré sans photos).
/// Ici : copie dans le dossier Documents de l'app (jamais vidé par le système).
class PhotoStorage {
  static const reportPhotos = 'report_photos';
  static const branding = 'branding';

  static Future<String> _base() async =>
      (await getApplicationDocumentsDirectory()).path;

  /// Le fichier est-il déjà dans le stockage permanent de l'app ?
  static Future<bool> isPermanent(String path) async =>
      kIsWeb || p.isWithin(await _base(), path);

  /// Copie [path] dans `Documents/<sub>/` et renvoie le nouveau chemin.
  /// Déjà permanent, introuvable, ou erreur → renvoie [path] inchangé.
  static Future<String> persist(String path, {String sub = reportPhotos}) async {
    if (kIsWeb || path.isEmpty) return path;
    try {
      final base = await _base();
      if (p.isWithin(base, path)) return path;
      final src = File(path);
      if (!src.existsSync()) return path;
      final dir = Directory(p.join(base, sub));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final ext = p.extension(path).isEmpty ? '.jpg' : p.extension(path);
      final dest = p.join(dir.path, '${const Uuid().v4()}$ext');
      await src.copy(dest);
      return dest;
    } catch (e) {
      debugPrint('[PhotoStorage] copie impossible ($path) : $e');
      return path;
    }
  }

  /// Supprime [path] s'il appartient au stockage permanent de l'app (jamais un
  /// fichier extérieur, ex. la galerie du téléphone).
  static Future<void> deleteIfOwned(String path) async {
    if (kIsWeb || path.isEmpty) return;
    try {
      final base = await _base();
      if (!p.isWithin(base, path)) return;
      final f = File(path);
      if (f.existsSync()) await f.delete();
    } catch (_) {}
  }

  /// Supprime tout le dossier [sub] (effacement des données du compte).
  static Future<void> deleteAll(String sub) async {
    if (kIsWeb) return;
    try {
      final dir = Directory(p.join(await _base(), sub));
      if (dir.existsSync()) await dir.delete(recursive: true);
    } catch (_) {}
  }
}
