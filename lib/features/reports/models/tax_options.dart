import 'package:intl/intl.dart';
import 'currency_options.dart';

/// ─── Catalogue de taxes (TVA / VAT / MwSt / GST / Sales Tax…) ────────────────
///
/// Pourquoi ce fichier existe :
/// La taxe N'EST PAS liée à la langue mais au PAYS de l'entreprise — et même au
/// sein d'un pays il y a plusieurs taux (standard/réduit) + des cas à 0 %
/// (franchise en base FR, Kleinunternehmer DE…). On ne peut donc pas coder un
/// taux fixe par langue : on offre un **dropdown pays + taux**, un **défaut
/// déduit de la région/langue**, et tout reste **éditable librement** (option
/// « Autre / personnalisé » → n'importe quel pays).
///
/// Le calcul reste trivial partout : `taxe = sous-total × taux/100`.
///
/// ⚠️ Les `label` (« TVA », « MwSt. », « Sales Tax »…) et les `mention` (phrases
/// légales) sont des chaînes LITTÉRALES propres au pays — PAS des clés i18n :
/// une facture s'émet selon les règles du pays de l'entreprise, pas selon la
/// langue d'affichage de l'app. Seuls les NOMS de pays (`nameKey`) et les
/// libellés d'UI sont traduits (`.tr()` au rendu).

class TaxPreset {
  final String label; // ex. « TVA », « MwSt. », « Sales Tax »
  final double rate; // en POURCENT : 20.0, 5.5, 0.0
  final String mention; // mention légale facultative (peut être '')
  // (2026-10-21) Indication affichée dans le choix SEULEMENT (pas sur la facture) :
  // provinces du Canada (« QC », « ON »…).
  final String hint;
  const TaxPreset(this.label, this.rate, [this.mention = '', this.hint = '']);
}

class TaxCountry {
  final String code; // ISO-2 : « FR », « DE », « US »…
  final String nameKey; // clé i18n du nom de pays : « tax_country_FR »
  final List<TaxPreset> presets; // 1er = taux par défaut du pays
  const TaxCountry(this.code, this.nameKey, this.presets);
}

/// Configuration de taxe effective (résolue), telle qu'utilisée par la facture.
class TaxConfig {
  final double rate; // pourcent
  final String label;
  final String mention;
  const TaxConfig({required this.rate, required this.label, required this.mention});
}

/// Pays où l'app est réellement distribuable (Play + App Store + paiement carte).
/// Liste soignée + l'option « Autre / personnalisé » (kTaxOtherCode) couvre le
/// reste de la planète via saisie libre. Taux = valeurs standard connues ; ils
/// restent éditables côté utilisateur s'ils évoluent.
const List<TaxCountry> kTaxCountries = [
  TaxCountry('FR', 'tax_country_FR', [
    TaxPreset('TVA', 20),
    TaxPreset('TVA', 10),
    TaxPreset('TVA', 5.5),
    TaxPreset('TVA', 2.1),
    TaxPreset('TVA', 0, 'TVA non applicable, art. 293 B du CGI'),
  ]),
  TaxCountry('BE', 'tax_country_BE', [
    TaxPreset('TVA', 21),
    TaxPreset('TVA', 12),
    TaxPreset('TVA', 6),
  ]),
  TaxCountry('LU', 'tax_country_LU', [
    TaxPreset('TVA', 17),
    TaxPreset('TVA', 14),
    TaxPreset('TVA', 8),
    TaxPreset('TVA', 3),
  ]),
  TaxCountry('DE', 'tax_country_DE', [
    TaxPreset('MwSt.', 19),
    TaxPreset('MwSt.', 7),
    TaxPreset('MwSt.', 0, 'Gemäß § 19 UStG wird keine Umsatzsteuer ausgewiesen.'),
  ]),
  TaxCountry('AT', 'tax_country_AT', [
    TaxPreset('USt.', 20),
    TaxPreset('USt.', 13),
    TaxPreset('USt.', 10),
  ]),
  TaxCountry('CH', 'tax_country_CH', [
    TaxPreset('MwSt.', 8.1),
    TaxPreset('MwSt.', 3.8),
    TaxPreset('MwSt.', 2.6),
  ]),
  TaxCountry('NL', 'tax_country_NL', [
    TaxPreset('btw', 21),
    TaxPreset('btw', 9),
  ]),
  TaxCountry('ES', 'tax_country_ES', [
    TaxPreset('IVA', 21),
    TaxPreset('IVA', 10),
    TaxPreset('IVA', 4),
  ]),
  TaxCountry('IT', 'tax_country_IT', [
    TaxPreset('IVA', 22),
    TaxPreset('IVA', 10),
    TaxPreset('IVA', 5),
    TaxPreset('IVA', 4),
  ]),
  TaxCountry('PT', 'tax_country_PT', [
    TaxPreset('IVA', 23),
    TaxPreset('IVA', 13),
    TaxPreset('IVA', 6),
  ]),
  TaxCountry('IE', 'tax_country_IE', [
    TaxPreset('VAT', 23),
    TaxPreset('VAT', 13.5),
    TaxPreset('VAT', 9),
    TaxPreset('VAT', 0),
  ]),
  TaxCountry('FI', 'tax_country_FI', [
    TaxPreset('ALV', 25.5),
    TaxPreset('ALV', 14),
    TaxPreset('ALV', 10),
  ]),
  TaxCountry('GR', 'tax_country_GR', [
    TaxPreset('VAT', 24),
    TaxPreset('VAT', 13),
    TaxPreset('VAT', 6),
  ]),
  TaxCountry('PL', 'tax_country_PL', [
    TaxPreset('VAT', 23),
    TaxPreset('VAT', 8),
    TaxPreset('VAT', 5),
  ]),
  TaxCountry('SE', 'tax_country_SE', [
    TaxPreset('moms', 25),
    TaxPreset('moms', 12),
    TaxPreset('moms', 6),
  ]),
  TaxCountry('DK', 'tax_country_DK', [
    TaxPreset('moms', 25),
  ]),
  TaxCountry('NO', 'tax_country_NO', [
    TaxPreset('MVA', 25),
    TaxPreset('MVA', 15),
    TaxPreset('MVA', 12),
  ]),
  TaxCountry('GB', 'tax_country_GB', [
    TaxPreset('VAT', 20),
    TaxPreset('VAT', 5),
    TaxPreset('VAT', 0),
  ]),
  TaxCountry('US', 'tax_country_US', [
    // USA = sales tax saisie par l'utilisateur (varie par État/comté/ville) :
    // on ne la calcule jamais automatiquement → l'user entre SON taux.
    TaxPreset('Sales Tax', 0),
  ]),
  // (2026-10-21) Canada par province. Taxes COMPOSÉES (« GST + QST »…) : la facture
  // les détaille sur 2 lignes (voir kCompoundTaxes) ; avant : GST/HST 5/13/15 seulement.
  TaxCountry('CA', 'tax_country_CA', [
    TaxPreset('GST', 5, '', 'AB · YT · NT · NU'),
    TaxPreset('HST', 13, '', 'ON'),
    TaxPreset('HST', 14, '', 'NS'), // Nouvelle-Écosse : 14 % depuis le 1er avril 2025
    TaxPreset('HST', 15, '', 'NB · NL · PE'),
    TaxPreset('TPS + TVQ', 14.975, '', 'QC'), // Québec, factures en français
    TaxPreset('GST + QST', 14.975, '', 'QC'), // Québec, factures en anglais
    TaxPreset('GST + PST', 12, '', 'BC'), //     PST 7 %
    TaxPreset('GST + PST', 11, '', 'SK'), //     PST 6 %
    TaxPreset('GST + RST', 12, '', 'MB'), //     RST 7 %
  ]),
  TaxCountry('AU', 'tax_country_AU', [
    TaxPreset('GST', 10),
    TaxPreset('GST', 0),
  ]),
  TaxCountry('NZ', 'tax_country_NZ', [
    TaxPreset('GST', 15),
  ]),
  TaxCountry('IN', 'tax_country_IN', [
    TaxPreset('GST', 18),
    TaxPreset('GST', 12),
    TaxPreset('GST', 5),
    TaxPreset('GST', 28),
  ]),
];

/// (2026-10-21) Taxes COMPOSÉES : au Canada, la facture doit montrer chaque taxe sur
/// sa propre ligne (Québec : TPS 5 % ET TVQ 9,975 %). Le stockage reste UN libellé +
/// UN taux (« TPS + TVQ », 14,975) ; la facture retrouve ici les composantes. Un
/// libellé ou un taux modifié à la main → une seule ligne, comme avant.
const List<(String, double, List<(String, double)>)> kCompoundTaxes = [
  ('TPS + TVQ', 14.975, [('TPS', 5), ('TVQ', 9.975)]),
  ('GST + QST', 14.975, [('GST', 5), ('QST', 9.975)]),
  ('GST + PST', 12, [('GST', 5), ('PST', 7)]),
  ('GST + PST', 11, [('GST', 5), ('PST', 6)]),
  ('GST + RST', 12, [('GST', 5), ('RST', 7)]),
];

/// Composantes d'une taxe composée (libellé + taux exacts), sinon null.
List<(String, double)>? taxComponents(String label, double rate) {
  final l = label.trim().toUpperCase();
  for (final (name, total, parts) in kCompoundTaxes) {
    if (name.toUpperCase() == l && (total - rate).abs() < 0.0005) return parts;
  }
  return null;
}

/// Code spécial « Autre / personnalisé » (hors liste) : tout saisi à la main.
const String kTaxOtherCode = '_other';
const String kTaxOtherNameKey = 'tax_country_other';

TaxCountry? taxCountryByCode(String? code) {
  if (code == null) return null;
  for (final c in kTaxCountries) {
    if (c.code == code) return c;
  }
  return null;
}

/// Repli langue → pays quand la région du téléphone est inconnue/non listée.
String _languageToCountry(String? language) {
  switch (language) {
    case 'fr':
      return 'FR';
    case 'de':
      return 'DE';
    case 'en':
      return 'GB';
    case 'es':
      return 'ES';
    case 'it':
      return 'IT';
    case 'nl':
      return 'NL';
    case 'pt':
      return 'PT';
    case 'pl':
      return 'PL';
    default:
      return 'FR';
  }
}

/// Pays par défaut : on privilégie la RÉGION du téléphone (la plus précise pour
/// « mon pays ») ; à défaut on retombe sur le pays typique de la langue de l'app.
String defaultTaxCountryCode({String? region, String? language}) {
  final r = region?.toUpperCase();
  if (r != null && taxCountryByCode(r) != null) return r;
  return _languageToCountry(language);
}

/// Taxe par défaut (1er préréglage du pays par défaut). Sert au tout 1er rapport
/// et au bouton « Réinitialiser ».
TaxConfig defaultTaxConfig({String? region, String? language}) {
  final c = taxCountryByCode(defaultTaxCountryCode(region: region, language: language)) ??
      kTaxCountries.first;
  final p = c.presets.first;
  return TaxConfig(rate: p.rate, label: p.label, mention: p.mention);
}

/// Résout la taxe GLOBALE par défaut depuis la table `settings` ; si rien n'est
/// enregistré (1er lancement), retombe sur [defaultTaxConfig] (région/langue).
TaxConfig resolveGlobalTax(Map<dynamic, dynamic> settings,
    {String? region, String? language}) {
  final fallback = defaultTaxConfig(region: region, language: language);
  final rateStr = settings['tax_rate']?.toString();
  final rate =
      rateStr == null ? null : parseLocalNumber(rateStr);
  if (rate == null) return fallback;
  final lbl = settings['tax_label']?.toString();
  return TaxConfig(
    rate: rate,
    label: (lbl != null && lbl.trim().isNotEmpty) ? lbl : fallback.label,
    mention: settings['tax_mention']?.toString() ?? '',
  );
}

/// Taxe effective d'UN rapport : son override s'il existe, sinon le défaut global.
TaxConfig resolveReportTax(
  Map<dynamic, dynamic> settings, {
  double? reportRate,
  String? reportLabel,
  String? reportMention,
  String? region,
  String? language,
}) {
  if (reportRate == null) {
    return resolveGlobalTax(settings, region: region, language: language);
  }
  final global = resolveGlobalTax(settings, region: region, language: language);
  return TaxConfig(
    rate: reportRate,
    label: (reportLabel != null && reportLabel.trim().isNotEmpty)
        ? reportLabel
        : global.label,
    mention: reportMention ?? '',
  );
}

/// Formate un taux pour l'affichage avec le séparateur décimal de la locale :
/// 20 → « 20 », 5.5 → « 5,5 » (fr/de) / « 5.5 » (en). Pas de zéros superflus.
String formatTaxRate(double rate, {String? locale}) {
  // (2026-10-21) 3 décimales : la TVQ du Québec est à 9,975 % (vu en relecture
  // visuelle : « 9,97 % » sur la facture avec 2 décimales).
  final f = NumberFormat.decimalPattern(locale)
    ..minimumFractionDigits = 0
    ..maximumFractionDigits = 3;
  return f.format(rate);
}
