import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/widgets/clients_icon.dart';
import '../../core/config/app_build.dart';
import '../../core/constants/app_colors.dart';
import '../auth/providers/auth_provider.dart';
import '../subscription/subscription_provider.dart';
import '../../shared/services/local_db_service.dart';
import 'setup_screen.dart';

class MainShell extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;
  const MainShell({required this.navigationShell, super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  // (#13) Anti-double-traitement de la perte d'appartenance à l'équipe.
  bool _handlingTeamRemoval = false;

  // (H) Garde-fou EN MÉMOIRE (survit aux recréations du shell / changements de
  // compte qui vident les prefs) : le popup « récompense rapports » ne s'affiche
  // jamais 2 fois dans la même session de l'app.
  static int _milestoneShownThisSession = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkBroadcast();
      await _checkFeedbackNudge();
      await _checkReportMilestone();
    });
  }

  // (#13) Demande de rejoindre REFUSÉE (ou membre RETIRÉ) en direct : le doc
  // membre est supprimé côté admin → le stream `currentMemberProvider` émet
  // null alors qu'on se croit encore en équipe.
  //
  // ⚠️ CORRECTIF (faux positif) : un `null` peut aussi être TRANSITOIRE — juste
  // après la CRÉATION d'une équipe (le doc membre n'a pas encore propagé) ou un
  // simple null de cache. Réagir aveuglément éjectait à tort le créateur de sa
  // propre équipe (et, via removeLink, cassait le lien Firestore partagé entre
  // ses appareils). On se protège donc par :
  //  1. (appelant) ne réagir QUE si on avait vu un membre RÉEL avant le null ;
  //  2. (ici) CONFIRMATION autoritaire côté SERVEUR que le doc n'existe vraiment
  //     plus avant d'agir ;
  //  3. clearTeam SANS removeLink → si jamais on se trompait, le prochain
  //     démarrage restaure l'équipe (le lien Firestore n'est pas détruit ; un
  //     vrai retrait est de toute façon confirmé/nettoyé par teamState.build).
  Future<void> _onRemovedFromTeam(bool wasPending) async {
    if (_handlingTeamRemoval) return;
    _handlingTeamRemoval = true;
    try {
      final companyId = ref.read(teamStateProvider).valueOrNull?.companyId;
      final uid = ref.read(firebaseUserProvider).valueOrNull?.uid;
      if (companyId == null || uid == null) return;

      // (2) Confirmation SERVEUR : on ne se fie jamais à un null transitoire.
      try {
        final doc = await FirebaseFirestore.instance
            .collection('companies_raptech1')
            .doc(companyId)
            .collection('members_raptech1')
            .doc(uid)
            .get(const GetOptions(source: Source.server));
        if (doc.exists) return; // faux positif : on est toujours membre
        // doc absent → retrait confirmé → on continue.
      } on FirebaseException catch (e) {
        // (#8) PERMISSION_DENIED = on ne peut PLUS lire notre propre doc membre
        // → les règles nous l'interdisent → on n'est PLUS membre → retrait
        // CONFIRMÉ (on continue). Toute autre erreur (réseau, indispo) = prudence.
        if (e.code != 'permission-denied') return;
      } catch (_) {
        return;
      }

      // Confirmé : le doc membre n'existe vraiment plus.
      await ref
          .read(teamStateProvider.notifier)
          .clearTeam(removeLink: false); // (3) ne PAS casser le lien Firestore
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dlg) => AlertDialog(
          icon: Icon(
              wasPending ? Icons.info_outline : Icons.group_off_outlined,
              color: Colors.orange.shade700),
          title:
              Text(wasPending ? 'Demande non acceptée' : 'Retiré de l\'équipe'),
          content: Text(
            wasPending
                ? 'Votre demande pour rejoindre l\'équipe n\'a pas été acceptée '
                    'par l\'administrateur.\n\nVous pouvez réessayer avec un autre '
                    'code d\'invitation quand vous le souhaitez.'
                : 'Vous avez été retiré de l\'équipe par l\'administrateur.\n\n'
                    'Vous pouvez rejoindre une équipe à tout moment avec un code '
                    'd\'invitation.',
          ),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(dlg),
                child: const Text('Compris')),
          ],
        ),
      );
    } finally {
      _handlingTeamRemoval = false;
    }
  }

  Future<void> _checkBroadcast() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('pending_broadcast_id');
    final message = prefs.getString('pending_broadcast_message');
    if (id == null || message == null) return;

    // Clear pending so it won't show again unless gate writes it again
    await prefs.remove('pending_broadcast_id');
    await prefs.remove('pending_broadcast_message');

    if (!mounted) return;
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dlg) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.campaign_outlined, size: 20),
          SizedBox(width: 8),
          Text('Message du développeur'),
        ]),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () async {
              final p = await SharedPreferences.getInstance();
              await p.setBool('dismissed_broadcast_$id', true);
              if (dlg.mounted) Navigator.pop(dlg);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _checkReportMilestone() async {
    try {
      final reports = await LocalDbService().getAllReports();
      final count = reports.length;
      if (count == 0) return;

      final prefs = await SharedPreferences.getInstance();
      final lastShown = prefs.getInt('report_milestone_shown') ?? 0;

      const milestones = [5, 10, 25, 50, 100];
      int? toShow;
      for (final m in milestones) {
        if (count >= m && m > lastShown) toShow = m;
      }
      if (toShow == null || !mounted) return;
      // (H) Déjà montré cette session (même si les prefs ont été vidées par un
      // changement de compte) → on ne réaffiche pas.
      if (toShow <= _milestoneShownThisSession) return;
      _milestoneShownThisSession = toShow;

      await prefs.setInt('report_milestone_shown', toShow);
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return;

      const defaults = {
        5: ('🎉', 'Bon départ !', '5 rapports créés. Vous avez pris un excellent départ — continuez comme ça !'),
        10: ('💪', '10 rapports !', 'L\'habitude est prise. L\'app fait désormais partie de votre workflow.'),
        25: ('🚀', '25 rapports !', 'Vous êtes un utilisateur confirmé. Merci de nous faire confiance.'),
        50: ('⭐', '50 rapports !', 'Impressionnant. Merci d\'utiliser l\'app au quotidien.'),
        100: ('🏆', '100 rapports !', 'Vous êtes un pro. Merci pour votre fidélité — vous faites partie des meilleurs utilisateurs.'),
      };

      final (emoji, title, defaultBody) = defaults[toShow]!;

      // Try to read custom body from Firestore config/app_control
      String body = defaultBody;
      try {
        final doc = await FirebaseFirestore.instance
            .collection('config')
            .doc('app_control')
            .get()
            .timeout(const Duration(seconds: 3));
        final remote = doc.data()?['milestone_${toShow}_message'] as String?;
        if (remote != null && remote.trim().isNotEmpty) body = remote.trim();
      } catch (_) {}
      showDialog(
        context: context,
        builder: (dlg) => AlertDialog(
          title: Text('$emoji $title'),
          content: Text(body),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dlg),
              child: const Text('Merci !'),
            ),
          ],
        ),
      );
    } catch (_) {}
  }

  Future<void> _checkFeedbackNudge() async {
    final prefs = await SharedPreferences.getInstance();
    final show = prefs.getBool('show_feedback_nudge') ?? false;
    if (!show) return;
    await prefs.setBool('show_feedback_nudge', false); // clear so it doesn't repeat
    if (!mounted) return;

    // Small delay so the home screen is fully rendered
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Une idée ou un problème ? Le développeur est à votre écoute — Paramètres → Feedback.',
        ),
        duration: const Duration(seconds: 7),
        action: SnackBarAction(
          label: 'Paramètres',
          onPressed: () => context.go('/settings'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final team = ref.watch(teamStateProvider).valueOrNull;
    final hasTeam = team?.hasTeam ?? false;
    final isPro = ref.watch(effectiveSubscriptionProvider);
    // (O) Demandes d'adhésion en attente → pastille rouge sur l'onglet Équipe.
    final pendingCount = ref.watch(teamPendingCountProvider).valueOrNull ?? 0;

    // (#13) Surveille la disparition EN DIRECT du doc membre (refus / retrait)
    // tant qu'on se croit en équipe → nettoie + prévient l'utilisateur.
    // (1) On ne réagit QUE sur une transition « membre RÉEL → null » : sinon les
    // null TRANSITOIRES (création d'équipe pas encore propagée, cache) éjectaient
    // à tort le créateur de sa propre équipe. La confirmation serveur dans
    // `_onRemovedFromTeam` est le 2e garde-fou.
    ref.listen(currentMemberProvider, (prev, next) {
      if (!(ref.read(teamStateProvider).valueOrNull?.hasTeam ?? false)) return;
      final hadRealMember = prev?.valueOrNull != null;
      if (!hadRealMember) return;
      // (#8) Retrait/refus : soit le doc membre devient `null`, soit la lecture
      // est REFUSÉE (le stream passe en ERREUR car les règles ne nous laissent
      // plus lire). Les deux cas déclenchent la vérif serveur de `_onRemovedFromTeam`.
      final looksRemoved =
          (next.hasValue && next.value == null) || next.hasError;
      if (looksRemoved) {
        final wasPending = prev!.valueOrNull!.isPending;
        _onRemovedFromTeam(wasPending);
      }
    });

    return Scaffold(
      body: widget.navigationShell,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (kEnableSetupBar)
            _SetupStatusBar()
          else if (isPro)
            const _ProBar(),
          NavigationBar(
            selectedIndex: widget.navigationShell.currentIndex,
            onDestinationSelected: (index) {
              // (#3) Avant de changer d'onglet, on ferme tout dialog/feuille
              // encore ouvert au-dessus → l'onglet s'affiche « propre », jamais
              // avec une popup d'un autre contexte restée par-dessus.
              final rootNav = Navigator.of(context, rootNavigator: true);
              if (rootNav.canPop()) rootNav.popUntil((r) => r.isFirst);
              widget.navigationShell.goBranch(
                index,
                initialLocation: index == widget.navigationShell.currentIndex,
              );
            },
            destinations: kEnableNewNavLayout
                // ── Compact 4-tab layout ─────────────────────────────────
                // Rapports · Mon compte · IA · Paramètres
                // Clients accessible via AppBar in Rapports / button in Mon compte.
                // Équipe accessible via toggle inside Rapports (kEnableTeamMergedTab).
                ? [
                    const NavigationDestination(
                      icon: Icon(Icons.assignment_outlined),
                      selectedIcon: Icon(Icons.assignment),
                      label: 'Rapports',
                    ),
                    const NavigationDestination(
                      icon: Icon(Icons.account_circle_outlined),
                      selectedIcon: Icon(Icons.account_circle),
                      label: 'Mon compte',
                    ),
                    const NavigationDestination(
                      icon: Icon(Icons.auto_awesome_outlined),
                      selectedIcon: Icon(Icons.auto_awesome),
                      label: 'IA',
                    ),
                    NavigationDestination(
                      icon: Badge(
                        isLabelVisible: pendingCount > 0,
                        label: Text('$pendingCount'),
                        child: const Icon(Icons.groups_outlined),
                      ),
                      selectedIcon: Badge(
                        isLabelVisible: pendingCount > 0,
                        label: Text('$pendingCount'),
                        child: const Icon(Icons.groups),
                      ),
                      label: 'Équipe',
                    ),
                    const NavigationDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: 'Réglages',
                    ),
                  ]
                // ── Classic layout (5 or 6 tabs) ─────────────────────────
                : [
                    const NavigationDestination(
                      icon: Icon(Icons.assignment_outlined),
                      selectedIcon: Icon(Icons.assignment),
                      label: 'Rapports',
                    ),
                    const NavigationDestination(
                      icon: ClientsIcon(),                 // carte contact + badge « C » (distinct du profil)
                      selectedIcon: ClientsIcon(selected: true),
                      label: 'Clients',
                    ),
                    const NavigationDestination(
                      icon: Icon(Icons.auto_awesome_outlined),
                      selectedIcon: Icon(Icons.auto_awesome),
                      label: 'IA',
                    ),
                    NavigationDestination(
                      icon: hasTeam
                          ? const Icon(Icons.groups_outlined)
                          : const Icon(Icons.groups_2_outlined),
                      selectedIcon: const Icon(Icons.groups),
                      label: 'Équipe',
                    ),
                    const NavigationDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: 'Réglages',
                    ),
                    if (kEnableProfileTab) const NavigationDestination(
                      icon: Icon(Icons.account_circle_outlined),
                      selectedIcon: Icon(Icons.account_circle),
                      label: 'Profil',
                    ),
                  ],
          ),
        ],
      ),
    );
  }
}

// ─── Smart setup/status bar ───────────────────────────────────────────────────

class _SetupStatusBar extends ConsumerWidget {
  const _SetupStatusBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPro = ref.watch(effectiveSubscriptionProvider);
    if (isPro) return const _ProBar();

    final user = ref.watch(firebaseUserProvider).valueOrNull;
    final isLoggedIn = user != null;

    return Material(
      color: isLoggedIn ? AppColors.primary.withValues(alpha: 0.88) : Colors.red.shade700,
      child: InkWell(
        onTap: () => SetupChecklistSheet.show(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 14),
          child: Row(children: [
            Icon(
              isLoggedIn ? Icons.workspace_premium_outlined : Icons.lock_person_outlined,
              color: Colors.white, size: 14,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                isLoggedIn
                    ? 'Passez Pro — exports illimités, signature distante, factures →'
                    : 'Connectez-vous pour toutes les fonctionnalités →',
                style: const TextStyle(color: Colors.white, fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─── PRO bar ──────────────────────────────────────────────────────────────────

class _ProBar extends StatelessWidget {
  const _ProBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.primary,
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: const Text(
        'VERSION PRO',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 2,
        ),
      ),
    );
  }
}
