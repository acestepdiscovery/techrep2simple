// Cloud Function base URL — SINGLE SOURCE OF TRUTH.
//
// 2026-06-08 pivot IAP simple : nouvelle CF propre `stripe-raptech1simple`
// (l'ancienne `stripe-raptech1` est laissée de côté avec ses env vars accumulées).
// Tous les services (subscription, iap, team, referral, ai, notification,
// identity_audit) pointent ici → pour changer d'URL, UNE seule ligne à modifier.
//
// Format Cloud Run : https://{service}-{numéro_projet}.{région}.run.app
// ⚠️ APRÈS avoir déployé le nouveau service, VÉRIFIE l'URL exacte dans la console
//    Cloud Run et corrige cette ligne si elle diffère.
const String kCfBaseUrl =
    'https://stripe-raptech1simple-503650417046.europe-west1.run.app';
