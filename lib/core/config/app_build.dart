// Bump this manually whenever pubspec.yaml version+build number changes.
// pubspec:  version: 1.0.0+1  →  kAppBuildNumber = 1
// const int kAppBuildNumber = 1;
//const int kAppBuildNumber = 6;
// const int kAppBuildNumber = 7;
// const int kAppBuildNumber = 8;
// const int kAppBuildNumber = 9;
const int kAppBuildNumber = 10;

// Unique token baked into this specific build.
// Change this value for each distinct distribution (demo, beta, prod release, etc.)
// To block a build: add its token to the `blocked_tokens` array in config/app_control.
//const String kAppInstanceToken = 'demo_v1_raptech_2026';

//const String kAppInstanceToken = 'demo_v1_raptech_2026_SIMPLE';
// const String kAppInstanceToken = 'demo_v1_raptech_2026_SIMPLE2';
// const String kAppInstanceToken = 'demo_v1_raptech_2026_SIMPLE3'; // apparemtn with canccel system almost ready li rester juste un truc (servvice tesrt machin à faire apreàs et efnin on pourra metter IAP_TRUST_CLIENT =false (car à true ehae elle fait contianc à user et non pas cloud oh wel)
// const String kAppInstanceToken = 'demo_v1_raptech_2026_SIMPLE4'; // apparemtn with canccel system almost ready li rester juste un truc (servvice tesrt machin à faire apreàs et efnin on pourra metter IAP_TRUST_CLIENT =false (car à true ehae elle fait contianc à user et non pas cloud oh wel)
const String kAppInstanceToken = 'demo_v1_raptech_2026_SIMPLE5'; // il manquaqit un api pour que le json VALIDATOR des achats work etc lets see


// How long (in minutes) the instance token check result is cached in SharedPrefs.
// Set to 1 for testing so you don't wait an hour to see the block take effect.
// Set to 60 (or more) for production builds.
const int kInstanceTokenCacheMinutes = 1;

// ─── URLs légales (hébergées) ─────────────────────────────────────────────────
// Affichées dans Réglages → À propos, ET exigées par les stores (Google Play
// demande l'URL Confidentialité dans la fiche ; Apple EXIGE des liens in-app vers
// CGU + Confidentialité pour les apps à abonnement). REMPLIR une fois les pages
// en ligne (sources : legal/POLITIQUE_DE_CONFIDENTIALITE_IAP_2026-06-12.md et
// legal/CGU_IAP_2026-06-12.md). Vide = le lien affiche « bientôt disponible ».
const String kPrivacyPolicyUrl = ''; // ex. https://ton-domaine/confidentialite
const String kTermsUrl = ''; // ex. https://ton-domaine/cgu

// ─── Feature flags ────────────────────────────────────────────────────────────

// Parrainage (referral) — [PAUSED-REFERRAL] 2026-06-08 pivot IAP simple.
// Le parrainage est mis EN PAUSE (pas supprimé). Source unique d'extinction :
// envelopper chaque ENTRÉE UI parrainage par `if (kParrainageEnabled) ...`
// (route /referral, tuiles setup/settings/profil, billing card équipe).
// Remettre à true (+ repasser le billing en Stripe) pour le réactiver.
const bool kParrainageEnabled = false;








// v8: discount is now SLOPE/POOL = €0.21 per active activation, computed by CF.
// kReferralDiscountPercent is no longer used — kept only to avoid compile errors
// in case any old reference was missed. Remove when all references are cleaned up.
const int kReferralDiscountPercent = 0; // DEPRECATED — v8 uses activation model

// Merged Rapports+Équipe tab (toggle équipe À L'INTÉRIEUR de Rapports).
// (simplification 2026-06-03) DÉSACTIVÉ : les rapports d'ÉQUIPE vivent désormais
// dans l'onglet « Équipe » dédié. Rapports = uniquement les rapports perso.
const bool kEnableTeamMergedTab = false;

// Compact 4-tab navigation layout.
// When true:
//   - Équipe tab removed from nav (accessible via the toggle inside Rapports).
//   - Clients tab removed from nav; accessible via "Mes clients" button in
//     Mon compte AND via the AppBar icon in Rapports.
//   - Profile tab moves to position 1 (right after Rapports), renamed "Mon compte".
//   - Result: Rapports · Mon compte · IA · Paramètres · Équipe (onglet dédié).
// (2026-06-03) L'équipe a son propre onglet « Équipe » → kEnableTeamMergedTab=false.
const bool kEnableNewNavLayout = true;

// Setup/onboarding bar above the bottom navigation.
// When true: replaces the thin PRO bar with a smart setup bar that shows the
// most critical pending step for non-PRO users, and collapses to the PRO bar
// once subscribed. Tap opens a checklist bottom sheet.
const bool kEnableSetupBar = true;

// "Profil" tab in the bottom navigation bar.
// When true: adds a 6th "Profil" tab showing the full account setup checklist.
// Both kEnableSetupBar and kEnableProfileTab can be true simultaneously.
const bool kEnableProfileTab = true;

// Section "Debug" dans les Paramètres (seed, pills, overrides…).
// Visible uniquement en build debug ET si ce flag est true. Mettre à false pour
// masquer complètement la section debug (ex. démos clients en build debug).
// (2026-06-11) Laissée à false : on teste en conditions RÉELLES (vrais achats
// testeur + refund Play Console pour repartir frais), pas avec le simulateur.
const bool kEnableDebugSection = false;

// Liste blanche de builds autorisés (allowlist), distincte des blocked_tokens.
// Sert à 2 vérifs : (1) envoi vers un cloud drive, (2) interaction Stripe via le CF.
// Si la liste `accepted_tokens` dans config/app_control est VIDE/absente → tout est
// autorisé (fail-open). Si non-vide → seuls les tokens listés sont acceptés.
// Le token de CE build est kAppInstanceToken (ci-dessus).
