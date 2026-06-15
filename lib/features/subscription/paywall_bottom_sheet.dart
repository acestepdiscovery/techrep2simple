// Paywall — IAP-only (2026-06-08 simple pivot).
//
// Rewritten from the Stripe+referral version (preserved in the sibling
// `OLDPROJECT z22` folder and git history). Now: fixed store products only —
// 3 solo tiles + 4 team brackets, "Restaurer mes achats", and a store deep-link
// to manage the subscription. No Stripe checkout, no referral.
//
// Entitlement detection is unchanged: we listen to effectiveSubscriptionProvider
// (Firestore) and close the sheet when Pro turns on after the CF validates.

import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_colors.dart';
import '../../core/config/app_build.dart';
import '../../shared/services/billing_config.dart';
import '../../shared/services/team_service.dart';
import '../../shared/services/iap_service.dart';
import '../../shared/services/instance_token_guard.dart';
import '../auth/providers/auth_provider.dart';
import 'subscription_provider.dart';

// Call from anywhere:
//   PaywallBottomSheet.show(context, reason: 'Export PDF');
//   PaywallBottomSheet.show(context, initialForTeam: true); // pre-select team tab
class PaywallBottomSheet extends ConsumerStatefulWidget {
  final String? reason;
  final bool initialForTeam;
  const PaywallBottomSheet({super.key, this.reason, this.initialForTeam = false});

  static Future<void> show(
    BuildContext context, {
    String? reason,
    bool initialForTeam = false,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      // (#3) Anchored to the ROOT navigator so it doesn't linger in a tab branch.
      useRootNavigator: true,
      builder: (_) =>
          PaywallBottomSheet(reason: reason, initialForTeam: initialForTeam),
    );
  }

  @override
  ConsumerState<PaywallBottomSheet> createState() => _PaywallBottomSheetState();
}

class _PaywallBottomSheetState extends ConsumerState<PaywallBottomSheet> {
  late bool _forCompany;
  String _selectedSoloId = kProMonthly.id;
  String _selectedTeamId = kTeamProducts[1].id; // default "up to 5"
  bool _productsLoaded = false;

  final IapService _iap = IapService.instance;

  @override
  void initState() {
    super.initState();
    _forCompany = widget.initialForTeam;
    _iap.busy.addListener(_onIapChange);
    _iap.lastError.addListener(_onIapChange);
    _iap.purchaseSuccess.addListener(_onPurchaseSuccess);
    _loadProducts();
  }

  @override
  void dispose() {
    _iap.busy.removeListener(_onIapChange);
    _iap.lastError.removeListener(_onIapChange);
    _iap.purchaseSuccess.removeListener(_onPurchaseSuccess);
    super.dispose();
  }

  void _onIapChange() {
    if (mounted) setState(() {});
  }

  // (feedback achat) Ferme la feuille + confirme UNE seule fois — que l'achat
  // vienne d'un nouvel abonné (effectiveSubscription transitionne false→true) ou
  // d'un user DÉJÀ Pro qui ajoute un abo (pas de transition → signal purchaseSuccess).
  bool _closed = false;
  void _onPurchaseSuccess() => _closeWithSuccess();
  void _closeWithSuccess() {
    if (_closed || !mounted) return;
    _closed = true;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(const SnackBar(
      content: Text('Votre abonnement Pro est actif ✓'),
      backgroundColor: Colors.green,
      duration: Duration(seconds: 5),
    ));
  }

  Future<void> _loadProducts() async {
    await _iap.loadProducts();
    if (mounted) setState(() => _productsLoaded = true);
  }

  Future<void> _buy(IapProduct product, {String? companyId}) async {
    if (FirebaseAuth.instance.currentUser == null) {
      Navigator.pop(context);
      context.push('/auth');
      return;
    }
    // (#1 anti-sous-paiement équipe) On REFUSE de passer à un palier INFÉRIEUR au
    // nombre de membres ACTIFS : sinon un admin pourrait activer N membres puis
    // baisser le palier et tous les garder en payant moins. → désactiver d'abord.
    if (product.isTeam && companyId != null && companyId.isNotEmpty) {
      try {
        final members = await TeamService().getMembers(companyId);
        final activeCount = members.where((m) => m.active).length;
        if (product.seats < activeCount && mounted) {
          await showDialog(
            context: context,
            builder: (d) => AlertDialog(
              title: const Text('Trop de membres actifs'),
              content: Text(
                  'Votre équipe a $activeCount membres actifs. Désactivez '
                  '${activeCount - product.seats} membre(s) avant de passer au '
                  'palier « jusqu\'à ${product.seats} membres ».'),
              actions: [
                FilledButton(
                    onPressed: () => Navigator.pop(d),
                    child: const Text('Compris')),
              ],
            ),
          );
          return;
        }
      } catch (_) {
        // Lecture des membres impossible (offline) → on n'empêche pas l'achat.
      }
    }
    // Instance kill-switch guard (same as before).
    final (tokenBlocked, tokenMsg) = await InstanceTokenGuard.check();
    if (tokenBlocked) {
      if (mounted) await InstanceTokenGuard.showBlockedDialog(context, tokenMsg);
      return;
    }
    await _iap.buy(product, companyId: companyId);
    // Success → CF writes `subscription` → effectiveSubscriptionProvider flips →
    // the listener below closes the sheet. Errors surface via _iap.lastError.
  }

  Future<void> _openStoreManage() async {
    // Deep-link to the OS subscription management screen.
    final url = Platform.isIOS
        ? 'https://apps.apple.com/account/subscriptions'
        : 'https://play.google.com/store/account/subscriptions';
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  // Ouvre une page légale (CGU / Confidentialité). Tant que l'URL n'est pas
  // renseignée (app_build), on affiche un message au lieu d'un lien mort.
  Future<void> _openLegalUrl(String url) async {
    if (url.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Page bientôt disponible.')),
        );
      }
      return;
    }
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(effectiveSubscriptionProvider, (prev, next) {
      if (next && !(prev ?? false)) _closeWithSuccess();
    });

    final team = ref.watch(teamStateProvider).valueOrNull;
    final hasTeam = team?.hasTeam ?? false;
    final isAdmin = team?.isAdmin ?? false;
    final canSubscribeForTeam = hasTeam && isAdmin;
    final isNonAdminMember = hasTeam && !isAdmin;
    final companySub = ref.watch(companySubscriptionProvider).valueOrNull;
    final companyActive = companySub.isActive;
    final companySeatLimit = (companySub?['seat_limit'] as int?) ?? 0;
    // (déjà abonné solo) Produit solo perso actuellement actif → on le marque
    // « Actif » et on indique qu'on peut CHANGER d'offre (sans bloquer).
    final userSub = ref.watch(subscriptionProvider).valueOrNull;
    final currentSoloId =
        userSub.isActive ? (userSub?['iap_product_id'] as String?) : null;

    final busy = _iap.busy.value;
    final error = _iap.lastError.value;

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      maxChildSize: 0.97,
      minChildSize: 0.5,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: Scrollbar(
                controller: controller,
                thumbVisibility: true,
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                  children: [
                    _TeamToggle(
                      forCompany: _forCompany,
                      onChanged: (v) => setState(() => _forCompany = v),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.reason ?? 'Débloquez toutes les fonctionnalités',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 16),

                    // ── Features ─────────────────────────────────────────────
                    if (!_forCompany) ...[
                      // (déjà Pro via équipe) Membre OU admin déjà couvert par l'abo
                      // ÉQUIPE → on clarifie la PORTÉE du solo : il ne couvre que les
                      // rapports PERSO (les rapports d'équipe sont déjà couverts).
                      if (hasTeam && companyActive)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline,
                                  size: 18, color: Colors.blue.shade700),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Vous êtes déjà Pro via votre équipe — vos rapports '
                                  'd\'ÉQUIPE sont couverts. Cet abonnement solo couvre '
                                  'uniquement vos rapports PERSO (sous votre identité).',
                                  style: TextStyle(
                                      fontSize: 11.5, color: Colors.blue.shade900),
                                ),
                              ),
                            ],
                          ),
                        ),
                      // (#5) Chef d'équipe PAS encore Pro équipe sur « Pour moi » → on
                      // l'oriente vers l'onglet équipe (un abo solo ne couvre que LUI).
                      if (canSubscribeForTeam && !companyActive)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Icon(Icons.info_outline,
                                    size: 18, color: Colors.orange.shade800),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Vous êtes responsable d\'une équipe',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: Colors.orange.shade900),
                                  ),
                                ),
                              ]),
                              const SizedBox(height: 4),
                              Text(
                                'Cet abonnement « Pour moi » ne couvre que VOUS. Pour '
                                'donner le Pro à tous vos techniciens (et payer moins '
                                'cher par personne), prenez l\'abonnement équipe.',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    color: Colors.orange.shade900),
                              ),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: () =>
                                      setState(() => _forCompany = true),
                                  icon: const Icon(Icons.group_outlined,
                                      size: 16),
                                  label: const Text(
                                      'Aller à « Pour mon équipe »'),
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      _FeatureRow(Icons.picture_as_pdf_outlined,
                          'Exports PDF illimités',
                          'Générez autant de rapports que nécessaire'),
                      _FeatureRow(Icons.draw_outlined,
                          'Signature distante du client',
                          'Le client signe à distance, depuis un lien'),
                      _FeatureRow(Icons.cloud_outlined, 'Sauvegarde cloud',
                          'Vos rapports accessibles partout'),
                    ] else ...[
                      _FeatureRow(Icons.all_inclusive, 'Tout l\'abonnement solo',
                          'Exports illimités, signature distante, cloud — pour CHAQUE membre',
                          color: Colors.indigo),
                      _FeatureRow(Icons.fact_check_outlined,
                          'Aperçu + validation des rapports',
                          'Consultez et validez/retournez les rapports de vos techniciens',
                          color: Colors.green.shade600),
                      _FeatureRow(Icons.manage_accounts_outlined,
                          'Gestion des membres',
                          'Invitations, droits, sièges, activité de l\'équipe',
                          color: Colors.orange.shade700),
                      _FeatureRow(Icons.trending_down, 'Prix dégressif',
                          'Plus l\'équipe est grande, moins cher par siège',
                          color: Colors.teal.shade600),
                    ],
                    const SizedBox(height: 24),

                    // ── Plans ────────────────────────────────────────────────
                    if (_forCompany) ...[
                      if (canSubscribeForTeam) ...[
                        if (companyActive) ...[
                          _ActivePlanBanner(
                            text: '$companySeatLimit sièges actifs',
                            onManage: _openStoreManage,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Changez de palier ci-dessous (mise à niveau gérée par le store).',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 8),
                        ],
                        ...kTeamProducts.map((p) => _ProductTile(
                              icon: Icons.group_outlined,
                              label: p.label,
                              subtitle: p.subtitle,
                              price: _iap.priceLabel(p.id),
                              selected: _selectedTeamId == p.id,
                              onTap: () =>
                                  setState(() => _selectedTeamId = p.id),
                            )),
                        const SizedBox(height: 20),
                        _SubscribeButton(
                          loading: busy,
                          label: companyActive
                              ? 'Changer de palier'
                              : 'Activer pour l\'équipe',
                          icon: Icons.group,
                          onTap: () => _buy(
                            productById(_selectedTeamId)!,
                            companyId: team?.companyId,
                          ),
                        ),
                      ] else if (isNonAdminMember) ...[
                        _TeamMemberInfoCard(
                            onShareTap: () => _copyShareMessage(context)),
                        const SizedBox(height: 12),
                        _SubscribeButton(
                          loading: busy,
                          label: 'Souscrire en solo à la place',
                          icon: Icons.person,
                          secondary: true,
                          onTap: () => setState(() => _forCompany = false),
                        ),
                      ] else ...[
                        _NoTeamInfoCard(),
                        const SizedBox(height: 12),
                        _SubscribeButton(
                          loading: busy,
                          label: 'Voir les abonnements individuels',
                          icon: Icons.person,
                          secondary: true,
                          onTap: () => setState(() => _forCompany = false),
                        ),
                      ],
                    ] else ...[
                      // Solo
                      OutlinedButton.icon(
                        onPressed: () => setState(() => _forCompany = true),
                        icon: const Icon(Icons.group_outlined, size: 16),
                        label: const Text('Voir les abonnements pour équipe'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(40),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // (déjà abonné) On INDIQUE l'offre déjà prise (badge « Actif »)
                      // sans bloquer : on peut en changer (mensuel↔annuel = remplacé
                      // par le store, pas de double abo).
                      if (currentSoloId != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            () {
                              final label =
                                  productById(currentSoloId)?.label ?? '';
                              // (résilié) Abo en cours mais renouvellement coupé →
                              // on dit qu'il reste ACTIF jusqu'à la date, puis fin.
                              if (userSub?['cancel_at_period_end'] == true) {
                                final e = userSub.periodEnd;
                                final until = e != null
                                    ? ' jusqu\'au ${e.day}/${e.month}/${e.year}'
                                    : '';
                                return 'Votre offre « $label » est RÉSILIÉE — l\'accès '
                                    'reste ACTIF$until, puis se termine. Re-souscrivez '
                                    'ci-dessous pour réactiver ou changer.';
                              }
                              return 'Vous avez déjà l\'offre « $label ». Vous pouvez '
                                  'en changer ci-dessous.';
                            }(),
                            style: TextStyle(
                                fontSize: 11.5,
                                color: (userSub?['cancel_at_period_end'] == true)
                                    ? Colors.orange.shade900
                                    : Colors.blue.shade900),
                          ),
                        ),
                      ...kSoloProducts.map((p) => _ProductTile(
                            icon: p.isLifetime
                                ? Icons.all_inclusive
                                : Icons.calendar_today_outlined,
                            label: p.label,
                            subtitle: p.subtitle,
                            price: _iap.priceLabel(p.id),
                            selected: _selectedSoloId == p.id,
                            active: p.id == currentSoloId,
                            onTap: () =>
                                setState(() => _selectedSoloId = p.id),
                          )),
                      // (à-vie) Achat unique → pas de remplacement d'abo : on
                      // prévient de penser à annuler l'abonnement en cours.
                      if (currentSoloId != null &&
                          (productById(_selectedSoloId)?.isLifetime ?? false))
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '⚠️ « À vie » est un achat unique : votre abonnement actuel '
                            'continuera jusqu\'à ce que vous l\'annuliez dans le store.',
                            style: TextStyle(
                                fontSize: 11.5, color: Colors.orange.shade900),
                          ),
                        ),
                      const SizedBox(height: 20),
                      _SubscribeButton(
                        loading: busy,
                        label: currentSoloId == null
                            ? 'S\'abonner'
                            : (_selectedSoloId == currentSoloId
                                ? 'Offre déjà active'
                                : 'Changer pour cette offre'),
                        icon: Icons.workspace_premium_outlined,
                        onTap: () {
                          if (currentSoloId != null &&
                              _selectedSoloId == currentSoloId) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'C\'est déjà votre offre actuelle.')));
                            return;
                          }
                          _buy(productById(_selectedSoloId)!);
                        },
                      ),
                    ],

                    if (!_productsLoaded) ...[
                      const SizedBox(height: 10),
                      Text('Chargement des prix…',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade400)),
                    ],

                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(error,
                            style: TextStyle(
                                color: Colors.red.shade700, fontSize: 13)),
                      ),
                    ],

                    const SizedBox(height: 12),
                    // Mandatory "Restore purchases" (Apple Review 3.1.1).
                    TextButton.icon(
                      onPressed: busy ? null : () => _iap.restore(),
                      icon: const Icon(Icons.restore, size: 16),
                      label: const Text('Restaurer mes achats'),
                    ),

                    const SizedBox(height: 12),
                    const _ShareAppCard(),

                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Pas maintenant',
                          style: TextStyle(color: Colors.grey)),
                    ),
                    const SizedBox(height: 8),
                    // (Apple Review 3.1.2 + Google) Mention d'abonnement OBLIGATOIRE
                    // près du bouton d'achat + liens CGU/Confidentialité fonctionnels.
                    Text(
                      'Abonnement à renouvellement automatique. Le paiement est '
                      'débité via l\'App Store ou Google Play à la confirmation de '
                      'l\'achat. Sauf résiliation au moins 24 h avant la fin de la '
                      'période en cours, l\'abonnement se renouvelle automatiquement '
                      'au même tarif. Gérez ou résiliez à tout moment dans les '
                      'réglages d\'abonnement de votre compte (App Store / Google '
                      'Play). Les formules mensuelles sont sans engagement ; '
                      'l\'achat « à vie » est un paiement unique non récurrent.',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          onPressed: () => _openLegalUrl(kTermsUrl),
                          style: TextButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(0, 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text("Conditions d'utilisation",
                              style: TextStyle(fontSize: 11)),
                        ),
                        Text('·',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade500)),
                        TextButton(
                          onPressed: () => _openLegalUrl(kPrivacyPolicyUrl),
                          style: TextButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(0, 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Politique de confidentialité',
                              style: TextStyle(fontSize: 11)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _copyShareMessage(BuildContext context) {
    const msg =
        'J\'utilise "Rapport Technique IA" pour mes bons d\'intervention — rapide, pro, PDF en un clic. Disponible sur iOS et Android. À tester absolument !';
    Clipboard.setData(const ClipboardData(text: msg));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Message copié !')));
  }
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _TeamToggle extends StatelessWidget {
  final bool forCompany;
  final ValueChanged<bool> onChanged;
  const _TeamToggle({required this.forCompany, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _ToggleOption(
            label: 'Pour moi',
            icon: Icons.person_outline,
            selected: !forCompany,
            onTap: () => onChanged(false),
          ),
          _ToggleOption(
            label: 'Pour mon équipe',
            icon: Icons.group_outlined,
            selected: forCompany,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _ToggleOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _ToggleOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 6,
                        offset: const Offset(0, 2))
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 16,
                  color: selected ? AppColors.primary : Colors.grey.shade500),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  color: selected ? AppColors.primary : Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color? color;
  const _FeatureRow(this.icon, this.title, this.subtitle, {this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: c),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                Text(subtitle,
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final String price;
  final bool selected;
  final bool active;
  final VoidCallback onTap;
  const _ProductTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.price,
    required this.selected,
    this.active = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primary : Colors.grey.shade200,
              width: selected ? 2 : 1,
            ),
            color: selected
                ? AppColors.primary.withValues(alpha: 0.05)
                : Colors.white,
          ),
          child: Row(
            children: [
              Icon(icon,
                  color: selected ? AppColors.primary : Colors.grey.shade400,
                  size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color:
                              selected ? AppColors.primary : Colors.black87,
                        )),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade500)),
                  ],
                ),
              ),
              if (active) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Text('Actif',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700)),
                ),
                const SizedBox(width: 8),
              ],
              Text(price,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: selected ? AppColors.primary : Colors.black87,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivePlanBanner extends StatelessWidget {
  final String text;
  final VoidCallback onManage;
  const _ActivePlanBanner({required this.text, required this.onManage});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, color: Colors.green.shade700, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Abonnement actif · $text',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.green.shade800,
                    fontSize: 13)),
          ),
          TextButton(
            onPressed: onManage,
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                visualDensity: VisualDensity.compact),
            child: const Text('Gérer', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _SubscribeButton extends StatelessWidget {
  final bool loading;
  final String label;
  final IconData icon;
  final bool secondary;
  final VoidCallback onTap;

  const _SubscribeButton({
    required this.loading,
    required this.label,
    required this.icon,
    required this.onTap,
    this.secondary = false,
  });

  @override
  Widget build(BuildContext context) {
    if (secondary) {
      return OutlinedButton.icon(
        onPressed: loading ? null : onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
    return FilledButton.icon(
      onPressed: loading ? null : onTap,
      icon: loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            )
          : Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 15)),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

// Non-admin team member opening the team tab.
class _TeamMemberInfoCard extends StatelessWidget {
  final VoidCallback onShareTap;
  const _TeamMemberInfoCard({required this.onShareTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade50, Colors.indigo.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tips_and_updates_outlined,
                  color: Colors.blue.shade700, size: 20),
              const SizedBox(width: 8),
              Text('Le bon plan pour votre équipe',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade800,
                      fontSize: 14)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Si votre responsable souscrit le plan équipe, '
            'vous bénéficiez de l\'accès Pro automatiquement — '
            'sans rien payer de votre poche.',
            style: TextStyle(fontSize: 13, color: Colors.blue.shade800),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onShareTap,
            icon: const Icon(Icons.share_outlined, size: 16),
            label: const Text('Lui envoyer l\'appli'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// Solo user (no team) opening the team tab.
class _NoTeamInfoCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(firebaseUserProvider).valueOrNull;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.group_add_outlined,
                  color: Colors.grey.shade700, size: 20),
              const SizedBox(width: 8),
              Text('Plan pour une équipe',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                      fontSize: 14)),
            ],
          ),
          const SizedBox(height: 4),
          Text('À partir de 5,99 €/mois (jusqu\'à 2 membres)',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 10),
          Text(
            'Vous gérez des techniciens ? Créez votre espace équipe, '
            'puis activez l\'abonnement équipe pour que tous vos techniciens '
            'aient accès Pro automatiquement.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                if (user != null) {
                  context.push('/team-setup');
                } else {
                  context.push('/auth');
                }
              },
              icon: const Icon(Icons.group_add, size: 18),
              label: const Text('Créer / rejoindre une équipe'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                textStyle: const TextStyle(fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Share card — visible to everyone.
class _ShareAppCard extends StatelessWidget {
  const _ShareAppCard();

  static const _shareText =
      'J\'utilise "Rapport Technique IA" pour mes bons d\'intervention — '
      'rapide, professionnel, PDF en un clic. Disponible sur iOS et Android. '
      'À tester absolument !';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child:
                Icon(Icons.share_outlined, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Faire connaître l\'appli',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                Text('À vos collègues, votre chef, d\'autres entreprises…',
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              Clipboard.setData(const ClipboardData(text: _shareText));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Message copié dans le presse-papier !')));
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              textStyle: const TextStyle(fontSize: 12),
            ),
            child: const Text('Copier'),
          ),
        ],
      ),
    );
  }
}
