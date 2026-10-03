import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'app.dart';
import 'shared/services/iap_service.dart';
import 'shared/services/subscription_service.dart';

// Set to true after adding google-services.json (Android) and GoogleService-Info.plist (iOS)
const bool kFirebaseEnabled = true;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Localisation (easy_localization) : charge le cache des traductions.
  await EasyLocalization.ensureInitialized();
  // (i18n dates) Initialise les symboles de date de TOUTES les langues (mois,
  // jours…) → `DateFormat.yMd()/yMMMMd()` s'affichent dans la langue/format du
  // pays. La locale courante est appliquée via `Intl.defaultLocale` (app.dart).
  await initializeDateFormatting();
  if (kFirebaseEnabled) {
    try {
      await Firebase.initializeApp();
    } catch (_) {
      // Falls back to offline mode if Firebase isn't configured yet
    }
  }
  // (dead man's switch) Charge la date de dernière confirmation d'entitlement
  // serveur (anti « Pro éternel offline » > 31 j).
  try {
    await SubscriptionService.loadLastConfirmed();
  } catch (_) {}
  // IAP billing — listen to the store purchase stream for the whole app session.
  try {
    await IapService.instance.init();
  } catch (_) {
    // Store not available (e.g. desktop/web) → IAP simply inert.
  }
  runApp(
    EasyLocalization(
      // Langues prises en charge. Ajouter une langue = ajouter sa Locale ici
      // ET déposer assets/translations/<code>.json. Rien d'autre.
      supportedLocales: const [
        Locale('fr'), Locale('en'), Locale('de'), Locale('es'),
        // 2026-10-03 (v1.2.0) : italien, néerlandais, polonais, portugais (Portugal).
        Locale('it'), Locale('nl'), Locale('pl'), Locale('pt'),
      ],
      path: 'assets/translations',
      // Langue de secours : si la langue du téléphone n'est pas prise en charge,
      // ou si une clé manque dans une traduction → on retombe sur le français.
      fallbackLocale: const Locale('fr'),
      useFallbackTranslations: true,
      // Pas de startLocale → au 1er lancement, easy_localization suit la langue
      // du téléphone (puis mémorise le choix manuel fait dans Réglages).
      child: const ProviderScope(child: TechReportApp()),
    ),
  );
}
