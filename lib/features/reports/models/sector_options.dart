import 'package:easy_localization/easy_localization.dart';

// ─────────────────────────────────────────────────────────────────────────────
// (i18n « méthode B ») Options des menus déroulants des champs spécifiques par
// secteur.
//
// PRINCIPE : on STOCKE une CLÉ STABLE (`copper`) — jamais le libellé affiché —
// et on AFFICHE la traduction via `.tr()`. Exactement comme l'enum
// SectorTemplate. Conséquence : un rapport (vieux comme neuf) s'affiche
// toujours dans la langue courante, partout (écran, PDF, TXT, HTML).
//
// Les valeurs en base d'AVANT cette bascule étaient les libellés FRANÇAIS
// (« Cuivre »…). La migration DB v10 (LocalDbService) les convertit une fois
// en clés via `sectorOptionFromFrench`. Le dropdown reste tolérant en filet :
// si une valeur stockée n'est pas reconnue, on l'affiche/garde telle quelle
// (zéro plantage), et `sectorValueLabel` la rend brute (champ libre non traduit).
// ─────────────────────────────────────────────────────────────────────────────

/// Clé d'option STOCKÉE  ->  clé de traduction (`sf_opt_*` dans les JSON).
const Map<String, String> sectorOptionLabelKey = {
  // plomberie · type_tuyauterie
  'pvc': 'sf_opt_pvc',
  'copper': 'sf_opt_copper',
  'steel': 'sf_opt_steel',
  'pe': 'sf_opt_pe',
  'pex': 'sf_opt_pex',
  'other': 'sf_opt_other',
  // incendie · type_agent
  'co2': 'sf_opt_co2',
  'powder_abc': 'sf_opt_powder_abc',
  'water_spray': 'sf_opt_water_spray',
  'foam': 'sf_opt_foam',
  'halon': 'sf_opt_halon',
  // maintenance · type_entretien
  'preventive': 'sf_opt_preventive',
  'corrective': 'sf_opt_corrective',
  'predictive': 'sf_opt_predictive',
  'improvement': 'sf_opt_improvement',
  // nettoyage · frequence
  'once': 'sf_opt_once',
  'daily': 'sf_opt_daily',
  'weekly': 'sf_opt_weekly',
  'monthly': 'sf_opt_monthly',
  // transport · type_vehicule
  'truck': 'sf_opt_truck',
  'van': 'sf_opt_van',
  'trailer': 'sf_opt_trailer',
  'tractor': 'sf_opt_tractor',
  'bus': 'sf_opt_bus',
  'utility': 'sf_opt_utility',
  // transport · type_intervention
  'servicing': 'sf_opt_servicing',
  'repair': 'sf_opt_repair',
  'technical_inspection': 'sf_opt_technical_inspection',
  'accident': 'sf_opt_accident',
  'breakdown': 'sf_opt_breakdown',
};

/// Ancien libellé FRANÇAIS (stocké avant i18n)  ->  clé stable.
/// Utilisé UNE FOIS par la migration DB v10. La conversion est idempotente :
/// après migration la valeur est une clé (`copper`), absente de cette table,
/// donc une 2e passe ne fait rien.
const Map<String, String> sectorOptionFromFrench = {
  'PVC': 'pvc',
  'Cuivre': 'copper',
  'Acier': 'steel',
  'PE': 'pe',
  'PEX': 'pex',
  'Autre': 'other',
  'CO₂': 'co2',
  'Poudre ABC': 'powder_abc',
  'Eau pulvérisée': 'water_spray',
  'Mousse': 'foam',
  'Halon': 'halon',
  'Préventif': 'preventive',
  'Curatif': 'corrective',
  'Prédictif': 'predictive',
  'Amélioratif': 'improvement',
  'Unique': 'once',
  'Quotidien': 'daily',
  'Hebdomadaire': 'weekly',
  'Mensuel': 'monthly',
  'Camion': 'truck',
  'Camionnette': 'van',
  'Remorque': 'trailer',
  'Tracteur': 'tractor',
  'Bus': 'bus',
  'Utilitaire': 'utility',
  'Entretien': 'servicing',
  'Réparation': 'repair',
  'Contrôle technique': 'technical_inspection',
  'Accident': 'accident',
  'Panne': 'breakdown',
};

/// Clés de champs qui sont des MENUS DÉROULANTS (valeur ∈ liste d'options).
/// La migration ne convertit QUE ces champs → un champ LIBRE (remarques, n° de
/// série…) qui contiendrait par hasard « Acier » n'est jamais touché.
const Set<String> sectorDropdownFieldKeys = {
  'type_tuyauterie',
  'type_agent',
  'type_entretien',
  'frequence',
  'type_vehicule',
  'type_intervention',
};

/// Affiche la valeur d'un champ secteur : si c'est une clé d'option connue →
/// libellé traduit dans la langue courante ; sinon (champ libre, ou vieille
/// valeur non migrée) → valeur brute (jamais de plantage).
String sectorValueLabel(String stored) {
  final tk = sectorOptionLabelKey[stored];
  return tk != null ? tk.tr() : stored;
}
