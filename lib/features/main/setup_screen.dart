import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../shared/services/referral_service.dart';
import '../auth/providers/auth_provider.dart';
import '../referral/providers/referral_provider.dart';
import '../settings/providers/settings_provider.dart';
import '../subscription/paywall_bottom_sheet.dart';
import '../subscription/subscription_provider.dart';
import '../subscription/subscription_section.dart';
import '../profile/providers/profile_context_provider.dart';
import '../profile/widgets/profile_switcher.dart';
import '../team/screens/team_dashboard_screen.dart' show teamTabRequestProvider, TeamTabRequest;
import '../../core/constants/app_colors.dart';
import '../../core/config/app_build.dart';

// ─── Full screen (used as Profile tab) ───────────────────────────────────────

class SetupScreen extends ConsumerWidget {
  const SetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(firebaseUserProvider).valueOrNull;
    final isPro = ref.watch(effectiveSubscriptionProvider);
    final team = ref.watch(teamStateProvider).valueOrNull;
    final settings = ref.watch(settingsProvider).valueOrNull ?? {};
    final companyName = (settings['company_name'] ?? '').toString().trim();
    final techName = (settings['technician_name'] ?? '').toString().trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon compte'),
        actions: [
          // (#5) Accès express au parrainage : copie le code + snackbar.
          // [PAUSED-REFERRAL] masqué tant que le parrainage est en pause.
          if (kParrainageEnabled && user != null)
            IconButton(
              tooltip: 'Copier mon code de parrainage',
              icon: const Icon(Icons.card_giftcard_outlined),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  final code = await ReferralService.getOrCreateCode(user.uid);
                  await Clipboard.setData(ClipboardData(text: code));
                  messenger.showSnackBar(SnackBar(
                    content: Text('Code de parrainage « $code » copié ! '
                        'Plus d\'infos dans la page Parrainage.'),
                    action: SnackBarAction(
                      label: 'Parrainage',
                      onPressed: () => context.push('/referral'),
                    ),
                  ));
                } catch (_) {
                  messenger.showSnackBar(const SnackBar(
                      content: Text('Impossible de récupérer le code.')));
                }
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          // (simplification) Toggle de profil retiré : le choix d'identité se
          // fait dans Réglages (solo) / onglet Équipe. Mon compte = compte pur.
          // ── User header (tap → profil) ──────────────────────────────────
          if (user != null) ...[
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => context.push('/profile-account'),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AppColors.primary,
                    child: Text(
                      (user.displayName?.isNotEmpty == true
                              ? user.displayName![0]
                              : user.email?[0] ?? '?')
                          .toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (user.displayName?.isNotEmpty == true)
                          Text(user.displayName!, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                        Text(user.email ?? '', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                      ],
                    ),
                  ),
                  if (isPro)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('PRO', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right, size: 18, color: Colors.black38),
                ]),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // (#7) Sélecteur d'identité (profil perso ↔ équipe) — RÉUTILISE le
          // système existant (activeProfileProvider). Affiché seulement si
          // l'utilisateur a réellement 2 profils (solo + équipe) ; sinon inutile.
          if (ref.watch(canSwitchProfileProvider)) const ProfileSwitcherCard(),

          // ── Checklist ───────────────────────────────────────────────────
          const Text('Configuration', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black54)),
          const SizedBox(height: 10),

          _StepTile(
            index: 1,
            title: 'Compte créé',
            done: user != null,
            subtitle: user != null
                ? (user.email ?? 'Connecté')
                : 'Non connecté — certaines fonctions sont limitées',
            actionLabel: user != null ? null : 'Se connecter',
            onAction: user != null ? null : () => context.push('/auth'),
          ),
          _StepTile(
            index: 2,
            title: 'Infos de l\'entreprise',
            done: companyName.isNotEmpty || techName.isNotEmpty,
            subtitle: companyName.isNotEmpty
                ? companyName
                : techName.isNotEmpty
                    ? techName
                    : 'Non renseigné — apparaît sur vos PDFs',
            actionLabel: 'Paramètres',
            onAction: () => context.go('/settings'),
          ),
          _StepTile(
            index: 3,
            title: 'Abonnement Pro',
            done: isPro,
            disabled: user == null, // (e7) nécessite un compte
            subtitle: user == null
                ? 'Connectez-vous pour vous abonner'
                : isPro
                    ? 'Actif — exports illimités, signature distante, factures'
                    : 'Non souscrit — 5 exports/mois, fonctions limitées',
            // (I) Tuile interactive même quand Pro → mène à la gestion de l'abo.
            actionLabel: user == null
                ? null
                : (isPro ? 'Gérer' : 'Voir les offres'),
            onAction: user == null
                ? null
                : (isPro
                    ? () => _openProSubscription(context, ref, team)
                    // (e10) si on a une équipe → onglet « Pour mon équipe » présélectionné
                    : () => PaywallBottomSheet.show(context,
                        initialForTeam: team?.hasTeam ?? false)),
            important: !isPro && user != null,
          ),
          // [PAUSED-REFERRAL] tuile parrainage masquée (pivot IAP simple).
          if (kParrainageEnabled) _StepTile(
            index: 4,
            title: 'Parrainage',
            done: false,
            optional: true,
            disabled: user == null, // (e7)
            subtitle: user == null
                ? 'Connectez-vous pour parrainer'
                : 'Invitez des proches — vous payez tous les deux moins (jusqu\'à −50%)',
            actionLabel: 'Mon parrainage',
            onAction: () => context.push('/referral'),
            // (e3) Progression de parrainage (cases qui se remplissent).
            footer: user == null
                ? null
                : _ReferralCells(count: ref.watch(activeActivationsCountProvider)),
            // (o1) Remplissage de la tuile depuis la gauche (count/8).
            fillFraction: user == null
                ? null
                : (ref.watch(activeActivationsCountProvider) / 8).clamp(0.0, 1.0),
          ),
          _StepTile(
            index: 5,
            title: 'Équipe',
            done: team?.hasTeam ?? false,
            optional: true,
            disabled: user == null, // (e7)
            subtitle: user == null
                ? 'Connectez-vous pour créer/rejoindre une équipe'
                : team?.hasTeam == true
                    ? '${team!.companyName ?? 'Équipe configurée'} · ${team.role == 'admin' ? 'Admin' : 'Technicien'}'
                    : 'Optionnel — permet la validation et le partage de rapports',
            actionLabel: team?.hasTeam == true ? null : 'Configurer',
            onAction: team?.hasTeam == true ? null : () => context.push('/team-setup'),
          ),

          const SizedBox(height: 28),

          // (D-opt1) Abonnement pro PERSONNEL géré ICI (déplacé des Réglages).
          if (user != null) ...[
            const Text('Abonnement pro personnel',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.black54)),
            const SizedBox(height: 6),
            const SubscriptionSection(scope: SubScope.personal),
            // (#10) Petit pointeur « Abonnement équipe » → se gère dans l'onglet
            // Équipe (uniquement si l'utilisateur fait partie d'une équipe).
            if (team?.hasTeam ?? false) ...[
              const SizedBox(height: 10),
              _TeamSubscriptionPointer(),
            ],
            const SizedBox(height: 28),
          ],

          // ── Quick links ──────────────────────────────────────────────────
          const Text('Accès rapide', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black54)),
          const SizedBox(height: 10),
          // (e1) Lien « Paramètres » retiré : déjà accessible depuis la barre de navigation.
          // (#10) « Mon équipe », « Abonnement » et « Parrainage » retirés d'Accès
          // rapide : redondants (Équipe = onglet dédié ; Abonnement = section
          // ci-dessus / onglet Équipe ; Parrainage = icône partage de la page).
          // (e9) Mon équipe : flèche (→ page équipe) + partage du code d'invitation.
          // _TeamQuickLink(
          //   companyName: team?.companyName,
          //   inviteCode: (team?.hasTeam ?? false) ? team?.inviteCode : null,
          // ),
          // _QuickLink(icon: Icons.workspace_premium_outlined, label: 'Abonnement', onTap: () => PaywallBottomSheet.show(context, initialForTeam: team?.hasTeam ?? false)),
          // _QuickLink(icon: Icons.card_giftcard_outlined, label: 'Parrainage', onTap: () => context.push('/referral')),
          // In compact nav layout, Clients tab is removed — provide direct access here
          if (kEnableNewNavLayout)
            _QuickLink(icon: Icons.contacts_outlined, label: 'Mes clients', onTap: () => context.push('/clients')),
        ],
      ),
    );
  }
}

// (I) Quand l'utilisateur est Pro, la tuile « Abonnement Pro » mène à la gestion :
//  • abo solo seul → la section est juste en dessous (snackbar) ;
//  • abo équipe seul → onglet Équipe ;
//  • les deux → petit choix.
void _openProSubscription(BuildContext context, WidgetRef ref, dynamic team) {
  final soloActive = ref.read(subscriptionProvider).valueOrNull.isActive;
  final teamActive = ref.read(companySubscriptionProvider).valueOrNull.isActive;
  if (soloActive && teamActive) {
    showDialog<void>(
      context: context,
      builder: (dlg) => AlertDialog(
        title: const Text('Quel abonnement gérer ?'),
        content: const Text(
            'Vous avez les deux. Lequel voulez-vous gérer ?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dlg);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text(
                      'Votre abonnement solo se gère ci-dessous, dans « Abonnement pro personnel ».')));
            },
            child: const Text('Solo'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dlg);
              context.go('/team-tab');
            },
            child: const Text('Équipe'),
          ),
        ],
      ),
    );
  } else if (teamActive) {
    context.go('/team-tab');
  } else {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Votre abonnement se gère ci-dessous, dans « Abonnement pro personnel » 👇')));
  }
}

// ─── Bottom sheet version (opened from setup bar) ────────────────────────────

class SetupChecklistSheet extends ConsumerWidget {
  const SetupChecklistSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      // (#3) Navigateur racine → la feuille ne « ressuscite » pas en revenant
      // sur l'onglet d'où elle a été ouverte.
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const SetupChecklistSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(firebaseUserProvider).valueOrNull;
    final isPro = ref.watch(effectiveSubscriptionProvider);
    final team = ref.watch(teamStateProvider).valueOrNull;
    final settings = ref.watch(settingsProvider).valueOrNull ?? {};
    final companyName = (settings['company_name'] ?? '').toString().trim();
    final techName = (settings['technician_name'] ?? '').toString().trim();

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, ctrl) => ListView(
        controller: ctrl,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Configuration du compte', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          const SizedBox(height: 4),
          const Text('Suivez ces étapes pour tirer le meilleur de l\'app.',
              style: TextStyle(fontSize: 13, color: Colors.black54)),
          const SizedBox(height: 16),
          _StepTile(
            index: 1,
            title: 'Compte créé',
            done: user != null,
            subtitle: user?.email ?? 'Non connecté',
            actionLabel: user != null ? null : 'Se connecter',
            onAction: user != null ? null : () { Navigator.pop(context); context.push('/auth'); },
          ),
          _StepTile(
            index: 2,
            title: 'Infos de l\'entreprise',
            done: companyName.isNotEmpty || techName.isNotEmpty,
            subtitle: companyName.isNotEmpty ? companyName : techName.isNotEmpty ? techName : 'Non renseigné',
            actionLabel: 'Paramètres',
            onAction: () { Navigator.pop(context); context.go('/settings'); },
          ),
          _StepTile(
            index: 3,
            title: 'Abonnement Pro',
            done: isPro,
            subtitle: isPro ? 'Actif' : 'Exports illimités, signature distante, factures',
            actionLabel: isPro ? null : 'S\'abonner',
            onAction: isPro ? null : () { Navigator.pop(context); PaywallBottomSheet.show(context); },
            important: !isPro,
          ),
          // [PAUSED-REFERRAL] entrée parrainage masquée (pivot IAP simple).
          if (kParrainageEnabled) _StepTile(
            index: 4,
            title: 'Parrainage',
            done: false,
            optional: true,
            subtitle: 'Invitez des proches — jusqu\'à −50% chacun',
            actionLabel: 'Voir',
            onAction: () { Navigator.pop(context); context.push('/referral'); },
          ),
          _StepTile(
            index: 5,
            title: 'Équipe',
            done: team?.hasTeam ?? false,
            optional: true,
            subtitle: team?.hasTeam == true
                ? team!.companyName ?? 'Configurée'
                : 'Optionnel',
            actionLabel: team?.hasTeam == true ? null : 'Configurer',
            onAction: team?.hasTeam == true ? null : () { Navigator.pop(context); context.push('/team-setup'); },
          ),
        ],
      ),
    );
  }
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

class _StepTile extends StatelessWidget {
  final int index;
  final String title;
  final bool done;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool optional;
  final bool important;
  // (e7) Désactivé tant qu'on n'est pas connecté : grisé et non cliquable.
  final bool disabled;
  // (e3) Contenu additionnel rendu sous le sous-titre (ex. barre de progression).
  final Widget? footer;
  // (o1) Remplit la tuile en couleur depuis la GAUCHE (0..1) — effet « avancement ».
  final double? fillFraction;

  const _StepTile({
    required this.index,
    required this.title,
    required this.done,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
    this.optional = false,
    this.important = false,
    this.disabled = false,
    this.footer,
    this.fillFraction,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          // (o1) Si fillFraction est défini : dégradé à coupure nette → la
          // partie GAUCHE est colorée (vert), le reste garde la couleur de base.
          color: (fillFraction != null && fillFraction! > 0)
              ? null
              : (done
                  ? Colors.green.shade50
                  : important
                      ? Colors.orange.shade50
                      : Colors.grey.shade50),
          gradient: (fillFraction != null && fillFraction! > 0)
              ? LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.green.shade100,
                    Colors.green.shade100,
                    Colors.grey.shade50,
                    Colors.grey.shade50,
                  ],
                  stops: [
                    0.0,
                    fillFraction!.clamp(0.0, 1.0),
                    fillFraction!.clamp(0.0, 1.0),
                    1.0,
                  ],
                )
              : null,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: done
                ? Colors.green.shade200
                : important
                    ? Colors.orange.shade200
                    : Colors.grey.shade200,
          ),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? Colors.green : important ? Colors.orange.shade400 : Colors.grey.shade300,
            ),
            child: done
                ? const Icon(Icons.check, color: Colors.white, size: 16)
                : Center(
                    child: Text('$index',
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                if (optional) ...[
                  const SizedBox(width: 6),
                  Text('optionnel', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                ],
              ]),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.black54)),
              if (footer != null) ...[const SizedBox(height: 6), footer!],
            ]),
          ),
          if (disabled) ...[
            const SizedBox(width: 8),
            Icon(Icons.lock_outline, size: 16, color: Colors.grey.shade500),
          ] else if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: done ? Colors.green : important ? Colors.orange.shade700 : AppColors.primary,
              ),
              child: Text(actionLabel!, style: const TextStyle(fontSize: 12)),
            ),
          ],
        ]),
      ),
      ),
    );
  }
}

class _QuickLink extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickLink({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppColors.primary, size: 22),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
      onTap: onTap,
      dense: true,
    );
  }
}

// (e3) Barre de progression du parrainage : 8 cases qui se remplissent au fil
// des parrainages actifs (8 = plancher de prix atteint).
class _ReferralCells extends StatelessWidget {
  final int count;
  static const int _cells = 8;
  const _ReferralCells({required this.count});

  @override
  Widget build(BuildContext context) {
    final filled = count.clamp(0, _cells);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(_cells, (i) {
            final isOn = i < filled;
            return Expanded(
              child: Container(
                margin: const EdgeInsets.only(right: 3),
                height: 8,
                decoration: BoxDecoration(
                  color: isOn ? AppColors.primary : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 3),
        Text(
          filled >= _cells
              ? 'Réduction maximale atteinte 🎉'
              : '$filled parrainage${filled > 1 ? 's' : ''} actif${filled > 1 ? 's' : ''} · $filled/$_cells',
          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}

// (#10) Pointeur « Abonnement équipe » sous l'abo perso : informe que l'abo
// d'équipe se gère dans l'onglet Équipe → Réglages équipe, et y mène.
class _TeamSubscriptionPointer extends ConsumerWidget {
  const _TeamSubscriptionPointer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      // (M) Atterrit sur le 3e sous-onglet « Réglages équipe » (où vit l'abo).
      onTap: () {
        ref.read(teamTabRequestProvider.notifier).state = TeamTabRequest(
            tab: 2, nonce: DateTime.now().microsecondsSinceEpoch);
        context.go('/team-tab');
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.indigo.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.indigo.shade100),
        ),
        child: Row(children: [
          Icon(Icons.groups_outlined, size: 20, color: Colors.indigo.shade400),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Abonnement équipe',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Colors.indigo.shade800)),
                Text('Se gère dans l\'onglet Équipe → Réglages équipe.',
                    style: TextStyle(
                        fontSize: 11, color: Colors.indigo.shade700)),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 18, color: Colors.indigo.shade300),
        ]),
      ),
    );
  }
}
