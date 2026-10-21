import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/reports/models/report_model.dart';
import 'local_db_service.dart';
import 'photo_storage.dart';

/// (2026-10-21) Photo prise pendant qu'Android FERME l'app (téléphone qui manque de
/// mémoire : l'appareil photo prend toute la place). Signalé par un utilisateur
/// (« on perd les photos », « le message félicitations efface mon rapport »),
/// reproduit sur émulateur en tuant l'app pendant la prise de vue : au retour, l'app
/// redémarrait sur l'accueil, rapport en cours ET photo perdus.
///
/// Parade :
///  1. avant d'ouvrir l'appareil photo / la galerie, le formulaire enregistre le
///     brouillon et note ici quel rapport attend une photo ([mark]) ;
///  2. au démarrage suivant, [recover] récupère la photo restée chez Android
///     (`retrieveLostData`), l'ajoute à CE rapport et renvoie son id → l'app rouvre
///     le formulaire.
class PendingCapture {
  static const _kId = 'pending_capture_report_id';
  static const _kAt = 'pending_capture_at_ms';

  /// Une prise de vue plus vieille que ça n'est plus rattachée à un rapport.
  static const maxAge = Duration(hours: 6);

  static Future<void> mark(String reportId) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kId, reportId);
      await p.setInt(_kAt, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_kId);
      await p.remove(_kAt);
    } catch (_) {}
  }

  /// Rapport en attente d'une photo (null si aucun ou trop ancien).
  static Future<String?> pendingReportId({DateTime? now}) async {
    try {
      final p = await SharedPreferences.getInstance();
      final id = p.getString(_kId);
      final at = p.getInt(_kAt);
      if (id == null || at == null) return null;
      final age = (now ?? DateTime.now()).difference(DateTime.fromMillisecondsSinceEpoch(at));
      return age <= maxAge ? id : null;
    } catch (_) {
      return null;
    }
  }

  /// Ajoute [photoPaths] au rapport [reportId] (créé en brouillon s'il n'existe
  /// pas encore : rapport vide au moment de la prise de vue). Testé.
  static Future<void> attach(String reportId, List<String> photoPaths,
      {LocalDbService? db, DateTime? now}) async {
    final d = db ?? LocalDbService();
    final t = now ?? DateTime.now();
    final existing = await d.getReport(reportId);
    if (existing != null) {
      await d.insertReport(existing.copyWith(
        photosPaths: [...existing.photosPaths, ...photoPaths],
      ));
    } else {
      await d.insertReport(ReportModel(
        id: reportId,
        clientName: '',
        date: t,
        status: ReportStatus.draft,
        photosPaths: photoPaths,
        createdAt: t,
        updatedAt: t,
      ));
    }
  }

  /// Au démarrage (Android) : photo(s) perdue(s) récupérée(s) → ajoutée(s) au
  /// rapport en attente ; renvoie son id (sinon null).
  static Future<String?> recover() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    final id = await pendingReportId();
    LostDataResponse resp;
    try {
      resp = await ImagePicker().retrieveLostData();
    } catch (_) {
      return null;
    }
    if (resp.isEmpty) {
      if (id != null) await clear();
      return null;
    }
    final files = resp.files ?? (resp.file != null ? [resp.file!] : const <XFile>[]);
    await clear();
    if (id == null || files.isEmpty) return null;
    final kept = <String>[];
    for (final f in files) {
      kept.add(await PhotoStorage.persist(f.path));
    }
    await attach(id, kept);
    return id;
  }
}
