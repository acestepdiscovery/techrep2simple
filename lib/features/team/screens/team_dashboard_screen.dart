import 'dart:io';
import '../../../core/config/app_build.dart'; // kParrainageEnabled [PAUSED-REFERRAL]
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../settings/providers/settings_provider.dart';
import '../../../shared/widgets/text_field_dialog.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../../features/reports/models/report_model.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/subscription/subscription_provider.dart';
import '../../../features/referral/providers/referral_provider.dart';
import '../../../shared/services/referral_service.dart';
import '../../../features/team/models/team_member_model.dart';
import '../../../features/team/widgets/team_company_info_card.dart';
import '../../../features/subscription/subscription_section.dart';
import '../../../shared/services/team_service.dart';
import '../../../shared/services/validation_pdf_service.dart';
import '../../../shared/widgets/zoomable_pdf_view.dart';
import '../../../shared/widgets/status_badge.dart';

// (M/J) Demande d'ouverture d'un SOUS-ONGLET précis de la page Équipe (0=Gérer,
// 1=Rapports, 2=Réglages équipe), avec déroulé optionnel de la carte « infos
// entreprise ». Le `nonce` force la réouverture même si la page Équipe est déjà
// construite (IndexedStack la garde vivante).
class TeamTabRequest {
  final int tab;
  final bool expandCompany;
  final int nonce;
  const TeamTabRequest(
      {required this.tab, this.expandCompany = false, required this.nonce});
}

final teamTabRequestProvider = StateProvider<TeamTabRequest?>((ref) => null);

class TeamDashboardScreen extends ConsumerStatefulWidget {
  const TeamDashboardScreen({super.key});

  @override
  ConsumerState<TeamDashboardScreen> createState() => _TeamDashboardScreenState();
}

class _TeamDashboardScreenState extends ConsumerState<TeamDashboardScreen> {
  String _filterStatus = 'all';

  @override
  Widget build(BuildContext context) {
    final teamAsync = ref.watch(teamStateProvider);
    final currentMember = ref.watch(currentMemberProvider).valueOrNull;

    // (1.1 / 2.3) AppBar avec retour sur TOUS les états (sinon les écrans
    // « pas d'équipe » / « en attente » / loading n'ont pas de bouton retour).
    AppBar teamAppBar() => AppBar(title: const Text('Mon équipe'));

    return teamAsync.when(
      loading: () => Scaffold(
        appBar: teamAppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: teamAppBar(),
        body: Center(child: Text('Erreur : $e')),
      ),
      data: (team) {
        if (!team.hasTeam) {
          return Scaffold(
            appBar: teamAppBar(),
            body: const _NoTeamPromoView(),
          );
        }

        if (currentMember?.isPending ?? false) {
          return Scaffold(
            appBar: teamAppBar(),
            body: _PendingApprovalView(
              companyName: team.companyName ?? 'l\'équipe',
            ),
          );
        }

        final canValidate =
            team.isAdmin || (currentMember?.canValidate ?? false);
        final seatLimit = ref.watch(companySeatLimitProvider);
        // (#7) Pastille de demandes en attente sur l'onglet « Gérer ».
        final pendingCount =
            ref.watch(teamPendingCountProvider).valueOrNull ?? 0;

        // (M/J) Sous-onglet demandé (depuis Mon compte / le toggle rapport…).
        final tabReq = ref.watch(teamTabRequestProvider);
        // (M2) Page Équipe à 3 onglets : Gérer · Rapports · Réglages équipe.
        return DefaultTabController(
          // Le nonce force la sélection même si la page est déjà construite.
          key: ValueKey(tabReq?.nonce ?? 0),
          length: 3,
          initialIndex: tabReq?.tab ?? 0,
          child: Scaffold(
            appBar: AppBar(
              title: Text(team.companyName ?? 'Équipe'),
              actions: [
                // (#11) Les 2 icônes badge (rapports en attente / demandes) sont
                // retirées : redondantes avec les onglets + la pastille du nav
                // tab Équipe. On garde un seul bouton de partage du code d'invit.
                if (team.inviteCode != null)
                  IconButton(
                    icon: const Icon(Icons.share_outlined),
                    tooltip: 'Partager le code d\'invitation',
                    onPressed: () => _showInviteShareDialog(
                        context, team.companyName, team.inviteCode!),
                  ),
              ],
              bottom: TabBar(
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicatorColor: AppColors.accent,
                tabs: [
                  // (#7) Même pastille « demandes en attente » que le nav tab :
                  // l'utilisateur voit directement qu'il faut aller dans « Gérer ».
                  Tab(
                    icon: Badge(
                      isLabelVisible: pendingCount > 0,
                      label: Text('$pendingCount'),
                      child: const Icon(Icons.groups_outlined),
                    ),
                    text: 'Gérer',
                  ),
                  const Tab(
                      icon: Icon(Icons.assignment_outlined), text: 'Rapports'),
                  const Tab(
                      icon: Icon(Icons.settings_outlined),
                      text: 'Réglages équipe'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                // ── Onglet 0 : GÉRER (membres + invitation + sièges) ───
                _TeamManageView(
                  companyId: team.companyId!,
                  isAdmin: team.isAdmin,
                  seatLimit: seatLimit,
                  inviteCode: team.inviteCode,
                  companyName: team.companyName,
                ),
                // ── Onglet 1 : RAPPORTS de l'équipe ────────────────────
                _TabColorStrip(
                  color: Colors.indigo.shade300,
                  child: Column(
                    children: [
                      if (team.isAdmin) _AdminDashboardHint(),
                      _FilterBar(
                        selectedStatus: _filterStatus,
                        onStatus: (s) => setState(() => _filterStatus = s),
                      ),
                      Expanded(
                        child: StreamBuilder<List<Map<String, dynamic>>>(
                          stream: TeamService().streamTeamReports(
                            team.companyId!,
                            technicianId: team.isAdmin ? null : _currentUid(),
                          ),
                          builder: (context, snap) {
                            if (snap.connectionState ==
                                    ConnectionState.waiting &&
                                !snap.hasData) {
                              return const Center(
                                  child: CircularProgressIndicator());
                            }
                            if (snap.hasError) {
                              return Center(
                                  child: Text('Erreur : ${snap.error}'));
                            }
                            final allReports = snap.data ?? [];
                            final filtered = _filterStatus == 'all'
                                ? allReports
                                : allReports
                                    .where((r) => r['status'] == _filterStatus)
                                    .toList();

                            return Column(
                              children: [
                                if (team.isAdmin && allReports.isNotEmpty)
                                  _StatsBar(reports: allReports),
                                Expanded(
                                  child: filtered.isEmpty
                                      ? const Center(
                                          child: Text('Aucun rapport.',
                                              style: TextStyle(
                                                  color: Colors.black54)))
                                      : ListView.separated(
                                          padding: const EdgeInsets.all(16),
                                          itemCount: filtered.length,
                                          separatorBuilder: (_, __) =>
                                              const SizedBox(height: 8),
                                          itemBuilder: (_, i) => _ReportTile(
                                            data: filtered[i],
                                            companyId: team.companyId!,
                                            canValidate: canValidate,
                                          ),
                                        ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                // ── Onglet 2 : RÉGLAGES de l'équipe ────────────────────
                _TeamSettingsView(
                  companyId: team.companyId!,
                  isAdmin: team.isAdmin,
                  seatLimit: seatLimit,
                  companyName: team.companyName,
                  // (J) Carte « infos entreprise » déroulée si demandé.
                  expandCompany:
                      tabReq?.tab == 2 && (tabReq?.expandCompany ?? false),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String? _currentUid() {
    try {
      return ref.read(firebaseUserProvider).valueOrNull?.uid;
    } catch (_) {
      return null;
    }
  }
}

// ─── Filter bar ───────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final String selectedStatus;
  final void Function(String) onStatus;

  const _FilterBar({required this.selectedStatus, required this.onStatus});

  @override
  Widget build(BuildContext context) {
    const options = [
      ('all', 'Tous'),
      ('submitted', 'Envoyés'),
      ('pendingValidation', 'À valider'),
      ('validated', 'Validés'),
    ];
    return Container(
      height: 44,
      color: Colors.white,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: options.map((o) {
          final selected = selectedStatus == o.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(o.$2),
              selected: selected,
              onSelected: (_) => onStatus(o.$1),
              selectedColor: AppColors.primary,
              labelStyle: TextStyle(
                color: selected ? Colors.white : Colors.black87,
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Report tile ──────────────────────────────────────────────────────────────

class _ReportTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final String companyId;
  final bool canValidate;

  const _ReportTile({
    required this.data,
    required this.companyId,
    required this.canValidate,
  });

  ReportStatus get _status => ReportStatus.values.firstWhere(
        (s) => s.name == (data['status'] ?? 'draft'),
        orElse: () => ReportStatus.draft,
      );

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ReportDetailSheet(
          data: data, companyId: companyId, canValidate: canValidate),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateRaw = data['date'] as String?;
    final date = dateRaw != null
        ? DateFormat('dd/MM/yyyy').format(DateTime.parse(dateRaw))
        : '—';
    final clientName = data['client_name'] ?? '—';
    final techName = data['technician_name'] ?? '';
    final reportNum = data['report_number'];
    final numStr =
        reportNum != null ? '#${reportNum.toString().padLeft(3, '0')}' : '';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showDetail(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (numStr.isNotEmpty) ...[
                          Text(numStr,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: AppColors.primary)),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(clientName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(date,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54)),
                    if (techName.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(techName,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black45)),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  StatusBadge(status: _status),
                  if (canValidate && _status == ReportStatus.submitted) ...[
                    const SizedBox(height: 6),
                    _ValidateButton(
                        companyId: companyId, reportId: data['id']),
                    const SizedBox(height: 4),
                    _RejectButton(
                        companyId: companyId, reportId: data['id']),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Stats bar (admin only) ───────────────────────────────────────────────────

class _StatsBar extends StatelessWidget {
  final List<Map<String, dynamic>> reports;
  const _StatsBar({required this.reports});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final weekStart = DateTime(now.year, now.month, now.day - (now.weekday - 1));

    int thisWeek = 0;
    int validated = 0;
    int submitted = 0;
    int rejected = 0;

    for (final r in reports) {
      final status = r['status'] as String? ?? '';
      final dateStr = (r['updated_at'] ?? r['created_at'] ?? '') as String;
      if (dateStr.isNotEmpty) {
        try {
          if (!DateTime.parse(dateStr).isBefore(weekStart)) thisWeek++;
        } catch (_) {}
      }
      if (status == 'validated') validated++;
      if (status == 'submitted') submitted++;
      if (status == 'rejected') rejected++;
    }

    final total = validated + rejected;
    final rate = total > 0 ? (validated / total * 100).round() : null;

    return Container(
      color: Colors.grey.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _Stat(label: 'Cette semaine', value: '$thisWeek',
              icon: Icons.calendar_today_outlined, color: AppColors.primary),
          const SizedBox(width: 8),
          _Stat(label: 'En attente', value: '$submitted',
              icon: Icons.hourglass_empty_outlined,
              color: submitted > 0 ? Colors.orange : Colors.grey),
          const SizedBox(width: 8),
          _Stat(label: 'Taux valid.', value: rate != null ? '$rate %' : '—',
              icon: Icons.verified_outlined,
              color: rate != null && rate >= 80 ? Colors.green : Colors.grey),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _Stat({required this.label, required this.value,
      required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      style: TextStyle(fontSize: 14,
                          fontWeight: FontWeight.bold, color: color)),
                  Text(label,
                      style: const TextStyle(fontSize: 10, color: Colors.black45),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Validate button ──────────────────────────────────────────────────────────

class _ValidateButton extends StatefulWidget {
  final String companyId;
  final String reportId;
  final VoidCallback? onSuccess;

  const _ValidateButton({
    required this.companyId,
    required this.reportId,
    this.onSuccess,
  });

  @override
  State<_ValidateButton> createState() => _ValidateButtonState();
}

class _ValidateButtonState extends State<_ValidateButton> {
  bool _loading = false;

  Future<void> _validate() async {
    setState(() => _loading = true);
    try {
      await TeamService()
          .updateReportStatus(widget.companyId, widget.reportId, 'validated');
      widget.onSuccess?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.statusValidated,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          textStyle: const TextStyle(fontSize: 11),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: _loading ? null : _validate,
        icon: _loading
            ? const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                    strokeWidth: 1.5, color: Colors.white))
            : const Icon(Icons.check, size: 14),
        label: const Text('Valider'),
      ),
    );
  }
}

// ─── Reject button ───────────────────────────────────────────────────────────

class _RejectButton extends StatefulWidget {
  final String companyId;
  final String reportId;

  const _RejectButton({required this.companyId, required this.reportId});

  @override
  State<_RejectButton> createState() => _RejectButtonState();
}

class _RejectButtonState extends State<_RejectButton> {
  bool _loading = false;

  Future<void> _reject() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dlg) => AlertDialog(
        title: const Text('Retourner le rapport'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Commentaire pour le technicien (optionnel) :',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Ex : Signature client manquante...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlg, null),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dlg, controller.text.trim()),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Retourner'),
          ),
        ],
      ),
    );
    if (result == null) return;
    setState(() => _loading = true);
    try {
      await TeamService().updateReportStatus(
        widget.companyId, widget.reportId, 'rejected',
        rejectionComment: result.isEmpty ? null : result,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.red,
          side: const BorderSide(color: Colors.red),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          textStyle: const TextStyle(fontSize: 11),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: _loading ? null : _reject,
        icon: _loading
            ? const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                    strokeWidth: 1.5, color: Colors.red))
            : const Icon(Icons.undo, size: 14),
        label: const Text('Retourner'),
      ),
    );
  }
}

// ─── (#11) Partage du code d'invitation depuis l'AppBar équipe ────────────────
void _showInviteShareDialog(
    BuildContext context, String? companyName, String inviteCode) {
  final name = (companyName != null && companyName.trim().isNotEmpty)
      ? companyName.trim()
      : null;
  final shareText =
      'Rejoignez ${name != null ? 'mon équipe "$name"' : 'notre équipe'} '
      'sur Compte Rendu Technique IA !\nCode d\'invitation : $inviteCode';
  showDialog(
    context: context,
    builder: (dlg) => AlertDialog(
      title: const Text('Inviter dans l\'équipe'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (name != null) ...[
            Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
          ],
          const Text('Code d\'invitation',
              style: TextStyle(fontSize: 11, color: Colors.black54)),
          SelectableText(
            inviteCode,
            style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 3,
                color: AppColors.primary),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dlg), child: const Text('Fermer')),
        FilledButton.icon(
          onPressed: () {
            Navigator.pop(dlg);
            Share.share(shareText);
          },
          icon: const Icon(Icons.share, size: 18),
          label: const Text('Partager'),
        ),
      ],
    ),
  );
}

// (#6) L'ancien dialog « Renommer l'équipe » a été retiré : le nom est
// désormais éditable directement dans le formulaire d'identité
// (TeamCompanyInfoCard), comme en solo.

// ─── (M2) Bandeau de couleur en haut de chaque onglet équipe ──────────────────
class _TabColorStrip extends StatelessWidget {
  final Color color;
  final Widget child;
  const _TabColorStrip({required this.color, required this.child});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Container(height: 3, color: color),
          Expanded(child: child),
        ],
      );
}

// ─── Onglet « Réglages équipe » : identité, voir rapports, abonnement ─────────
class _TeamSettingsView extends ConsumerWidget {
  final String companyId;
  final bool isAdmin;
  final int? seatLimit;
  final String? companyName;
  final bool expandCompany; // (J) déroule la carte « infos entreprise »
  const _TeamSettingsView({
    required this.companyId,
    required this.isAdmin,
    this.seatLimit,
    this.companyName,
    this.expandCompany = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reward100 = ref.watch(teamReward100Provider).valueOrNull ?? false;
    return _TabColorStrip(
      color: Colors.teal.shade300,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          // (#2b) Équipe sans responsable (CEO parti) → message + créer une équipe.
          _NoAdminBanner(companyId: companyId),
          // (S6) Récompense 100 parrainages débloquée 🎉
          // [PAUSED-REFERRAL] masquée tant que le parrainage est en pause.
          if (kParrainageEnabled && reward100)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  Colors.amber.shade100,
                  Colors.orange.shade100,
                ]),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.amber.shade400),
              ),
              child: Row(children: [
                const Text('🎉', style: TextStyle(fontSize: 30)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('100 parrainages actifs !',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Colors.orange.shade900)),
                      const SizedBox(height: 3),
                      Text(
                          'Votre équipe a débloqué une récompense spéciale 🏆 — '
                          'on vous contacte très vite. Bravo !',
                          style: TextStyle(
                              fontSize: 12, color: Colors.brown.shade700)),
                    ],
                  ),
                ),
              ]),
            ),

          // ── Identité de l'équipe : (#6) nom + infos en UN seul formulaire ─
          // (comme en solo). Le nom n'est plus une tuile « Renommer » séparée :
          // il est le 1er champ de la carte ci-dessous.
          const _TeamSettingsLabel('Identité de l\'équipe'),
          TeamCompanyInfoCard(
              companyId: companyId,
              isAdmin: isAdmin,
              initiallyExpanded: expandCompany),

          // (O) Infos PERSONNELLES du coéquipier (cet appareil) qui apparaissent
          // sur SES rapports d'équipe : son nom de technicien + son logo.
          const SizedBox(height: 14),
          const _TeamSettingsLabel('Vous, sur vos rapports d\'équipe'),
          const _TeammateIdentityCard(),

          // (#9) « Voir les rapports de l'équipe » retiré : l'onglet « Rapports »
          // juste à côté fait déjà le travail (redondant).

          // ── Abonnement : (#9) mené par la facturation, puis statut « Actif »
          // (avec ⚙️ → gérer), sièges, et l'abo solo en toute fin. ───────────
          const SizedBox(height: 16),
          const _TeamSettingsLabel('Abonnement'),
          // [PAUSED-REFERRAL] _TeamBillingCard affiche le modèle de prix Stripe
          // dégressif + le pool parrainage → masquée en IAP (le prix réel vient
          // du store/paywall). SubscriptionSection ci-dessous montre le statut.
          if (kParrainageEnabled && isAdmin && seatLimit != null) ...[
            _TeamBillingCard(companyId: companyId, nSeats: seatLimit!),
            const SizedBox(height: 10),
          ],
          const SubscriptionSection(scope: SubScope.team),
        ],
      ),
    );
  }
}

// (#5) Petit intitulé de section pour aligner/structurer « Réglages équipe ».
class _TeamSettingsLabel extends StatelessWidget {
  final String text;
  const _TeamSettingsLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 6),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
            color: Colors.grey.shade600,
          ),
        ),
      );
}

// (#2b) Bandeau « équipe sans responsable » : si plus aucun membre admin actif
// (le CEO est parti par un chemin qui n'a pas dissous l'équipe), on prévient les
// coéquipiers qu'ils doivent créer une nouvelle équipe (plus de gestion ni de
// paiement possible sans responsable).
class _NoAdminBanner extends StatelessWidget {
  final String companyId;
  const _NoAdminBanner({required this.companyId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TeamMemberModel>>(
      stream: TeamService().streamMembers(companyId),
      builder: (_, snap) {
        final members = snap.data;
        if (members == null || members.isEmpty) return const SizedBox.shrink();
        final hasActiveAdmin =
            members.any((m) => m.role == 'admin' && m.active);
        if (hasActiveAdmin) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.report_gmailerrorred_outlined,
                    color: Colors.red.shade700, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Équipe sans responsable',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade800)),
                ),
              ]),
              const SizedBox(height: 6),
              Text(
                'Le responsable de cette équipe est parti. Elle ne peut plus être '
                'gérée ni payée. Créez une nouvelle équipe — vos coéquipiers '
                'pourront vous y rejoindre avec le nouveau code.',
                style: TextStyle(fontSize: 12, color: Colors.red.shade900),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => context.go('/team-setup'),
                  icon: const Icon(Icons.add_business_outlined, size: 18),
                  label: const Text('Créer une nouvelle équipe'),
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.red.shade600),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// (O) Infos PERSONNELLES (cet appareil) du coéquipier sur SES rapports d'équipe :
// nom de technicien + logo. Le nom/SIRET de l'entreprise viennent, eux, de
// l'identité d'ÉQUIPE (synchronisée). Le logo n'est PAS synchronisé (fichier
// local) → note pour récupérer celui de l'admin.
class _TeammateIdentityCard extends ConsumerStatefulWidget {
  const _TeammateIdentityCard();
  @override
  ConsumerState<_TeammateIdentityCard> createState() =>
      _TeammateIdentityCardState();
}

class _TeammateIdentityCardState extends ConsumerState<_TeammateIdentityCard> {
  bool _picking = false;

  Future<void> _editName(String current) async {
    final v = await showSingleFieldDialog(
      context: context,
      title: 'Votre nom de technicien',
      initialValue: current,
      label: 'Nom du technicien',
      hint: 'Ex : Jean Dupont',
      textCapitalization: TextCapitalization.words,
    );
    if (v == null) return;
    // (#6) Champs DISTINCTS du solo : 'team_technician_name' / 'team_logo_path'
    // → éditer ici ne touche PAS l'identité solo.
    await ref
        .read(settingsProvider.notifier)
        .set('team_technician_name', v.trim());
  }

  Future<void> _pickLogo() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final picked = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          imageQuality: 90,
          maxWidth: 512,
          maxHeight: 512);
      if (picked == null) return;
      await ref
          .read(settingsProvider.notifier)
          .set('team_logo_path', picked.path);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _removeLogo() async {
    await ref.read(settingsProvider.notifier).set('team_logo_path', '');
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider).valueOrNull ?? {};
    // (#6) Champs propres à l'équipe (distincts du solo). Repli sur le solo s'ils
    // sont vides → pas de régression pour qui avait déjà rempli son nom/logo.
    final techName = (s['team_technician_name']?.toString().isNotEmpty ?? false)
        ? s['team_technician_name'].toString()
        : (s['technician_name'] ?? '').toString();
    final logoPath = (s['team_logo_path']?.toString().isNotEmpty ?? false)
        ? s['team_logo_path'].toString()
        : (s['logo_path'] ?? '').toString();
    final hasLogo =
        logoPath.isNotEmpty && !logoPath.startsWith('http') && File(logoPath).existsSync();

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.badge_outlined, color: AppColors.primary),
            title: const Text('Votre nom de technicien'),
            subtitle: Text(
              techName.isEmpty ? 'Appuyer pour définir' : techName,
              style: TextStyle(
                  fontSize: 12,
                  color: techName.isEmpty ? Colors.grey : Colors.black87),
            ),
            trailing:
                const Icon(Icons.edit_outlined, size: 18, color: Colors.grey),
            onTap: () => _editName(techName),
          ),
          const Divider(height: 1),
          ListTile(
            leading: hasLogo
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.file(File(logoPath),
                        width: 40, height: 40, fit: BoxFit.contain),
                  )
                : const Icon(Icons.add_photo_alternate_outlined,
                    color: AppColors.primary),
            title: const Text('Votre logo'),
            subtitle: Text(
              hasLogo
                  ? 'Affiché sur vos rapports d\'équipe'
                  : 'Aucun logo — appuyer pour choisir',
              style: TextStyle(
                  fontSize: 12, color: hasLogo ? Colors.green : Colors.grey),
            ),
            trailing: hasLogo
                ? IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.red, size: 20),
                    tooltip: 'Supprimer le logo',
                    onPressed: _picking ? null : _removeLogo,
                  )
                : (_picking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.edit_outlined,
                        size: 18, color: Colors.grey)),
            onTap: _picking ? null : _pickLogo,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Row(children: [
              Icon(Icons.info_outline, size: 13, color: Colors.grey.shade500),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Le logo n\'est PAS synchronisé (il reste sur votre appareil). '
                  'Demandez à l\'administrateur de vous envoyer le logo de '
                  'l\'entreprise pour l\'ajouter ici — ainsi vos rapports '
                  'd\'équipe l\'affichent.',
                  style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

// ─── Onglet « Gérer l'équipe » : membres, invitation, sièges ──────────────────
class _TeamManageView extends ConsumerWidget {
  final String companyId;
  final bool isAdmin;
  final int? seatLimit;
  final String? inviteCode;
  final String? companyName;

  const _TeamManageView({
    required this.companyId,
    required this.isAdmin,
    this.seatLimit,
    this.inviteCode,
    this.companyName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _TabColorStrip(
      color: AppColors.primary,
      child: StreamBuilder<List<TeamMemberModel>>(
        stream: TeamService().streamMembers(companyId),
        builder: (_, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Text('Erreur : ${snap.error}');
          }
          final members = snap.data ?? [];
          final pending = members.where((m) => m.isPending).toList();
          final active = members.where((m) => !m.isPending).toList();
          final activeCount = active.where((m) => m.active).length;

          return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text('Membres de l\'équipe',
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold)),
                          ),
                          if (seatLimit != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: activeCount >= seatLimit!
                                    ? Colors.orange.shade50
                                    : Colors.green.shade50,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: activeCount >= seatLimit!
                                      ? Colors.orange.shade200
                                      : Colors.green.shade200,
                                ),
                              ),
                              child: Text(
                                '$activeCount / $seatLimit sièges',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: activeCount >= seatLimit!
                                      ? Colors.orange.shade800
                                      : Colors.green.shade800,
                                ),
                              ),
                            ),
                        ],
                      ),
                      // (M2) Modifier le nb de sièges → onglet « Réglages » (2).
                      if (isAdmin) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                DefaultTabController.of(context).animateTo(2),
                            icon: const Icon(Icons.event_seat_outlined, size: 18),
                            label: const Text('Modifier le nombre de sièges'),
                          ),
                        ),
                      ],
                      if (isAdmin && inviteCode != null) ...[
                        const SizedBox(height: 12),
                        _InviteCodeCard(
                            inviteCode: inviteCode!, companyName: companyName),
                      ],

                      // ── Demandes en attente (admin) ───────────────────
                      if (isAdmin && pending.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Icon(Icons.pending_outlined,
                                size: 16, color: Colors.orange),
                            const SizedBox(width: 6),
                            Text(
                              'Demandes en attente (${pending.length})',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: Colors.orange),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ...pending.map((m) => _PendingMemberTile(
                              member: m,
                              companyId: companyId,
                              // (#9a) Sièges dispo ? (client) — bloque l'accept.
                              // sans siège ; le vrai blocage est côté CF.
                              seatLimit: seatLimit,
                              activeCount: activeCount,
                            )),
                        const Divider(height: 24),
                      ],

                      const SizedBox(height: 8),
                      if (isAdmin)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color:
                                    AppColors.primary.withValues(alpha: 0.18)),
                          ),
                          child: Row(children: [
                            Icon(Icons.info_outline,
                                size: 13,
                                color:
                                    AppColors.primary.withValues(alpha: 0.7)),
                            const SizedBox(width: 6),
                            const Expanded(
                              child: Text(
                                'Appuyez sur ··· pour modifier les droits d\'un membre.',
                                style: TextStyle(
                                    fontSize: 11, color: AppColors.primary),
                              ),
                            ),
                          ]),
                        ),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: active.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1),
                        itemBuilder: (_, i) => _MemberTile(
                          member: active[i],
                          companyId: companyId,
                          isAdmin: isAdmin,
                        ),
                      ),
                    ],
                  );
                },
      ),
    );
  }
}

// ─── Pending member tile ──────────────────────────────────────────────────────

class _PendingMemberTile extends StatefulWidget {
  final TeamMemberModel member;
  final String companyId;
  // (#9a) Sièges TOTAUX (mensuels + à vie) et nb de membres actifs, pour
  // refuser l'activation s'il n'y a pas de siège libre.
  final int? seatLimit;
  final int activeCount;

  const _PendingMemberTile({
    required this.member,
    required this.companyId,
    this.seatLimit,
    this.activeCount = 0,
  });

  @override
  State<_PendingMemberTile> createState() => _PendingMemberTileState();
}

class _PendingMemberTileState extends State<_PendingMemberTile> {
  bool _loading = false;

  Future<void> _approve() async {
    // (#9a) Garde-fou CLIENT : pas d'activation sans siège disponible.
    // (Le vrai blocage anti-fraude sera confirmé côté Cloud Function.)
    final limit = widget.seatLimit;
    final hasFreeSeat = limit != null && widget.activeCount < limit;
    if (!hasFreeSeat) {
      await showDialog<void>(
        context: context,
        builder: (dlg) => AlertDialog(
          icon: Icon(Icons.event_seat_outlined, color: Colors.orange.shade700),
          title: const Text('Aucun siège disponible'),
          content: Text(
            limit == null
                ? 'Vous devez d\'abord souscrire un abonnement équipe (avec au '
                    'moins un siège) pour activer un membre.\n\nLa personne peut '
                    'rester en attente : vous pourrez l\'accepter une fois '
                    'l\'abonnement en place.'
                : 'Tous les sièges sont occupés (${widget.activeCount}/$limit). '
                    'Ajoutez un siège (Réglages équipe → Gérer les sièges) avant '
                    'd\'accepter ce membre.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dlg),
                child: const Text('Fermer')),
            FilledButton(
              onPressed: () {
                Navigator.pop(dlg);
                DefaultTabController.of(context).animateTo(2); // Réglages équipe
              },
              child: const Text('Gérer l\'abonnement'),
            ),
          ],
        ),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await TeamService()
          .approveMember(widget.companyId, widget.member.uid);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reject() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dlg) => AlertDialog(
        title: const Text('Refuser la demande ?'),
        content:
            Text('${widget.member.displayName} ne rejoindra pas l\'équipe.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dlg, false),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(dlg, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Refuser'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await TeamService().removeMember(widget.companyId, widget.member.uid);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: Colors.orange.shade100,
        child: Text(
          m.displayName.isNotEmpty ? m.displayName[0].toUpperCase() : '?',
          style: TextStyle(
              color: Colors.orange.shade800, fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(m.displayName),
      subtitle: Text(m.email, style: const TextStyle(fontSize: 12)),
      trailing: _loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.check_circle_outline,
                      color: Colors.green),
                  tooltip: 'Approuver',
                  onPressed: _approve,
                ),
                IconButton(
                  icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                  tooltip: 'Refuser',
                  onPressed: _reject,
                ),
              ],
            ),
    );
  }
}

// ─── Active member tile ───────────────────────────────────────────────────────

class _MemberTile extends StatefulWidget {
  final TeamMemberModel member;
  final String companyId;
  final bool isAdmin;

  const _MemberTile({
    required this.member,
    required this.companyId,
    required this.isAdmin,
  });

  @override
  State<_MemberTile> createState() => _MemberTileState();
}

class _MemberTileState extends State<_MemberTile> {
  bool _loading = false;

  Future<void> _toggleActive() async {
    setState(() => _loading = true);
    try {
      await TeamService().setMemberActive(
        widget.companyId,
        widget.member.uid,
        !widget.member.active,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dlg) => AlertDialog(
        title: const Text('Retirer ce membre ?'),
        content: Text(
            '${widget.member.displayName} sera retiré de l\'équipe. '
            'Il devra rejoindre à nouveau avec le code d\'invitation.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlg, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dlg, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Retirer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await TeamService().removeMember(widget.companyId, widget.member.uid);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    }
  }

  void _showPermissionsMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _PermissionsSheet(
        member: widget.member,
        companyId: widget.companyId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    final canManage = widget.isAdmin && !m.isAdmin;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: m.isAdmin
            ? AppColors.primary
            : (m.active ? Colors.grey.shade300 : Colors.grey.shade100),
        child: Text(
          m.displayName.isNotEmpty ? m.displayName[0].toUpperCase() : '?',
          style: TextStyle(
            color: m.isAdmin
                ? Colors.white
                : (m.active ? Colors.black87 : Colors.grey),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(
        m.displayName,
        style: TextStyle(
          color: m.active ? Colors.black87 : Colors.grey,
          decoration: m.active ? null : TextDecoration.lineThrough,
        ),
      ),
      subtitle: Text(m.email, style: const TextStyle(fontSize: 12)),
      trailing: canManage
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Permission badges
                if (m.canValidate)
                  Tooltip(
                    message: 'Peut valider',
                    child: Icon(Icons.verified_outlined,
                        size: 16,
                        color: AppColors.primary.withValues(alpha: 0.7)),
                  ),
                if (m.canInvite)
                  Tooltip(
                    message: 'Peut inviter',
                    child: Icon(Icons.person_add_outlined,
                        size: 16,
                        color: AppColors.primary.withValues(alpha: 0.7)),
                  ),
                const SizedBox(width: 4),
                _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Switch(
                        value: m.active,
                        activeThumbColor: AppColors.primary,
                        onChanged: (_) => _toggleActive(),
                      ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'permissions') _showPermissionsMenu(context);
                    if (v == 'remove') _remove();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'permissions',
                      child: Row(
                        children: [
                          Icon(Icons.manage_accounts_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('Droits'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'remove',
                      child: Row(
                        children: [
                          Icon(Icons.person_remove_outlined,
                              size: 18, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Retirer',
                              style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            )
          : Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: m.isAdmin
                    ? AppColors.primary.withValues(alpha: 0.1)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                m.isAdmin ? 'Admin' : (m.active ? 'Tech' : 'Inactif'),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color:
                      m.isAdmin ? AppColors.primary : Colors.black54,
                ),
              ),
            ),
    );
  }
}

// ─── Permissions sheet ────────────────────────────────────────────────────────

class _PermissionsSheet extends StatefulWidget {
  final TeamMemberModel member;
  final String companyId;

  const _PermissionsSheet(
      {required this.member, required this.companyId});

  @override
  State<_PermissionsSheet> createState() => _PermissionsSheetState();
}

class _PermissionsSheetState extends State<_PermissionsSheet> {
  late bool _canValidate;
  late bool _canInvite;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _canValidate = widget.member.canValidate;
    _canInvite = widget.member.canInvite;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await TeamService().setMemberPermissions(
        widget.companyId,
        widget.member.uid,
        canValidate: _canValidate,
        canInvite: _canInvite,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Droits de ${widget.member.displayName}',
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Ces droits s\'ajoutent au rôle Tech.',
              style:
                  TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 16),
          SwitchListTile(
            value: _canValidate,
            onChanged: (v) => setState(() => _canValidate = v),
            title: const Text('Peut valider des rapports'),
            subtitle: const Text('Voit le bouton "Valider" sur les rapports envoyés'),
            secondary:
                const Icon(Icons.verified_outlined, color: AppColors.primary),
            activeThumbColor: AppColors.primary,
          ),
          SwitchListTile(
            value: _canInvite,
            onChanged: (v) => setState(() => _canInvite = v),
            title: const Text('Peut inviter des membres'),
            subtitle: const Text('Voit et peut partager le code d\'invitation'),
            secondary: const Icon(Icons.person_add_outlined,
                color: AppColors.primary),
            activeThumbColor: AppColors.primary,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Enregistrer'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── No-team promo view ───────────────────────────────────────────────────────

class _NoTeamPromoView extends ConsumerWidget {
  const _NoTeamPromoView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(firebaseUserProvider).valueOrNull;

    if (user == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 56, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                'Connectez-vous pour accéder à l\'espace équipe',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => context.go('/auth'),
                icon: const Icon(Icons.login),
                label: const Text('Se connecter'),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.groups_outlined,
                size: 44, color: AppColors.primary),
          ),
          const SizedBox(height: 20),
          const Text(
            'Travaillez en équipe',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Partagez, validez et suivez les comptes rendus de toute votre équipe en temps réel.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 32),
          _FeatureRow(
            icon: Icons.assignment_turned_in_outlined,
            color: Colors.green,
            title: 'Flux de validation',
            subtitle:
                'Les techs envoient leurs rapports, l\'admin valide ou retourne.',
          ),
          const SizedBox(height: 16),
          _FeatureRow(
            icon: Icons.people_outline,
            color: AppColors.primary,
            title: 'Gestion des membres',
            subtitle:
                'Invitez, activez/désactivez et gérez les droits de chaque technicien.',
          ),
          const SizedBox(height: 16),
          _FeatureRow(
            icon: Icons.bar_chart_outlined,
            color: Colors.orange,
            title: 'Statistiques équipe',
            subtitle:
                'Taux de validation, rapports par semaine, activité par membre.',
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => context.go('/team-setup'),
              icon: const Icon(Icons.add_business_outlined),
              label: const Text('Créer mon équipe'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.go('/team-setup'),
              icon: const Icon(Icons.group_add_outlined),
              label: const Text('Rejoindre une équipe existante'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  const _FeatureRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 22, color: color),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Pending approval view ────────────────────────────────────────────────────

class _PendingApprovalView extends StatelessWidget {
  final String companyName;
  const _PendingApprovalView({required this.companyName});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.hourglass_empty_outlined,
                  size: 38, color: Colors.orange.shade600),
            ),
            const SizedBox(height: 20),
            const Text(
              'Demande envoyée',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'En attente de validation par l\'administrateur de $companyName.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Text(
              'Vous recevrez une notification dès que votre accès sera activé.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Report detail sheet ──────────────────────────────────────────────────────

class _ReportDetailSheet extends StatelessWidget {
  final Map<String, dynamic> data;
  final String companyId;
  final bool canValidate;

  const _ReportDetailSheet({
    required this.data,
    required this.companyId,
    required this.canValidate,
  });

  ReportStatus get _status => ReportStatus.values.firstWhere(
        (s) => s.name == (data['status'] ?? 'draft'),
        orElse: () => ReportStatus.draft,
      );

  @override
  Widget build(BuildContext context) {
    final dateRaw = data['date'] as String?;
    final date = dateRaw != null
        ? DateFormat('dd MMMM yyyy', 'fr_FR').format(DateTime.parse(dateRaw))
        : '—';
    final endDateRaw = data['end_date'] as String?;
    final endDate = endDateRaw != null
        ? DateFormat('dd MMMM yyyy', 'fr_FR').format(DateTime.parse(endDateRaw))
        : null;

    Widget infoRow(String label, String? value) {
      if (value == null || value.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(label,
                  style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 12,
                      fontWeight: FontWeight.w500)),
            ),
            Expanded(
                child: Text(value, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (_, controller) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    data['client_name'] ?? '—',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                StatusBadge(status: _status),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                controller: controller,
                children: [
                  infoRow('Technicien', data['technician_name']),
                  infoRow('Date',
                      endDate != null ? 'Du $date au $endDate' : date),
                  infoRow('Adresse', data['client_address']),
                  infoRow('Contact', data['client_contact']),
                  infoRow('Contrat', data['contract_number']),
                  infoRow('Type', data['intervention_type']),
                  infoRow('Description', data['description']),
                  infoRow('Observations', data['observations']),
                  infoRow(
                      'Équipement',
                      [
                        data['equipment_type'],
                        data['equipment_brand'],
                        data['equipment_model'],
                        if ((data['equipment_serial'] ?? '').isNotEmpty)
                          'n° ${data['equipment_serial']}',
                      ]
                          .where((v) =>
                              v != null && (v as String).isNotEmpty)
                          .join(' – ')),
                  if (_status == ReportStatus.rejected &&
                      (data['rejection_comment'] ?? '').isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(Icons.feedback_outlined,
                                size: 14, color: Colors.red.shade700),
                            const SizedBox(width: 6),
                            Text('Commentaire de l\'admin',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red.shade700)),
                          ]),
                          const SizedBox(height: 4),
                          Text(data['rejection_comment'] as String,
                              style: TextStyle(
                                  fontSize: 13, color: Colors.red.shade900)),
                        ],
                      ),
                    ),
                  ],
                  // Validation PDF — shows frozen snapshot with photo placeholders
                  if (canValidate && data['snapshot'] != null) ...[
                    const SizedBox(height: 16),
                    _ValidationPdfButton(snapshot: data['snapshot'] as Map<String, dynamic>),
                  ],
                  if (canValidate &&
                      _status == ReportStatus.submitted) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                            child: _ValidateButton(
                              companyId: companyId,
                              reportId: data['id'],
                              onSuccess: () => Navigator.pop(context),
                            )),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _RejectButton(
                                companyId: companyId, reportId: data['id'])),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Validation PDF button ────────────────────────────────────────────────────

class _ValidationPdfButton extends StatefulWidget {
  final Map<String, dynamic> snapshot;
  const _ValidationPdfButton({required this.snapshot});

  @override
  State<_ValidationPdfButton> createState() => _ValidationPdfButtonState();
}

class _ValidationPdfButtonState extends State<_ValidationPdfButton> {
  bool _loading = false;

  Future<void> _generate() async {
    setState(() => _loading = true);
    try {
      final bytes = await ValidationPdfService.generate(widget.snapshot);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          // (1.3) Zoom garanti (boutons +/− + pan).
          builder: (_) => ZoomablePdfView(bytes: bytes, title: 'Aperçu rapport'),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur PDF : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // (3b) Bouton agrandi + la note (déplacée du haut) expliquée à l'intérieur.
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: _loading ? null : _generate,
            icon: _loading
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.picture_as_pdf_outlined, size: 20),
            label: Text(
              _loading ? 'Génération…' : 'Voir le rapport de validation (PDF)',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.info_outline, size: 13, color: Colors.grey.shade500),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Aperçu fidèle des métadonnées soumises par le technicien. '
                'Les photos restent sur son appareil (non transmises) — '
                'elles apparaissent en emplacements réservés dans le PDF. '
                'Utilisez les boutons +/− pour zoomer dans l\'aperçu.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

// ─── Invite code card (admin members sheet) ───────────────────────────────────

class _InviteCodeCard extends StatefulWidget {
  final String inviteCode;
  final String? companyName;
  const _InviteCodeCard({required this.inviteCode, this.companyName});

  @override
  State<_InviteCodeCard> createState() => _InviteCodeCardState();
}

class _InviteCodeCardState extends State<_InviteCodeCard> {
  String? _storeUrlAndroid;
  String? _storeUrlIos;

  static const _fallbackAndroid =
      'https://play.google.com/store/apps/details?id=com.tec.reportnew1cld';

  @override
  void initState() {
    super.initState();
    _loadStoreUrls();
  }

  Future<void> _loadStoreUrls() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _storeUrlAndroid = prefs.getString('store_url_android');
      _storeUrlIos = prefs.getString('store_url_ios');
    });
  }

  String get _deepLink =>
      'raptech://invite?code=${Uri.encodeComponent(widget.inviteCode)}';

  String _buildShareText() {
    final android = _storeUrlAndroid ?? _fallbackAndroid;
    final iosUrl = _storeUrlIos != null && _storeUrlIos!.isNotEmpty
        ? _storeUrlIos!
        : null;
    final iosLine = iosUrl != null
        ? '🍎 iOS : $iosUrl'
        : '🍎 iOS : cherchez "Compte Rendu Technique IA" sur l\'App Store';
    final teamLabel = widget.companyName != null
        ? 'mon équipe "${widget.companyName}"'
        : 'notre équipe';

    return 'Rejoignez $teamLabel sur Compte Rendu Technique IA !\n'
        'Code d\'invitation : ${widget.inviteCode}\n\n'
        '1. Téléchargez l\'app :\n'
        '📱 Android : $android\n'
        '$iosLine\n\n'
        '2. Une fois installée, ouvrez ce lien ou entrez le code manuellement :\n'
        '$_deepLink';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Code d\'invitation',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                widget.inviteCode,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 5,
                  color: AppColors.primary,
                  fontFamily: 'monospace',
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.copy_outlined, size: 20),
                tooltip: 'Copier le code',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: widget.inviteCode));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Code copié !')),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.share_outlined, size: 20),
                tooltip: 'Partager le lien',
                onPressed: () => Share.share(_buildShareText()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Admin dashboard hint ─────────────────────────────────────────────────────

class _AdminDashboardHint extends StatelessWidget {
  const _AdminDashboardHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.primary.withValues(alpha: 0.05),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 13, color: AppColors.primary.withValues(alpha: 0.6)),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Rapports de votre équipe — tous les rapports soumis par vos techniciens apparaissent ici.',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Team billing card ────────────────────────────────────────────────────────

class _TeamBillingCard extends ConsumerWidget {
  final String companyId;
  final int nSeats;
  const _TeamBillingCard({required this.companyId, required this.nSeats});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final poolCredits = ref.watch(teamPoolCreditsProvider).valueOrNull ?? 0;
    final nextPrice   = ref.watch(teamNextPricePreviewProvider);
    final toFloor     = ReferralService.activationsToFloor(poolCredits, nSeats: nSeats);

    final perSeatDisc = (ReferralService.kSlope * (nSeats - 1))
        .clamp(0.0, ReferralService.kFloor);
    final perSeat = ReferralService.kBase - perSeatDisc;
    final volumeBill = perSeat * nSeats;

    // (affichage) Réduction parrainage RÉELLE appliquée = ce qui a effectivement
    // baissé la facture (volume → prix final), bornée par le plancher. La remise
    // « nominale » (R×0,21) peut être supérieure si on est déjà au plancher :
    // dans ce cas une partie est SANS EFFET → on l'indique honnêtement.
    final floorBill = ReferralService.kFloor * nSeats;
    final nominalCredit = poolCredits * ReferralService.kPool;
    final effectiveCredit =
        (volumeBill - nextPrice).clamp(0.0, nominalCredit);
    final wastedCredit = nominalCredit - effectiveCredit;
    String eur(double v) => v.toStringAsFixed(2).replaceAll('.', ',');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.receipt_long_outlined, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Text('Facturation équipe',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                    color: AppColors.primary)),
          ]),
          const SizedBox(height: 8),
          _BillingRow('Volume ($nSeats sièges × ${eur(perSeat)} €)',
              '${eur(volumeBill)} €/mois'),
          if (poolCredits > 0)
            _BillingRow(
                'Parrainages externes ($poolCredits actif${poolCredits > 1 ? 's' : ''})',
                '−${eur(effectiveCredit)} €'),
          const Divider(height: 12),
          _BillingRow('Prochain paiement estimé', '${eur(nextPrice)} €/mois',
              bold: true),
          // Plancher atteint : surplus de parrainages sans effet → on le dit.
          if (wastedCredit > 0.001) ...[
            const SizedBox(height: 6),
            Text(
                '🛑 Plancher atteint (${eur(floorBill)} €). '
                'Au-delà, les parrainages ne baissent plus cette facture '
                '(−${eur(wastedCredit)} € sans effet).',
                style: TextStyle(fontSize: 10, color: Colors.orange.shade700)),
          ] else if (toFloor > 0) ...[
            const SizedBox(height: 6),
            Text(
                '+$toFloor invitation${toFloor > 1 ? 's' : ''} externe${toFloor > 1 ? 's' : ''} '
                'pour atteindre le plancher (${eur(floorBill)} €)',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
          ],
        ],
      ),
    );
  }
}

class _BillingRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const _BillingRow(this.label, this.value, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
        fontSize: 12,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        color: bold ? AppColors.primary : Colors.black87);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}
