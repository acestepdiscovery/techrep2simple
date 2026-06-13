import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// (B/L) « Suppression » douce : un rapport supprimé n'est PAS effacé tout de
// suite — son id va dans une archive (set d'ids en SharedPreferences). Il
// disparaît de la liste principale mais reste récupérable, et la suppression
// DÉFINITIVE se fait depuis l'onglet Archive (réservé Pro). Aucune migration de
// base : on ne touche pas au schéma SQLite.
const _kArchivedKey = 'archived_report_ids';

class ArchivedReportsNotifier extends StateNotifier<Set<String>> {
  ArchivedReportsNotifier() : super(<String>{}) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = (prefs.getStringList(_kArchivedKey) ?? const <String>[]).toSet();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kArchivedKey, state.toList());
  }

  /// Envoie un rapport à l'archive (suppression douce).
  Future<void> archive(String id) async {
    state = {...state, id};
    await _persist();
  }

  /// Restaure un rapport archivé vers la liste principale.
  Future<void> restore(String id) async {
    state = {...state}..remove(id);
    await _persist();
  }

  /// Retire l'id de l'archive (après une suppression DÉFINITIVE en base).
  Future<void> forget(String id) => restore(id);
}

final archivedReportsProvider =
    StateNotifierProvider<ArchivedReportsNotifier, Set<String>>(
        (ref) => ArchivedReportsNotifier());
