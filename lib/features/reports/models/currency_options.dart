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
