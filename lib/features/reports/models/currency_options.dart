import 'package:intl/intl.dart';

/// ─── Devise des factures/devis ──────────────────────────────────────────────
///
/// Les MONTANTS qu'un artisan facture à SES clients ne sont pas forcément en € :
/// un plombier britannique facture en £, un américain en $, un suisse en CHF…
/// Avant, l'app codait « € » en dur partout dans le PDF. Ici on rend la devise
/// **dérivée du pays du téléphone** (avec override possible dans les Réglages),
/// et on formate les montants **selon la locale** (séparateur décimal + milliers
/// + place du symbole : « 1 234,50 € » en fr/de/es, « £1,234.50 » en en-GB).
///
/// ⚠️ N'a AUCUN rapport avec les prix d'abonnement (IAP) : ceux-là sont déjà
/// localisés automatiquement par Google Play / App Store selon le pays du store.

/// Symbole par code ISO-4217 (sous-ensemble des marchés visés).
const Map<String, String> kCurrencySymbol = {
  'EUR': '€',
  'GBP': '£',
  'USD': '\$',
  'CHF': 'CHF',
  'CAD': 'CA\$',
  'AUD': 'A\$',
  'NZD': 'NZ\$',
  'PLN': 'zł',
  'SEK': 'kr',
  'DKK': 'kr',
  'NOK': 'kr',
  'INR': '₹',
};

/// Ordre d'affichage dans le sélecteur.
const List<String> kCurrencyCodes = [
  'EUR', 'GBP', 'USD', 'CHF', 'CAD', 'AUD', 'NZD', 'PLN', 'SEK', 'DKK', 'NOK', 'INR',
];

/// Variable GLOBALE de devise courante (même principe que `Intl.defaultLocale`) :
/// posée par les écrans qui lisent les Réglages, lue par les helpers de format
/// (formulaire). Le PDF, lui, reçoit la devise en paramètre explicite.
String appCurrencyCode = 'EUR';

const Map<String, String> _countryCurrency = {
  'FR': 'EUR', 'BE': 'EUR', 'LU': 'EUR', 'DE': 'EUR', 'AT': 'EUR', 'NL': 'EUR',
  'ES': 'EUR', 'IT': 'EUR', 'PT': 'EUR', 'IE': 'EUR', 'FI': 'EUR', 'GR': 'EUR',
  'CH': 'CHF', 'GB': 'GBP', 'US': 'USD', 'CA': 'CAD', 'AU': 'AUD', 'NZ': 'NZD',
  'PL': 'PLN', 'SE': 'SEK', 'DK': 'DKK', 'NO': 'NOK', 'IN': 'INR',
};

String _languageCurrency(String? language) {
  switch (language) {
    case 'en':
      return 'GBP';
    case 'pl':
      return 'PLN';
    default:
      return 'EUR'; // fr/de/es/it/nl/pt… = zone euro par défaut
  }
}

/// Devise par défaut : région du téléphone d'abord, repli langue de l'app.
String defaultCurrencyCode({String? region, String? language}) {
  final r = region?.toUpperCase();
  if (r != null && _countryCurrency.containsKey(r)) return _countryCurrency[r]!;
  return _languageCurrency(language);
}

/// Devise effective depuis la table `settings` (`currency_code`), sinon défaut.
String resolveCurrencyCode(Map<dynamic, dynamic> settings,
    {String? region, String? language}) {
  final c = settings['currency_code']?.toString();
  if (c != null && c.trim().isNotEmpty && kCurrencySymbol.containsKey(c)) {
    return c;
  }
  return defaultCurrencyCode(region: region, language: language);
}

String currencySymbolOf(String code) => kCurrencySymbol[code] ?? code;

/// « EUR (€) » pour le sélecteur.
String currencyDisplay(String code) => '$code (${currencySymbolOf(code)})';

/// Formate un montant : symbole + séparateurs selon la locale active.
/// Ex. (EUR, fr) → « 1 234,50 € » ; (GBP, en) → « £1,234.50 ».
String formatMoney(num amount, {String? code, String? locale}) {
  final c = code ?? appCurrencyCode;
  final f = NumberFormat.currency(
    locale: locale, // null → Intl.defaultLocale (langue de l'app)
    symbol: currencySymbolOf(c),
    decimalDigits: 2,
  );
  return f.format(amount);
}

/// (2026-10-03) Quantité lisible : « 1 » au lieu de « 1.0 », séparateur décimal
/// de la langue (« 1,5 » en français, « 1.5 » en anglais).
String formatQuantity(num q, {String? locale}) =>
    NumberFormat.decimalPattern(locale ?? Intl.defaultLocale).format(q);

/// Séparateur « libellé : valeur » selon la langue : espace avant « : » en
/// français uniquement (« Adresse : … »), « Address: … » ailleurs. (2026-10-14)
String labelSep({String? locale}) =>
    (locale ?? Intl.defaultLocale ?? 'fr').startsWith('fr') ? ' : ' : ': ';

/// Lit un nombre TAPÉ par l'utilisateur, quelle que soit la langue (2026-10-14) :
/// « 12,5 », « 12.5 », « 1 234,50 », « 1.234,50 », « 1,234.50 », « 1'234.50 ».
/// Avant : seule « , » → « . » était gérée ; un séparateur de milliers rendait
/// le nombre illisible → prix 0 € en silence. Retourne null si illisible.
double? parseLocalNumber(String? input) {
  if (input == null) return null;
  var s = input.trim().replaceAll(RegExp(r"[\s'\u2019]"), '');
  if (s.isEmpty) return null;
  final lastComma = s.lastIndexOf(',');
  final lastDot = s.lastIndexOf('.');
  if (lastComma >= 0 && lastDot >= 0) {
    // Les deux : le DERNIER est le séparateur décimal, l'autre = milliers.
    final dec = lastComma > lastDot ? ',' : '.';
    s = s.replaceAll(dec == ',' ? '.' : ',', '').replaceAll(dec, '.');
  } else if (lastComma >= 0) {
    // Une seule virgule = décimale ; plusieurs = milliers (« 1,234,567 »).
    s = ','.allMatches(s).length > 1 ? s.replaceAll(',', '') : s.replaceAll(',', '.');
  } else if ('.'.allMatches(s).length > 1) {
    s = s.replaceAll('.', ''); // « 1.234.567 »
  }
  return double.tryParse(s);
}

/// Arrondi au centime, « au plus proche » (2026-10-14). Le petit décalage
/// évite que 1,005 (= 1,00499999… en binaire) soit arrondi à 1,00.
/// Les factures additionnent des lignes DÉJÀ arrondies (comme les logiciels de
/// facturation) : avant, 3 × (1,5 × 3,33) donnait « 14,99 + 3,00 = 17,98 ».
double roundMoney(num v) => ((v * 100) + (v >= 0 ? 1e-7 : -1e-7)).round() / 100;
