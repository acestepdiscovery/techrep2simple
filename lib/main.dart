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
  await initializeDateFormatting('fr_FR', null);
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
  runApp(const ProviderScope(child: TechReportApp()));
}
