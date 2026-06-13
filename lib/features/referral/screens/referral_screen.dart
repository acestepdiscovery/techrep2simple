import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/services/referral_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../subscription/subscription_provider.dart';
import '../models/activation_model.dart';
import '../providers/referral_provider.dart';

/// Page dédiée au parrainage — ouverte depuis Paramètres et Mon compte.
class ReferralScreen extends ConsumerWidget {
  const ReferralScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(firebaseUserProvider).valueOrNull?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Parrainage'),
        actions: [
          // (#11) Duplique le bouton de partage de la tuile « Mon code de
          // parrainage » directement dans l'AppBar (accès immédiat).
          if (uid != null)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Partager mon code',
              onPressed: () async {
                final code = await ReferralService.getOrCreateCode(uid);
                shareReferralCode(code);
              },
            ),
        ],
      ),
      body: uid == null
          ? _NotLoggedIn()
          : ReferralBody(uid: uid),
    );
  }
}

// (#11) Partage du code de parrainage — réutilisé par l'icône AppBar et la
// tuile « Mon code de parrainage » (un seul texte, jamais désynchronisé).
void shareReferralCode(String code) {
  Share.share(
    'Rejoins-moi sur Compte Rendu Technique Pro !\n'
    'Avant de t\'abonner, entre mon code :\n\n'
    '$code\n\n'
    'Si nous restons tous les deux abonnés, nous aurons chacun une réduction '
    'tous les mois.\n\n'
    'Pour l\'ajouter : Paramètres → Parrainage → Entrer un code.',
  );
}

class _NotLoggedIn extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text('Connectez-vous pour accéder au parrainage',
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.push('/auth'),
              child: const Text('Se connecter'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Corps du parrainage — réutilisable.
class ReferralBody extends ConsumerStatefulWidget {
  final String uid;
  const ReferralBody({super.key, required this.uid});
  @override
  ConsumerState<ReferralBody> createState() => _ReferralBodyState();
}

class _ReferralBodyState extends ConsumerState<ReferralBody> {
  String? _myCode;
  bool _loadingCode = true;
  String? _pendingInviterName;
  bool _hasFrozenInviter = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Confirme côté serveur les activations matures (délai écoulé) sans attendre
    // le renouvellement Stripe — puis les streams Firestore reflètent le changement.
    ReferralService.refreshStatus();
    try {
      final code = await ReferralService.getOrCreateCode(widget.uid);
      final frozen = await ReferralService.hasInviter(widget.uid);
      // Le nom à afficher : parrain gelé (après paiement) OU parrain en attente.
      // Les deux sont lus sur NOTRE propre doc (règles Firestore).
      final name = frozen
          ? await ReferralService.getInviterName(widget.uid)
          : await ReferralService.getPendingInviterName(widget.uid);
      if (mounted) {
        setState(() {
          _myCode = code;
          _pendingInviterName = name;
          _hasFrozenInviter = frozen;
          _loadingCode = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingCode = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPro = ref.watch(effectiveSubscriptionProvider);

    if (_loadingCode) {
      return const Center(child: CircularProgressIndicator());
    }

    final circleAsync = ref.watch(myCircleProvider);
    final activeCount = ref.watch(activeActivationsCountProvider);
    final toFloor = ref.watch(activationsToFloorProvider);
    final nextPrice = ref.watch(nextPricePreviewProvider);
    // En équipe, la réduction s'applique sur la facture ÉQUIPE (pool), pas sur un
    // prix solo individuel → on n'affiche PAS la carte "votre prix 3 €/mois" solo.
    final inTeam = ref.watch(teamStateProvider).valueOrNull?.hasTeam ?? false;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Explainer ────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              Colors.deepPurple.shade50,
              Colors.deepPurple.shade100.withValues(alpha: 0.4),
            ]),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.card_giftcard, color: Colors.deepPurple.shade400, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Invitez un proche — dès qu\'il s\'abonne, vous payez '
                    'tous les deux moins chaque mois où vous restez abonnés.',
                    style: TextStyle(fontSize: 12.5, color: Colors.deepPurple.shade900)),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 14),

        // ── Code applied state (pending or frozen inviter) ──────────────
        if (_pendingInviterName != null || _hasFrozenInviter) ...[
          _AppliedCodeCard(
            inviterName: _pendingInviterName,
            isFrozen: _hasFrozenInviter,
            canChange: !_hasFrozenInviter && !isPro,
            onChange: () => _showEnterCode(),
          ),
          const SizedBox(height: 14),
        ],

        // ── Subscribed: full referral dashboard ───────────────────────
        if (isPro) ...[
          // Membre/admin d'équipe → bandeau équipe (pas le prix solo trompeur)
          if (inTeam)
            _TeamReferralBanner()
          else
            _PriceNextMonthCard(nextPrice: nextPrice, activeCount: activeCount),
          const SizedBox(height: 14),

          Text('Mon cercle',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
          // (P) Clarifie où s'applique la réduction (sinon « −0,21 » ambigu).
          Text(
            inTeam
                ? 'Réductions appliquées selon votre choix (Solo / Équipe).'
                : 'Réductions appliquées à votre abonnement solo.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 6),
          circleAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) => const Text('Erreur de chargement du cercle.'),
            data: (circle) => circle.isEmpty
                ? _CircleEmpty(onInvite: _shareCode)
                : _CircleList(circle: circle, myUid: widget.uid),
          ),
          const SizedBox(height: 14),

          // Barre de progression "solo" uniquement hors équipe
          if (!inTeam) ...[
            if (toFloor > 0)
              _ProgressCard(activeCount: activeCount, toFloor: toFloor)
            else
              _FloorReached(),
            const SizedBox(height: 14),
          ],
        ] else ...[
          // ── Not subscribed: teaser + ladder ──────────────────────────
          _SubscribeTeaser(onSubscribe: () {
            // ferme la page et laisse l'utilisateur ouvrir le paywall
            context.pop();
          }),
          const SizedBox(height: 14),
          _PriceLadder(),
          const SizedBox(height: 14),
        ],

        // ── My code + share ───────────────────────────────────────────
        _InviteCard(code: _myCode, onShare: _shareCode),
        // (E) Pas encore Pro : on garde le code visible (incite à partager) mais
        // on prévient qu'il faut un abonnement pour que les parrainages s'activent.
        if (!isPro) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(children: [
              Icon(Icons.info_outline, size: 15, color: Colors.orange.shade800),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Partagez déjà votre code ! Vos parrainages s\'activeront '
                  'dès que vous serez abonné (et la personne aussi).',
                  style:
                      TextStyle(fontSize: 11, color: Colors.orange.shade900),
                ),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 8),
        // (parrainage) Choix de l'abo soutenu (si on a solo + équipe).
        const _ReferralTargetCard(),

        // ── Enter a code (only if no inviter yet) ─────────────────────
        if (_pendingInviterName == null && !_hasFrozenInviter)
          _EnterCodeTile(uid: widget.uid, onSuccess: (name) {
            setState(() => _pendingInviterName = name);
          }),
        // (2.6) Simulation du prix solo selon le nombre de parrainages.
        const SizedBox(height: 16),
        const _PriceSimulationCard(),
        const SizedBox(height: 24),
      ],
    );
  }

  void _showEnterCode() {
    showDialog<void>(
      context: context,
      builder: (_) => _EnterCodeDialog(
        uid: widget.uid,
        onSuccess: (name) => setState(() => _pendingInviterName = name),
      ),
    );
  }

  void _shareCode() {
    final code = _myCode;
    if (code == null) return;
    shareReferralCode(code);
  }
}

// ── Simulation du prix solo selon le nb de parrainages (2.6) ──────────────────

class _PriceSimulationCard extends StatelessWidget {
  const _PriceSimulationCard();

  @override
  Widget build(BuildContext context) {
    final floor = ReferralService.kFloor;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.show_chart, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          const Text('Simulation : votre prix solo',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: AppColors.primary)),
        ]),
        const SizedBox(height: 4),
        Text(
          'Chaque parrainage actif réduit votre abonnement, jusqu\'au plancher.',
          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 10),
        ...List.generate(9, (n) {
          final price = ReferralService.computePreviewPrice(n);
          final atFloor = price <= floor + 0.001;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              SizedBox(
                width: 96,
                child: Text('$n parrainage${n > 1 ? 's' : ''}',
                    style: const TextStyle(fontSize: 12.5)),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: (n / 8).clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation(
                        atFloor ? Colors.green : AppColors.primary),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${price.toStringAsFixed(2).replaceAll('.', ',')} €',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: atFloor ? Colors.green.shade700 : AppColors.primary),
              ),
            ]),
          );
        }),
        const SizedBox(height: 4),
        Text(
          'Plancher : ${floor.toStringAsFixed(2).replaceAll('.', ',')} €/mois (réduction max).',
          style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
        ),
      ]),
    );
  }
}

// ── Applied code card ─────────────────────────────────────────────────────────

class _AppliedCodeCard extends StatelessWidget {
  final String? inviterName;
  final bool isFrozen;
  final bool canChange;
  final VoidCallback onChange;
  const _AppliedCodeCard({
    required this.inviterName,
    required this.isFrozen,
    required this.canChange,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(children: [
        Icon(Icons.verified_outlined, color: Colors.green.shade600, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              isFrozen
                  ? 'Vous êtes parrainé par ${inviterName ?? 'un proche'}'
                  : 'Code de ${inviterName ?? 'votre parrain'} enregistré ✓',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: Colors.green.shade800),
            ),
            const SizedBox(height: 2),
            Text(
              isFrozen
                  ? 'Réduction active tant que vous restez abonnés tous les deux.'
                  : 'La réduction s\'activera après votre premier paiement.',
              style: TextStyle(fontSize: 11, color: Colors.green.shade700),
            ),
            const SizedBox(height: 4),
            Text(
              '👇 Vous pouvez aussi inviter vos propres proches ci-dessous — '
              'chaque filleul actif réduit encore votre prix.',
              style: TextStyle(fontSize: 11, color: Colors.green.shade800,
                  fontWeight: FontWeight.w500),
            ),
          ]),
        ),
        if (canChange)
          TextButton(
            onPressed: onChange,
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
            child: const Text('Changer', style: TextStyle(fontSize: 12)),
          ),
      ]),
    );
  }
}

// ── Price next month ──────────────────────────────────────────────────────────

class _PriceNextMonthCard extends StatelessWidget {
  final double nextPrice;
  final int activeCount;
  const _PriceNextMonthCard({required this.nextPrice, required this.activeCount});

  @override
  Widget build(BuildContext context) {
    final hasDiscount = nextPrice < ReferralService.kBase - 0.001;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Icon(Icons.euro_outlined, color: AppColors.primary, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Votre prix dès le mois prochain',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            Row(children: [
              if (hasDiscount) ...[
                Text('3,00 €',
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade500,
                        decoration: TextDecoration.lineThrough)),
                const SizedBox(width: 6),
              ],
              Text('${nextPrice.toStringAsFixed(2).replaceAll('.', ',')} €/mois',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.primary)),
            ]),
          ]),
        ),
        if (activeCount > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('$activeCount actif${activeCount > 1 ? 's' : ''}',
                style: TextStyle(
                    fontSize: 11, color: Colors.green.shade700, fontWeight: FontWeight.w600)),
          ),
      ]),
    );
  }
}

// ── Circle ──────────────────────────────────────────────────────────────────--

class _CircleEmpty extends StatelessWidget {
  final VoidCallback onInvite;
  const _CircleEmpty({required this.onInvite});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 32, color: Colors.grey.shade400),
          const SizedBox(height: 6),
          Text('Votre cercle est vide',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 4),
          Text('Invitez vos premiers proches pour réduire votre facture',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: onInvite,
            icon: const Icon(Icons.share, size: 16),
            label: const Text('Partager mon code'),
          ),
        ],
      ),
    );
  }
}

class _CircleList extends StatelessWidget {
  final List<ActivationModel> circle;
  final String myUid;
  const _CircleList({required this.circle, required this.myUid});

  // (synchro) Gère tous les délais CF : 15 j (prod) → date ; minutes/0 (test) →
  // « aujourd'hui à HH:mm » / « demain à HH:mm ». Toujours juste, sans valeur en dur.
  static String _fmt(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final hm = '${d.hour.toString().padLeft(2, '0')}h'
        '${d.minute.toString().padLeft(2, '0')}';
    if (day == today) return 'aujourd\'hui à $hm';
    if (day == today.add(const Duration(days: 1))) return 'demain à $hm';
    // « le » inclus ici (pour « s'active le 18/06 ») mais pas pour aujourd'hui/
    // demain (« s'active aujourd'hui » — pas « s'active le aujourd'hui »).
    return 'le ${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: circle.map((act) {
        final isActive = act.isActive;
        final isPending = act.isPending;
        final name = act.otherDisplayName(myUid);
        final icon = isActive
            ? Icons.check_circle_outline
            : isPending
                ? Icons.hourglass_top_outlined
                : Icons.do_not_disturb_on_outlined;
        final color = isActive
            ? Colors.green.shade600
            : isPending
                ? Colors.amber.shade700
                : Colors.grey.shade400;
        final subtitle = isActive
            ? '−0,21 €/mois · actif'
            : isPending
                ? act.confirmAfter != null
                    // (synchro) On affiche la VRAIE date d'activation (timestamp
                    // confirm_after posé par la CF) → toujours juste, peu importe
                    // le délai configuré côté serveur. Plus de « 15j » en dur.
                    ? 'En attente · s\'active ${_fmt(act.confirmAfter!)} (délai de sécurité)'
                    : 'En attente de confirmation'
                : 'Lien inactif (abonnement suspendu)';
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, color: color, size: 22),
          title: Text(name.isEmpty ? 'Utilisateur' : name, style: const TextStyle(fontSize: 13)),
          subtitle: Text(subtitle, style: TextStyle(fontSize: 11, color: color)),
        );
      }).toList(),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  final int activeCount;
  final int toFloor;
  const _ProgressCard({required this.activeCount, required this.toFloor});

  @override
  Widget build(BuildContext context) {
    const maxActivations = 7;
    final progress = (activeCount / maxActivations).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.deepPurple.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.deepPurple.shade100),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: Colors.deepPurple.shade100,
            valueColor: AlwaysStoppedAnimation(Colors.deepPurple.shade400),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '+$toFloor parrainage${toFloor > 1 ? 's' : ''} actif${toFloor > 1 ? 's' : ''} '
          'pour atteindre 1,50 €/mois (−50%)',
          style: TextStyle(fontSize: 11, color: Colors.deepPurple.shade700),
        ),
      ]),
    );
  }
}

class _FloorReached extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        Icon(Icons.celebration_outlined, color: Colors.green.shade600, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text('Tarif minimum atteint — vous payez 1,50 €/mois !',
              style: TextStyle(
                  fontSize: 12, color: Colors.green.shade700, fontWeight: FontWeight.w500)),
        ),
      ]),
    );
  }
}

// Affiché à la place de la carte "prix solo" quand l'utilisateur est en équipe.
class _TeamReferralBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.groups_outlined, color: AppColors.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Vous faites partie d\'une équipe',
                  style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.primary)),
              const SizedBox(height: 2),
              Text(
                'Vos invitations de personnes extérieures réduisent la facture de '
                'votre équipe. Le détail (prix par siège + pool) est dans « Mon équipe ».',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
              ),
            ]),
          ),
        ]),
        // (S6) Teaser de récompense : apparaît à partir de kRewardTeaserMin
        // parrainages, jusqu'au palier kRewardMilestone (récompense spéciale).
        Consumer(builder: (context, ref, _) {
          final pool = ref.watch(teamPoolCreditsProvider).valueOrNull ?? 0;
          final reached =
              (ref.watch(teamReward100Provider).valueOrNull ?? false) ||
                  pool >= ReferralService.kRewardMilestone;
          const goal = ReferralService.kRewardMilestone;
          if (reached) {
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '🎉 Objectif $goal parrainages atteint — récompense spéciale '
                'débloquée pour votre équipe !',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange.shade800),
              ),
            );
          }
          if (pool >= ReferralService.kRewardTeaserMin) {
            return Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '🎁 Objectif équipe : $goal parrainages actifs → récompense '
                    'spéciale (surprise).',
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary),
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (pool / goal).clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: Colors.grey.shade200,
                      valueColor:
                          const AlwaysStoppedAnimation(AppColors.primary),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text('$pool / $goal parrainages actifs',
                      style: TextStyle(
                          fontSize: 10.5, color: Colors.grey.shade600)),
                ],
              ),
            );
          }
          return const SizedBox.shrink();
        }),
        const SizedBox(height: 4),
        // (4e) Accès direct à « Mon équipe » → ouvre l'ONGLET Équipe de la barre
        // du bas (barre de nav visible), au lieu d'une page plein écran isolée.
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => context.go('/team-tab'),
            icon: const Icon(Icons.groups_outlined, size: 16),
            label: const Text('Voir mon équipe'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Choix de l'abo soutenu par les parrainages (si solo + équipe) ──────────────

class _ReferralTargetCard extends ConsumerWidget {
  const _ReferralTargetCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // N'apparaît QUE si l'utilisateur a les DEUX abos Pro (sinon la réduction va
    // automatiquement sur l'unique compte Pro).
    if (!ref.watch(hasBothProSubsProvider)) return const SizedBox.shrink();
    final target = ref.watch(referralTargetProvider).valueOrNull ?? 'team';
    final teamName =
        (ref.watch(teamStateProvider).valueOrNull?.companyName ?? 'mon équipe')
            .trim();

    Future<void> set(String t) async {
      if (t == target) return;
      final messenger = ScaffoldMessenger.of(context);
      try {
        await ReferralService.setReferralTarget(t);
        messenger.showSnackBar(SnackBar(
          content: Text(t == 'solo'
              ? 'Vos PROCHAINS parrainages réduiront votre abonnement SOLO.'
              : 'Vos PROCHAINS parrainages réduiront l\'abonnement de votre ÉQUIPE.'),
          backgroundColor: Colors.green,
        ));
      } catch (e) {
        messenger.showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ));
      }
    }

    Widget seg(String value, String label) {
      final selected = target == value;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: selected ? null : () => set(value),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : Colors.grey.shade700,
                )),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Vous avez un abo solo ET équipe',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.amber.shade900)),
          const SizedBox(height: 2),
          Text(
              'Choisissez quel abonnement vos PROCHAINS parrainages réduisent '
              '(les parrainages déjà actifs gardent leur affectation) :',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            padding: const EdgeInsets.all(3),
            child: Row(children: [
              seg('team', teamName),
              const SizedBox(width: 3),
              seg('solo', 'Mon solo'),
            ]),
          ),
        ],
      ),
    );
  }
}

// ── Invite card ───────────────────────────────────────────────────────────────

class _InviteCard extends StatelessWidget {
  final String? code;
  final VoidCallback onShare;
  const _InviteCard({required this.code, required this.onShare});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        const Icon(Icons.qr_code_2_outlined, color: AppColors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Mon code de parrainage', style: TextStyle(fontSize: 11, color: Colors.black54)),
            Text(code ?? '—',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    color: AppColors.primary)),
          ]),
        ),
        IconButton(
          icon: const Icon(Icons.copy_outlined, size: 20),
          tooltip: 'Copier',
          onPressed: code == null
              ? null
              : () {
                  Clipboard.setData(ClipboardData(text: code!));
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Code copié !')));
                },
        ),
        IconButton(
          icon: const Icon(Icons.share_outlined, size: 20),
          tooltip: 'Partager',
          onPressed: code == null ? null : onShare,
        ),
      ]),
    );
  }
}

// ── Enter code tile + dialog ──────────────────────────────────────────────────

class _EnterCodeTile extends StatelessWidget {
  final String uid;
  final ValueChanged<String> onSuccess;
  const _EnterCodeTile({required this.uid, required this.onSuccess});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.redeem_outlined),
      title: const Text('Entrer le code d\'un parrain'),
      subtitle: const Text('Doit être fait avant votre premier abonnement',
          style: TextStyle(fontSize: 11)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => _EnterCodeDialog(uid: uid, onSuccess: onSuccess),
      ),
    );
  }
}

class _EnterCodeDialog extends StatefulWidget {
  final String uid;
  final ValueChanged<String> onSuccess;
  const _EnterCodeDialog({required this.uid, required this.onSuccess});
  @override
  State<_EnterCodeDialog> createState() => _EnterCodeDialogState();
}

class _EnterCodeDialogState extends State<_EnterCodeDialog> {
  final _ctrl = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(children: [
        Icon(Icons.redeem_outlined, color: AppColors.primary),
        SizedBox(width: 8),
        Text('Code de parrainage'),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text(
          'Entrez le code d\'un proche abonné. Dès votre premier paiement, '
          'vous serez liés et paierez tous les deux moins.',
          style: TextStyle(fontSize: 13, color: Colors.black54),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: 'Code (6 caractères)',
            border: const OutlineInputBorder(),
            isDense: true,
            errorText: _error,
            errorMaxLines: 5,   // laisse le message s'afficher en entier
          ),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: _loading ? null : _apply,
          child: _loading
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Appliquer'),
        ),
      ],
    );
  }

  Future<void> _apply() async {
    final code = _ctrl.text.trim().toUpperCase();
    if (code.isEmpty) return;
    setState(() => _loading = true);
    try {
      final name = await ReferralService.applyCode(code);
      if (mounted) {
        Navigator.pop(context);
        widget.onSuccess(name);
        // (e5) Message clair : la réduction s'applique AU MOIS PROCHAIN.
        await showDialog(
          context: context,
          builder: (dlg) => AlertDialog(
            icon: const Icon(Icons.check_circle_outline,
                color: Colors.green, size: 40),
            title: Text('Parrainage de $name enregistré'),
            content: const Text(
              'La réduction s\'applique DÈS LE MOIS PROCHAIN.\n\n'
              'Ce mois-ci, votre 1er paiement reste au plein tarif (3,00 €). '
              'À partir du 2e mois, votre parrainage réduit votre facture — '
              'et c\'est récurrent.\n\n'
              'Ce délai laisse le temps de confirmer votre abonnement (sécurité, '
              'gestion des remboursements).',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(dlg),
                child: const Text('J\'ai compris'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }
}

// ── Teaser + ladder for non-subscribers ────────────────────────────────────────

class _SubscribeTeaser extends StatelessWidget {
  final VoidCallback onSubscribe;
  const _SubscribeTeaser({required this.onSubscribe});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        Icon(Icons.lock_outline, color: Colors.grey.shade500, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Abonnez-vous pour activer vos réductions de parrainage. '
            'Vous pouvez déjà entrer le code d\'un parrain ci-dessous.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ),
      ]),
    );
  }
}

class _PriceLadder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const rows = [
      ('0 parrainage', '3,00 €/mois'),
      ('1 parrainage', '2,79 €/mois'),
      ('3 parrainages', '2,37 €/mois'),
      ('7 parrainages', '1,50 €/mois ✦'),
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.deepPurple.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.deepPurple.shade100),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Plus vous invitez, moins vous payez',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: Colors.deepPurple.shade700)),
        const SizedBox(height: 8),
        ...rows.map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(r.$1, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                Text(r.$2,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: r.$1.startsWith('7') ? FontWeight.bold : FontWeight.normal,
                        color: r.$1.startsWith('7')
                            ? Colors.deepPurple.shade700
                            : Colors.grey.shade800)),
              ]),
            )),
      ]),
    );
  }
}
