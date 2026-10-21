import 'dart:convert';

import '../reports/models/currency_options.dart';
import '../reports/models/report_model.dart';

/// (2026-10-21) Pastilles de la liste « Rapports » de l'équipe (idée validée par le
/// user) : nombre de photos, signé par le client ou non, montant HT — pour juger
/// d'un coup d'œil avant d'ouvrir / valider. Calculées depuis le document Firestore
/// du rapport (champs de `ReportModel.toMap`, JSON en texte pour photos/matériel).

List<dynamic> _jsonList(Object? v) {
  if (v is List) return v;
  if (v is String && v.isNotEmpty) {
    try {
      final d = jsonDecode(v);
      if (d is List) return d;
    } catch (_) {}
  }
  return const [];
}

/// Nombre de photos du rapport.
int teamReportPhotoCount(Map<String, dynamic> data) => _jsonList(data['photos']).length;

/// Le client a signé (début ou fin d'intervention, sur place ou à distance).
bool teamReportSigned(Map<String, dynamic> data) {
  bool has(String k) => (data[k] as String?)?.isNotEmpty == true;
  return has('signature_client_data') || has('signature_client_start_data');
}

/// Montant HT : main-d'œuvre + matériel (chaque ligne arrondie, comme la facture).
double teamReportAmount(Map<String, dynamic> data) {
  final hours = (data['labor_hours'] as num?)?.toDouble() ?? 0;
  final rate = (data['labor_rate'] as num?)?.toDouble() ?? 0;
  var total = roundMoney(hours * rate);
  for (final m in _jsonList(data['materials'])) {
    if (m is Map) total += roundMoney(MaterialItem.fromMap(Map<String, dynamic>.from(m)).total);
  }
  return roundMoney(total);
}
