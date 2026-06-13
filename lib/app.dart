import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/config/app_build.dart';
import 'core/theme/app_theme.dart';
import 'features/ai/screens/ai_screen.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/subscription/subscription_provider.dart';
import 'features/settings/providers/settings_provider.dart';
import 'shared/services/referral_service.dart';
import 'features/auth/screens/auth_screen.dart';
import 'features/clients/screens/clients_list_screen.dart';
import 'features/gate/gate_screen.dart';
import 'features/main/main_shell.dart';
import 'features/main/setup_screen.dart';
import 'features/onboarding/onboarding_intro_screen.dart';
import 'features/onboarding/welcome_screen.dart';
import 'features/reports/models/report_model.dart';
import 'features/reports/screens/client_history_screen.dart';
import 'features/reports/screens/create_report_screen.dart';
import 'features/reports/screens/report_detail_screen.dart';
import 'features/reports/screens/reports_list_screen.dart';
import 'features/reports/screens/archive_screen.dart';
import 'features/settings/screens/settings_screen.dart';
import 'features/settings/screens/profile_screen.dart';
import 'features/referral/screens/referral_screen.dart';
import 'features/team/screens/team_dashboard_screen.dart';
import 'features/team/screens/team_tab_screen.dart';
import 'features/team/screens/team_setup_screen.dart';
import 'shared/services/local_db_service.dart';
import 'shared/services/notification_service.dart';

final _router = GoRouter(
  initialLocation: '/gate',
  errorBuilder: (context, state) => const _RedirectHome(),
  routes: [
    // ── Screens outside the bottom-nav shell ──────────────────────────────
    GoRoute(path: '/gate', builder: (_, __) => const GateScreen()),
    GoRoute(path: '/welcome', builder: (_, __) => const WelcomeScreen()),
    GoRoute(path: '/onboarding-intro', builder: (_, __) => const OnboardingIntroScreen()),
    GoRoute(
      path: '/auth',
      builder: (_, state) => AuthScreen(
        startInLoginMode: state.uri.queryParameters['mode'] == 'login',
      ),
    ),
    GoRoute(
      path: '/team-setup',
      builder: (_, state) => TeamSetupScreen(
        initialInviteCode: state.uri.queryParameters['code'],
      ),
    ),
    // Deep-link entry point: raptech://invite?code=ABCDEF
    GoRoute(
      path: '/invite',
      redirect: (_, state) {
        final code = state.uri.queryParameters['code'] ?? '';
        return '/team-setup?code=${Uri.encodeComponent(code)}';
      },
    ),
    GoRoute(path: '/referral', builder: (_, __) => const ReferralScreen()),
    GoRoute(path: '/archive', builder: (_, __) => const ArchiveScreen()),
    GoRoute(path: '/profile-account', builder: (_, __) => const ProfileScreen()),

    // ── Shell with bottom navigation bar ──────────────────────────────────
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          MainShell(navigationShell: navigationShell),
      branches: kEnableNewNavLayout
          // ── Compact 4-tab layout ─────────────────────────────────────────
          // Branch 0 Rapports | Branch 1 Mon compte | Branch 2 IA | Branch 3 Paramètres
          // /clients and /team-dashboard are standalone routes (outside the shell).
          ? [
              StatefulShellBranch(routes: [
                GoRoute(
                  path: '/home',
                  builder: (_, __) => const ReportsListScreen(),
                ),
                GoRoute(
                  path: '/create-report',
                  builder: (_, state) => CreateReportScreen(
                    reportId: state.uri.queryParameters['id'],
                    templatePreset: state.extra is ReportPreset
                        ? state.extra as ReportPreset
                        : null,
                  ),
                ),
                GoRoute(
                  path: '/report/:id',
                  builder: (_, state) =>
                      ReportDetailScreen(reportId: state.pathParameters['id']!),
                ),
              ]),
              StatefulShellBranch(routes: [
                GoRoute(
                  path: '/profile',
                  builder: (_, __) => const SetupScreen(),
                ),
              ]),
              StatefulShellBranch(routes: [
                GoRoute(
                  path: '/ai',
                  builder: (_, __) => const AiScreen(),
                ),
              ]),
              // Branch 3 — Équipe (onglet dédié : tableau de bord ou état vide)
              StatefulShellBranch(routes: [
                GoRoute(
                  path: '/team-tab',
                  builder: (_, __) => const TeamTabScreen(),
                ),
              ]),
              // Branch 4 — Paramètres
              StatefulShellBranch(routes: [
                GoRoute(
                  path: '/settings',
                  builder: (_, __) => const SettingsScreen(),
                ),
              ]),
            ]
          // ── Classic layout (5 or 6 tabs) ─────────────────────────────────
          : [
              // Branch 0 — Rapports
              StatefulShellBranch(routes: [
                GoRoute(
                  path: '/home',
                  builder: (_, __) => const ReportsListScreen(),
                ),
                GoRoute(
                  path: '/create-report',
                  builder: (_, state) => CreateReportScreen(
                    reportId: state.uri.queryParameters['id'],
                    templatePreset: state.extra is ReportPreset
                        ? state.extra as ReportPreset
                        : null,
                  ),
                ),
                GoRoute(
                  path: '/report/:id',
                  builder: (_, state) =>
                      ReportDetailScreen(reportId: state.pathParameters['id']!),
                ),
              ]),
              // Branch 1 — Clients
              StatefulShellBranch(routes: [
                GoRoute(
                  path: '/clients',
                  builder: (_, __) => const ClientsListScreen(),
                ),
                GoRoute(
                  path: '/client-history/:clientId',
                  builder: (_, state) => ClientHistoryScreen(
                    clientId: state.pathParameters['clientId']!,
                    clientName: state.extra as String? ?? '',
                  ),
                ),
              ]),
              // Branch 2 — IA
              StatefulShellBranch(routes: [
                GoRoute(
                  path: '/ai',
                  builder: (_, __) => const AiScreen(),
                ),
              ]),
              // Branch 3 — Équipe
              StatefulShellBranch(routes: [
                GoRoute(
                  path: '/team-dashboard',
                  builder: (_, __) => const TeamDashboardScreen(),
                ),
              ]),
              // Branch 4 — Paramètres
              StatefulShellBranch(routes: [
                GoRoute(
                  path: '/settings',
                  builder: (_, __) => const SettingsScreen(),
                ),
              ]),
              // Branch 5 — Profil (setup checklist + account info)
              if (kEnableProfileTab) StatefulShellBranch(routes: [
                GoRoute(
                  path: '/profile',
                  builder: (_, __) => const SetupScreen(),
                ),
              ]),
            ],
    ),
    // ── Standalone routes for new nav layout ──────────────────────────────
    // When kEnableNewNavLayout=true, Clients and Team are not nav branches.
    // They remain full-screen routes accessible via buttons/AppBar icons.
    if (kEnableNewNavLayout) ...[
      GoRoute(
        path: '/clients',
        builder: (_, __) => const ClientsListScreen(),
      ),
      GoRoute(
        path: '/client-history/:clientId',
        builder: (_, state) => ClientHistoryScreen(
          clientId: state.pathParameters['clientId']!,
          clientName: state.extra as String? ?? '',
        ),
      ),
      GoRoute(
        path: '/team-dashboard',
        builder: (_, __) => const TeamDashboardScreen(),
      ),
    ],
  ],
);

Widget _webLayout(BuildContext context, Widget? child) {
  return Scaffold(
    backgroundColor: const Color(0xFFCFD8DC),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(0),
          child: child!,
        ),
      ),
    ),
  );
}

class _RedirectHome extends StatefulWidget {
  const _RedirectHome();
  @override
  State<_RedirectHome> createState() => _RedirectHomeState();
}

class _RedirectHomeState extends State<_RedirectHome> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go('/home');
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class TechReportApp extends ConsumerStatefulWidget {
  const TechReportApp({super.key});

  @override
  ConsumerState<TechReportApp> createState() => _TechReportAppState();
}

class _TechReportAppState extends ConsumerState<TechReportApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    NotificationService().initialize(_router);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // On sign-in: if the UID changed (different account on same device), wipe local
  // data so the new user doesn't see the previous user's reports or settings.
  Future<void> _handleAccountSwitch(String newUid) async {
    final prefs = await SharedPreferences.getInstance();
    final storedUid = prefs.getString('last_signed_in_uid');
    if (storedUid != null && storedUid != newUid) {
      // Different account — clear local SQLite reports + relevant prefs
      debugPrint('[AccountSwitch] uid changed $storedUid -> $newUid : '
          'clearing identity (settings) + prefs, KEEPING reports (2.1)');
      // (2.1) On GARDE les rapports/clients locaux (contamination de docs
      // acceptée sur appareil de confiance) ; on n'efface que l'identité.
      await LocalDbService().clearUserData(keepReports: true);
      // Clear settings that belong to the previous user.
      // (fix L) 'team_intent' = intention « créer/rejoindre une équipe » posée
      // depuis la page de garde AVANT l'inscription. L'account-switch se déclenche
      // pile à l'inscription → sans préserver cette clé, elle était effacée avant
      // que l'écran d'auth la lise → on retombait sur /home au lieu de /team-setup.
      final keysToKeep = {
        'onboarding_done', 'app_mode', 'last_signed_in_uid', 'team_intent',
      };
      for (final key in prefs.getKeys()) {
        if (keysToKeep.contains(key)) continue;
        // (2.5) Le quota d'exports gratuits est au niveau APPAREIL (anti-fraude :
        // empêche de réinitialiser les 5 exports en changeant de compte). On le
        // PRÉSERVE au changement de compte. Les Pro = illimités, pas concernés.
        if (key.startsWith('pdf_export_count_') ||
            key.startsWith('exported_ids_')) {
          continue;
        }
        await prefs.remove(key);
      }
      // (anti-contamination) La BASE locale est vidée, mais les providers
      // Riverpod gardaient en mémoire les valeurs du compte précédent (ex.
      // nom d'entreprise). On les invalide pour forcer une relecture propre.
      ref.invalidate(settingsProvider);
      ref.invalidate(teamStateProvider);
      ref.invalidate(subscriptionProvider);
      ref.invalidate(companySubscriptionProvider);
    }
    await prefs.setString('last_signed_in_uid', newUid);
  }

  // When the app returns to the foreground (e.g. after Stripe checkout in browser),
  // force-refresh the subscription Firestore streams so the UI updates immediately
  // without requiring a full app restart.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(subscriptionProvider);
      ref.invalidate(companySubscriptionProvider);
      // Ré-établit les streams équipe au retour au premier plan : si un stream
      // a été coupé (ex. PERMISSION_DENIED pendant l'attente d'approbation), la
      // transition pending→active se reflète sans avoir à redémarrer l'app.
      ref.invalidate(teamStateProvider);
      ref.invalidate(currentMemberProvider);
      ref.invalidate(memberActiveProvider);
      // (parrainage) Confirme les activations matures à chaque ouverture de
      // l'app (pas seulement sur la page Parrainage) → règle l'asymétrie sans
      // dépendre d'un cron. THROTTLE 30 min pour économiser le free tier.
      // [PAUSED-REFERRAL] inactif tant que le parrainage est en pause (IAP simple).
      if (kParrainageEnabled) _maybeRefreshReferralOnResume();
    }
  }

  Future<void> _maybeRefreshReferralOnResume() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt('last_resume_referral_refresh') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - last < 30 * 60 * 1000) return; // throttle 30 min
      await prefs.setInt('last_resume_referral_refresh', now);
      await ReferralService.refreshStatus();
    } catch (_) {
      // best-effort
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(firebaseUserProvider, (prev, next) {
      final uid = next.valueOrNull?.uid;
      if (uid != null) {
        NotificationService().initializeForUser(uid);
        _handleAccountSwitch(uid);
      }
    });

    return MaterialApp.router(
      title: 'Compte Rendu Technique IA',
      theme: AppTheme.light,
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
      builder: kIsWeb ? _webLayout : null,
    );
  }
}
