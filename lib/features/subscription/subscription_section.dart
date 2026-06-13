import 'dart:io' show Platform;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/services/subscription_service.dart';
import '../../shared/services/referral_service.dart';
import '../../shared/services/team_service.dart';
import '../team/models/team_member_model.dart';
import '../referral/providers/referral_provider.dart';
import '../auth/providers/auth_provider.dart';
import 'subscription_provider.dart';
import 'paywall_bottom_sheet.dart';

// ─── Subscription section ─────────────────────────────────────────────────────

/// Périmètre d'affichage de la section abonnement :
///  • personal → Réglages (abo SOLO uniquement) ;
///  • team     → onglet Équipe (abo ÉQUIPE uniquement).
enum SubScope { personal, team }

class SubscriptionSection extends ConsumerStatefulWidget {
  final SubScope scope;
  const SubscriptionSection({super.key, this.scope = SubScope.personal});

  @override
  ConsumerState<SubscriptionSection> createState() =>
      _SubscriptionSectionState();
}

class _SubscriptionSectionState extends ConsumerState<SubscriptionSection> {
  bool _loadingPortal = false;
  bool _restoring = false;

  Future<void> _restoreSubscription() async {
    setState(() => _restoring = true);
    try {
      final user = ref.read(firebaseUserProvider).valueOrNull;
      if (user == null) return;
      // Force a Firestore read — the stream will update automatically
      final doc = await FirebaseFirestore.instance
          .collection('users_raptech1')
          .doc(user.uid)
          .get();
      final sub = doc.data()?['subscription'] as Map<String, dynamic>?;
      if (!mounted) return;
      if (sub != null && sub['status'] == 'active') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Abonnement récupéré !'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Aucun abonnement actif trouvé. Reconnectez-vous avec l\'email utilisé lors du paiement.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  Future<void> _openPortal({String? target}) async {
    setState(() => _loadingPortal = true);
    try {
      // [PAUSED-STRIPE] IAP : la gestion de l'abonnement (annulation, moyen de
      // paiement) se fait dans les réglages du store, pas via le portail Stripe.
      final url = Platform.isIOS
          ? 'https://apps.apple.com/account/subscriptions'
          : 'https://play.google.com/store/account/subscriptions';
      await SubscriptionService.openUrl(url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingPortal = false);
    }
  }

  // [PAUSED-STRIPE] (4f) Ancien dialog Stripe « ajouter/réduire sièges » (slider +
  // proration Stripe via /modify-team-seats). Remplacé par « Changer de palier »
  // (paywall IAP). Conservé pour réactivation éventuelle si Stripe revient.
  // ignore: unused_element
  Future<void> _manageSeats(
      BuildContext context, int currentSeats, String companyId) async {
    final messenger = ScaffoldMessenger.of(context);
    final pool = ref.read(teamPoolCreditsProvider).valueOrNull ?? 0;
    final periodEnd = ref.read(companySubscriptionProvider).valueOrNull.periodEnd;
    final now = DateTime.now();
    final int? daysRemaining = (periodEnd != null && periodEnd.isAfter(now))
        ? periodEnd.difference(now).inDays.clamp(1, 31)
        : null;
    final currentMonthly =
        ReferralService.computePreviewPrice(pool, nSeats: currentSeats);

    String money(double v) => '${v.toStringAsFixed(2).replaceAll('.', ',')} €';

    int seats = currentSeats < 2 ? 2 : currentSeats;
    bool busy = false;
    String? err;

    await showDialog<void>(
      context: context,
      builder: (dlg) => StatefulBuilder(
        builder: (dlg, setSt) {
          final newMonthly =
              ReferralService.computePreviewPrice(pool, nSeats: seats);
          final isIncrease = seats > currentSeats;
          final isDecrease = seats < currentSeats;
          double? prorataNow;
          if (isIncrease && daysRemaining != null) {
            prorataNow = (newMonthly - currentMonthly) * (daysRemaining / 30.0);
            if (prorataNow < 0) prorataNow = 0;
          }

          Widget row(String l, String v, {bool bold = false}) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                        child: Text(l, style: const TextStyle(fontSize: 12.5))),
                    Text(v,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight:
                                bold ? FontWeight.bold : FontWeight.normal,
                            color: bold ? AppColors.primary : null)),
                  ],
                ),
              );

          return AlertDialog(
            title: const Text('Gérer les sièges'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton.filledTonal(
                        onPressed: (busy || seats <= 2)
                            ? null
                            : () => setSt(() => seats--),
                        icon: const Icon(Icons.remove),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text('$seats',
                            style: const TextStyle(
                                fontSize: 30, fontWeight: FontWeight.bold)),
                      ),
                      IconButton.filledTonal(
                        onPressed: (busy || seats >= 50)
                            ? null
                            : () => setSt(() => seats++),
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  Text('Minimum 2 sièges',
                      style:
                          TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                  const SizedBox(height: 12),
                  // ── Aperçu du prix ───────────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        row('Actuel · $currentSeats sièges',
                            '${money(currentMonthly)}/mois'),
                        row('Nouveau · $seats sièges',
                            '${money(newMonthly)}/mois',
                            bold: true),
                        if (pool > 0)
                          Text('(parrainages externes inclus : −${money(pool * 0.21)})',
                              style: TextStyle(
                                  fontSize: 10, color: Colors.grey.shade500)),
                        if (isIncrease) ...[
                          const Divider(height: 14),
                          row(
                            'À payer maintenant (prorata)',
                            prorataNow != null
                                ? '≈ ${money(prorataNow)}'
                                : 'au prorata',
                          ),
                          Text(
                            'Sièges disponibles tout de suite, puis '
                            '${money(newMonthly)}/mois.',
                            style: TextStyle(
                                fontSize: 10.5, color: Colors.grey.shade600),
                          ),
                        ] else if (isDecrease) ...[
                          const Divider(height: 14),
                          Text(
                            'Effectif au prochain cycle — rien à payer '
                            'maintenant (sans remboursement).',
                            style: TextStyle(
                                fontSize: 10.5, color: Colors.grey.shade600),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // (réduction sièges) Désactivation de membres EN LIGNE : si on
                  // veut réduire sous le nombre de membres actifs, on liste les
                  // membres à désactiver directement ici (le stream se met à jour
                  // → le bloc disparaît quand il y a assez de sièges).
                  if (seats < currentSeats)
                    StreamBuilder<List<TeamMemberModel>>(
                      stream: TeamService().streamMembers(companyId),
                      builder: (_, snap) {
                        final members = snap.data ?? [];
                        final active = members
                            .where((m) => m.active && !m.isPending)
                            .toList();
                        if (active.length <= seats) {
                          return const SizedBox.shrink();
                        }
                        final removable =
                            active.where((m) => m.role != 'admin').toList();
                        final toFree = active.length - seats;
                        return Container(
                          margin: const EdgeInsets.only(top: 10),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${active.length} membres actifs. Désactivez '
                                '$toFree membre(s) pour passer à $seats sièges :',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    color: Colors.orange.shade900),
                              ),
                              const SizedBox(height: 6),
                              ...removable.map((m) => Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 1),
                                    child: Row(children: [
                                      Expanded(
                                        child: Text(
                                          m.displayName.isNotEmpty
                                              ? m.displayName
                                              : m.email,
                                          style: const TextStyle(fontSize: 12),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () => TeamService()
                                            .setMemberActive(
                                                companyId, m.uid, false),
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8),
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          foregroundColor: Colors.red.shade700,
                                        ),
                                        child: const Text('Désactiver',
                                            style: TextStyle(fontSize: 12)),
                                      ),
                                    ]),
                                  )),
                              if (removable.isEmpty)
                                Text(
                                  'Aucun membre désactivable (hors vous-même).',
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.grey.shade600),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  if (err != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        err!.trim().isEmpty
                            ? 'Échec de la modification. Réessayez.'
                            : err!,
                        style:
                            TextStyle(color: Colors.red.shade700, fontSize: 12),
                      ),
                    ),
                    // Réduction bloquée par des membres actifs → action directe.
                    if (err!.contains('membres actifs') ||
                        err!.contains('Désactivez')) ...[
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(dlg);
                            context.go('/team-tab');
                          },
                          icon: const Icon(Icons.group_outlined, size: 16),
                          label: const Text('Gérer / désactiver des membres'),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(dlg),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: (busy || seats == currentSeats)
                    ? null
                    : () async {
                        setSt(() {
                          busy = true;
                          err = null;
                        });
                        try {
                          await SubscriptionService.modifyTeamSeats(
                              companyId, seats);
                          if (dlg.mounted) Navigator.pop(dlg);
                          messenger.showSnackBar(SnackBar(
                            content: Text('Sièges mis à jour : $seats'),
                            backgroundColor: Colors.green,
                          ));
                        } catch (e) {
                          debugPrint('[seats] modify error: $e');
                          setSt(() {
                            busy = false;
                            err = e.toString().replaceFirst('Exception: ', '');
                          });
                        }
                      },
                child: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Confirmer'),
              ),
            ],
          );
        },
      ),
    );
  }

  // (#9) Alerte explicative (sans erreur rouge) avant d'ouvrir les réglages
  // d'abonnement du STORE pour l'équipe — déclenchée par l'icône ⚙️ à droite de « Actif ».
  void _showTeamPortalInfo() {
    showDialog<void>(
      context: context,
      builder: (dlg) => AlertDialog(
        icon: const Icon(Icons.manage_accounts_outlined,
            color: AppColors.primary),
        title: const Text('Gérer l\'abonnement équipe'),
        content: const Text(
          'La gestion se fait dans les réglages d\'abonnement de votre store '
          '(App Store / Google Play). Vous pourrez :\n\n'
          '•  changer le moyen de paiement,\n'
          '•  voir l\'historique de facturation,\n'
          '•  résilier l\'abonnement.\n\n'
          'L\'accès Pro de vos techniciens reste actif tant que l\'abonnement '
          'n\'est pas résilié.',
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dlg), child: const Text('Fermer')),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(dlg);
              _openPortal(target: 'company');
            },
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Ouvrir les réglages d\'abonnement'),
          ),
        ],
      ),
    );
  }

  // (paiement) Tuile « paiement échoué » → permet de mettre à jour la carte
  // (ouvre le portail Stripe) pour rétablir l'accès une fois le paiement réussi.
  Widget _pastDueTile(String target) {
    return Column(
      children: [
        ListTile(
          leading: Icon(Icons.error_outline, color: Colors.orange.shade800),
          title: const Text('Paiement échoué'),
          subtitle: const Text(
            'Votre dernier paiement n\'a pas abouti — accès Pro suspendu. '
            'Mettez à jour votre moyen de paiement : l\'accès est rétabli '
            'automatiquement dès que le paiement réussit.',
            style: TextStyle(fontSize: 12),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _loadingPortal ? null : () => _openPortal(target: target),
              icon: _loadingPortal
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.credit_card_outlined),
              label: const Text('Mettre à jour le paiement'),
              style:
                  FilledButton.styleFrom(backgroundColor: Colors.orange.shade800),
            ),
          ),
        ),
      ],
    );
  }

  // (paiement équipe) Membre non-admin : le paiement de l'équipe a échoué →
  // il ne peut pas le réparer lui-même (c'est le responsable de l'équipe qui
  // paie), mais il garde une porte de sortie : prendre un abo solo.
  Widget _teamPaymentIssueMemberTile() {
    return Column(
      children: [
        ListTile(
          leading: Icon(Icons.error_outline, color: Colors.orange.shade800),
          title: const Text('Accès équipe suspendu'),
          subtitle: const Text(
            'Le paiement de l\'abonnement de votre équipe a échoué — votre accès '
            'Pro via l\'équipe est suspendu. Le responsable de l\'équipe (celui '
            'qui l\'a créée et gère son abonnement) doit mettre à jour la carte.',
            style: TextStyle(fontSize: 12),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => PaywallBottomSheet.show(context),
              icon: const Icon(Icons.workspace_premium_outlined, size: 18),
              label: const Text('Ou prendre un abonnement solo (accès immédiat)'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _freeTile(BuildContext context) {
    final user = ref.read(firebaseUserProvider).valueOrNull;
    final isTeam = widget.scope == SubScope.team;
    // (#9b) Un membre NON-ADMIN ne peut pas abonner l'équipe (c'est le rôle du
    // responsable). On lui cache le bouton « Abonner l'équipe » trompeur.
    final isTeamAdmin = ref.watch(teamStateProvider).valueOrNull?.isAdmin ?? false;
    final canSubscribeTeam = !isTeam || isTeamAdmin;
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.workspace_premium_outlined,
              color: Colors.grey),
          title: Text(isTeam ? 'Abonnement équipe' : 'Mon abonnement'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Gratuit · ${SubscriptionService.freeMonthlyExports} exports PDF/mois',
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 2),
              Text(
                canSubscribeTeam
                    ? '⭐ Exports ILLIMITÉS à partir de 2,50 €/mois'
                    : 'Seul le responsable de l\'équipe peut souscrire l\'abonnement.',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          trailing: canSubscribeTeam
              ? FilledButton(
                  onPressed: () => PaywallBottomSheet.show(
                    context,
                    initialForTeam: isTeam,
                  ),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                  child: Text(isTeam ? 'Abonner l\'équipe' : 'S\'abonner'),
                )
              : Icon(Icons.lock_outline, size: 18, color: Colors.grey.shade400),
        ),
        if (user != null && !isTeam)
          ListTile(
            leading: _restoring
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.restore, color: AppColors.primary),
            title: const Text('Récupérer mon abonnement'),
            subtitle: const Text(
              'Reconnectez-vous avec le compte utilisé lors du paiement.',
              style: TextStyle(fontSize: 11),
            ),
            trailing: const Icon(Icons.chevron_right,
                size: 18, color: Colors.grey),
            onTap: _restoring ? null : _restoreSubscription,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Debug override (kDebugMode only)
    if (kDebugMode) {
      final override = ref.watch(debugSubOverrideProvider);
      if (override == false) return _freeTile(context);
    }

    // Not logged in → free tier immediately (no Firebase stream to wait for)
    final user = ref.watch(firebaseUserProvider).valueOrNull;
    if (user == null) return _freeTile(context);

    final subAsync = ref.watch(subscriptionProvider);
    final companySubAsync = ref.watch(companySubscriptionProvider);
    final team = ref.watch(teamStateProvider).valueOrNull;

    final loading = subAsync.isLoading || companySubAsync.isLoading;
    if (loading) {
      return const ListTile(
        leading: Icon(Icons.workspace_premium, color: AppColors.primary),
        title: Text('Mon abonnement'),
        trailing: SizedBox(
          width: 16, height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final userSub = subAsync.valueOrNull;
    final companySub = companySubAsync.valueOrNull;
    // Flags RÉELS (pour les cross-sells) + flags SCOPÉS (pour l'affichage selon
    // l'onglet : Réglages = solo, onglet Équipe = équipe).
    final realCompanyActive = companySub.isActive;
    final realPersonalActive = userSub.isActive;
    final isCompanyActive = realCompanyActive && widget.scope == SubScope.team;
    final isPersonalActive =
        realPersonalActive && widget.scope == SubScope.personal;

    // (paiement) past_due = échec de paiement, Stripe réessaie. Scopé aussi.
    final personalPastDue =
        userSub?['status'] == 'past_due' && widget.scope == SubScope.personal;
    final companyPastDue =
        companySub?['status'] == 'past_due' && widget.scope == SubScope.team;

    if (!isCompanyActive && !isPersonalActive) {
      // L'utilisateur peut réparer SON propre paiement (perso).
      if (personalPastDue) return _pastDueTile('personal');
      // Paiement équipe en échec : seul l'ADMIN peut le réparer ; un membre
      // non-admin reçoit un message « contactez votre administrateur » (sinon
      // le bouton cible un abo perso inexistant → erreur).
      if (companyPastDue) {
        return (team?.isAdmin ?? false)
            ? _pastDueTile('company')
            : _teamPaymentIssueMemberTile();
      }
      return _freeTile(context);
    }

    // Abonnement actif — company prend priorité sur perso
    final activeSub = isCompanyActive ? companySub : userSub;
    final isCompany = isCompanyActive;
    final label = isCompany ? 'Équipe · ${activeSub.planLabel}' : activeSub.planLabel;
    final end = activeSub.periodEnd;
    final isLifetime = activeSub.isLifetime;
    final canManage = !isCompany
        ? activeSub.isRecurring
        : (team?.isAdmin ?? false) && activeSub.isRecurring;

    String statusText = label;
    if (!isLifetime && end != null) {
      final d = end.day.toString().padLeft(2, '0');
      final m = end.month.toString().padLeft(2, '0');
      // (annulation) Si le renouvellement auto est coupé (flag écrit par la CF sur
      // la notif store CANCELED), on affiche « expire le… » au lieu de
      // « renouvellement le… » — l'accès reste actif jusqu'à cette date.
      final canceled = activeSub?['cancel_at_period_end'] == true;
      statusText += canceled
          ? ' · expire le $d/$m/${end.year} (renouvellement annulé)'
          : ' · renouvellement le $d/$m/${end.year}';
    }
    // (double Pro) On affiche l'équipe (prioritaire) MAIS l'utilisateur a AUSSI un
    // abo SOLO perso actif → on l'indique. Les deux couvrent des choses différentes :
    // équipe = rapports d'équipe ; solo = rapports perso (sous son identité).
    if (isCompany && userSub.isActive) {
      statusText += '\n➕ Abonnement solo perso aussi actif (couvre vos rapports perso)';
    }

    return Column(
      children: [
        ListTile(
          leading: Icon(
            isCompany ? Icons.group : Icons.workspace_premium,
            color: AppColors.primary,
          ),
          title: Text(isCompany ? 'Abonnement équipe' : 'Mon abonnement'),
          subtitle: Text(statusText,
              style: const TextStyle(fontSize: 12, color: Colors.black87)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Text(
                  'Actif',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade700),
                ),
              ),
              // (#9) Équipe : ⚙️ à droite de « Actif » → alerte explicative puis
              // portail Stripe (remplace la tuile « Gérer l'abonnement équipe »).
              if (isCompany && canManage) ...[
                const SizedBox(width: 2),
                _loadingPortal
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: SizedBox(
                            width: 18,
                            height: 18,
                            child:
                                CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : IconButton(
                        icon: const Icon(Icons.settings_outlined, size: 20),
                        tooltip: 'Gérer l\'abonnement équipe',
                        onPressed: _showTeamPortalInfo,
                      ),
              ],
            ],
          ),
        ),
        // (UX) Membre non-admin : l'abo équipe est géré par l'admin → on le dit
        // clairement plutôt que d'afficher un écran muet.
        if (isCompany && !(team?.isAdmin ?? false))
          ListTile(
            dense: true,
            leading: Icon(Icons.shield_outlined,
                size: 18, color: Colors.grey.shade500),
            title: const Text('Géré par le responsable de votre équipe',
                style: TextStyle(fontSize: 12.5)),
            subtitle: const Text(
              'Votre accès Pro est fourni par l\'équipe. La facturation et les '
              'sièges sont gérés par le responsable de l\'équipe (celui qui l\'a '
              'créée).',
              style: TextStyle(fontSize: 11),
            ),
          ),
        // (#9) Pour l'ÉQUIPE, cette tuile est remplacée par l'icône ⚙️ sur la
        // ligne « Actif » ci-dessus → on ne l'affiche QUE pour le solo (perso).
        if (canManage && !isCompany)
          ListTile(
            leading: _loadingPortal
                ? const SizedBox(
                    width: 24, height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.manage_accounts_outlined,
                    color: AppColors.primary),
            title: const Text('Gérer l\'abonnement'),
            subtitle: const Text('Changer carte, factures, annuler',
                style: TextStyle(fontSize: 12)),
            trailing:
                const Icon(Icons.open_in_new, size: 16, color: Colors.grey),
            onTap: _loadingPortal
                ? null
                : () => _openPortal(target: 'personal'),
          ),
        // (#7+8) Changer de palier (admin équipe). Remplace l'ancien slider Stripe
        // « ajouter/réduire sièges » : en IAP on change de PALIER (l'upgrade/
        // downgrade + prorata est géré par le store, via le paywall équipe).
        // (#6) Affiché même SANS abonnement, mais GRISÉ → continuité visuelle.
        if (isCompany && (team?.isAdmin ?? false))
          ListTile(
            enabled: activeSub.isRecurring,
            leading: Icon(Icons.event_seat_outlined,
                color: activeSub.isRecurring
                    ? AppColors.primary
                    : Colors.grey.shade400),
            title: const Text('Changer de palier'),
            subtitle: Text(
              activeSub.isRecurring
                  ? () {
                      final n = ref.watch(companySeatLimitProvider) ?? 0;
                      return 'Palier actuel · jusqu\'à $n membres — passer au-dessus / en-dessous';
                    }()
                  : 'Activez un abonnement équipe pour choisir un palier',
              style: const TextStyle(fontSize: 12),
            ),
            trailing:
                const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
            onTap: activeSub.isRecurring
                ? () => PaywallBottomSheet.show(context, initialForTeam: true)
                : null,
          ),
        // (6a) Si l'utilisateur a AUSSI un autre abonnement actif, on le montre.
        if (isCompanyActive && isPersonalActive)
          ListTile(
            dense: true,
            leading: const Icon(Icons.workspace_premium_outlined,
                color: Colors.grey),
            title: const Text('Abonnement personnel'),
            subtitle: Text(
              '${userSub.planLabel} · également actif',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: userSub.isRecurring
                ? TextButton(
                    // (6a) Gère/annule l'abo PERSO indépendamment de l'équipe.
                    onPressed: _loadingPortal
                        ? null
                        : () => _openPortal(target: 'personal'),
                    child: const Text('Gérer'),
                  )
                : null,
          ),
        // (simplification) Cross-sell « Passer à un plan équipe » RETIRÉ des
        // Réglages (= solo pur) : l'abonnement équipe se prend dans l'onglet
        // Équipe. Conservé en commentaire au cas où.
        // if (widget.scope == SubScope.personal &&
        //     realPersonalActive &&
        //     !realCompanyActive &&
        //     (team?.hasTeam ?? false))
        //   ListTile(
        //     leading: const Icon(Icons.groups_outlined, color: Colors.orange),
        //     title: const Text('Passer à un plan équipe'),
        //     subtitle: const Text(
        //       'Donnez accès Pro à tous vos techniciens',
        //       style: TextStyle(fontSize: 12),
        //     ),
        //     trailing: const Icon(Icons.arrow_forward_ios,
        //         size: 14, color: Colors.orange),
        //     onTap: () => PaywallBottomSheet.show(context, initialForTeam: true),
        //   ),
        // (4.3) Membre d'équipe Pro SANS abo solo → proposer un abo solo (pour
        // des rapports perso). Cross-sell : flags RÉELS + seulement périmètre équipe.
        if (widget.scope == SubScope.team &&
            realCompanyActive &&
            !realPersonalActive &&
            (team?.hasTeam ?? false))
          ListTile(
            leading:
                Icon(Icons.person_outline, color: Colors.indigo.shade400),
            title: const Text('Ajouter un abonnement solo'),
            subtitle: const Text(
              'Optionnel — pour créer des rapports PERSO sous votre propre nom '
              'd\'entreprise (hors équipe) et basculer entre vos 2 profils.',
              style: TextStyle(fontSize: 12),
            ),
            trailing: Icon(Icons.arrow_forward_ios,
                size: 14, color: Colors.indigo.shade400),
            onTap: () => PaywallBottomSheet.show(context),
          ),
      ],
    );
  }
}
