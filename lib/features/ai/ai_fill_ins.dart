import '../reports/models/currency_options.dart';

/// (2026-10-20) Champs extraits par l'IA, non vides, dans l'ordre [order] (celui du
/// formulaire) ; les clés inconnues à la fin. L'IA renvoie les clés par ordre
/// alphabétique (Adresse, Client, Description, Fin…), peu lisible.
List<MapEntry<String, String>> orderedAiFields(Map<String, String> fields, List<String> order) => [
      for (final k in order)
        if ((fields[k] ?? '').trim().isNotEmpty) MapEntry(k, fields[k]!),
      for (final e in fields.entries)
        if (!order.contains(e.key) && e.value.trim().isNotEmpty) e,
    ];

/// (2026-10-20) « Améliorer un rapport » avec une note (écrite ou audio) : l'IA peut
/// y trouver le contact sur place, le n° de contrat, la durée ou les horaires.
/// Avant, l'app ignorait ces champs. Ils sont repris dans la copie améliorée
/// SEULEMENT s'ils étaient vides dans l'original — jamais d'écrasement de ce que
/// le technicien a saisi.
///
/// [map] = `ReportModel.toMap()` de la copie (modifiée en place) ; [ai] = champs IA.
void applyImproveFillIns(Map<String, dynamic> map, Map<String, String> ai) {
  bool empty(String key) => (map[key]?.toString() ?? '').trim().isEmpty;
  String val(String key) => (ai[key] ?? '').trim();

  for (final key in const ['client_contact', 'contract_number']) {
    if (empty(key) && val(key).isNotEmpty) map[key] = val(key);
  }

  if (map['labor_hours'] == null) {
    final h = parseLocalNumber(val('labor_hours'));
    if (h != null && h > 0 && h < 1000) map['labor_hours'] = h;
  }

  // Horaires « HH:MM » → posés sur la date du rapport.
  final day = DateTime.tryParse(map['date']?.toString() ?? '') ?? DateTime.now();
  for (final key in const ['start_time', 'end_time']) {
    if (!empty(key)) continue;
    final m = RegExp(r'^(\d{1,2})[:hH.](\d{2})$').firstMatch(val(key));
    if (m == null) continue;
    final h = int.parse(m.group(1)!), min = int.parse(m.group(2)!);
    if (h > 23 || min > 59) continue;
    map[key] = DateTime(day.year, day.month, day.day, h, min).toIso8601String();
  }
}
