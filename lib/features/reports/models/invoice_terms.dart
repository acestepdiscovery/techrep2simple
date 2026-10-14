import 'tax_options.dart';

/// Conditions de paiement / mentions légales imprimées sur la facture (2026-10-14).
///
/// Pré-remplies UNIQUEMENT pour la France, où elles sont obligatoires
/// (Service-Public, « Mentions obligatoires sur une facture ») — en français
/// quelle que soit la langue de l'app (une facture française se rédige en
/// français). Ailleurs : vide, l'utilisateur écrit ce que son pays exige.
/// Tout reste modifiable dans Réglages.
const String kInvoiceTermsFR =
    'Paiement à réception de facture. Escompte pour paiement anticipé : néant.\n'
    'En cas de retard de paiement : pénalités au taux de trois fois le taux '
    "d'intérêt légal et, pour les clients professionnels, indemnité forfaitaire "
    'pour frais de recouvrement de 40 €.\n'
    'Nature des opérations : prestations de services et fournitures associées.';

String defaultInvoiceTerms({String? region, String? language}) =>
    defaultTaxCountryCode(region: region, language: language) == 'FR'
        ? kInvoiceTermsFR
        : '';
