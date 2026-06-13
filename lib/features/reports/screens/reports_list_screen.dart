import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../models/report_model.dart';
import '../providers/reports_provider.dart';
import '../providers/archive_provider.dart';
import '../../../shared/services/local_db_service.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/services/kill_switch_service.dart';
import '../../../shared/services/subscription_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../subscription/subscription_provider.dart';
import '../../subscription/paywall_bottom_sheet.dart';
import '../../../core/config/app_build.dart';
import '../../../shared/services/team_service.dart';
import '../providers/photo_request_provider.dart';
import '../../../shared/widgets/clients_icon.dart';
import '../../../shared/widgets/badged_icon.dart';

class ReportsListScreen extends ConsumerStatefulWidget {
  const ReportsListScreen({super.key});

  @override
  ConsumerState<ReportsListScreen> createState() => _ReportsListScreenState();
}

class _ReportsListScreenState extends ConsumerState<ReportsListScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showTeamView = false;
  // (bug Hero) Tag unique par instance d'écran : évite la collision
  // « multiple heroes share the same tag: fab_reports » quand un écran est
  // empilé au-dessus du shell (IndexedStack garde les branches montées).
  final Object _fabHeroTag = UniqueKey();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncTeamStatuses();
      _maybeOpenTeamPaywall();
    });
  }

  // Après création d'une équipe (drapeau posé par team_setup), rouvre le paywall
  // sur l'onglet équipe pour que le CEO s'abonne tout de suite.
  Future<void> _maybeOpenTeamPaywall() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('show_team_paywall') != true) return;
    await prefs.remove('show_team_paywall');
    if (mounted) PaywallBottomSheet.show(context, initialForTeam: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      KillSwitchService.clearCache();
      KillSwitchService.check().then((result) {
        if (!result.allowed && mounted) {
          context.go('/gate');
        }
      });
      _syncTeamStatuses();
    }
  }

  void _syncTeamStatuses() {
    final teamState = ref.read(teamStateProvider).valueOrNull;
    final user = ref.read(firebaseUserProvider).valueOrNull;
    if (teamState == null || !teamState.hasTeam || user == null) return;
    ref.read(reportsProvider.notifier).syncStatusFromTeam(
          teamState.companyId!,
          user.uid,
        );
  }

  Future<void> _showNewReportSheet(BuildContext context) async {
    final result = await KillSwitchService.check();
    if (!context.mounted) return;
    if (!result.allowed) {
      showDialog(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('Application indisponible'),
          content: Text(result.message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Fermer')),
          ],
        ),
      );
      return;
    }
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _NewReportSheet(onNew: () {
        Navigator.pop(ctx);
        context.push('/create-report');
      }),
    );
  }

  List<ReportModel> _filter(List<ReportModel> reports) {
    if (_searchQuery.isEmpty) return reports;
    return reports.where((r) {
      return r.clientName.toLowerCase().contains(_searchQuery) ||
          r.interventionType.toLowerCase().contains(_searchQuery) ||
          r.description.toLowerCase().contains(_searchQuery) ||
          (r.reportNumber > 0 &&
              r.reportNumber.toString().contains(_searchQuery));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final reportsAsync = ref.watch(reportsProvider);

    // (Profil) On n'aligne PLUS automatiquement la vue Rapports sur le profil
    // actif : à l'ouverture, on reste sur « Mes rapports » (perso), même avec
    // une équipe. Le basculement vers la vue Équipe se fait via le toggle
    // dédié de l'onglet (manuel). → on n'est jamais « envoyé direct » en équipe.

    // Merged team tab — only active when flag enabled and user has a team
    final teamState = kEnableTeamMergedTab
        ? ref.watch(teamStateProvider).valueOrNull
        : null;
    final showToggle = teamState != null && teamState.hasTeam;
    final currentMemberName = showToggle
        ? (ref.watch(currentMemberProvider).valueOrNull?.displayName ?? 'Admin')
        : '';

    // AppBar bottom height: toggle=44 + (personal: search≈48 + tabs≈48)
    final double appBarBottomHeight = showToggle
        ? (_showTeamView ? 44.0 : 140.0)
        : 96.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(_showTeamView ? 'Équipe' : 'Mes rapports'),
        leading: IconButton(
          icon: const HomeBackIcon(size: 22),
          tooltip: 'Accueil (page de garde)',
          onPressed: () => context.push('/welcome'),
        ),
        actions: [
          // In compact nav layout, show a Clients icon in the AppBar
          if (kEnableNewNavLayout)
            IconButton(
              icon: const ClientsIcon(size: 22),
              tooltip: 'Mes clients',
              onPressed: () => context.push('/clients'),
            ),
          // Profil (avatar + badge « P »), distinct de Clients (« C »)
          IconButton(
            icon: const ProfileIcon(size: 22),
            tooltip: 'Mon profil',
            onPressed: () => context.push('/profile-account'),
          ),
          // (B/L) Archive des rapports supprimés.
          if (!_showTeamView)
            IconButton(
              icon: const Icon(Icons.inventory_2_outlined, size: 22),
              tooltip: 'Archive (rapports supprimés)',
              onPressed: () => context.push('/archive'),
            ),
          // (simplification) Icône « Équipe » retirée de Rapports : l'équipe a
          // son propre onglet dans la barre du bas. Conservée en commentaire au
          // cas où on voudrait y revenir.
          // if (!showToggle)
          //   Consumer(builder: (context, ref, _) {
          //     final ts = ref.watch(teamStateProvider).valueOrNull;
          //     if (ts != null && ts.hasTeam) {
          //       return IconButton(
          //         icon: const Icon(Icons.group_outlined),
          //         tooltip: 'Équipe',
          //         onPressed: () => context.push('/team-dashboard'),
          //       );
          //     }
          //     return const SizedBox.shrink();
          //   }),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(appBarBottomHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showToggle)
                _TeamViewToggle(
                  showTeamView: _showTeamView,
                  onToggle: (v) => setState(() => _showTeamView = v),
                ),
              if (!_showTeamView) ...[
                // Search bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Rechercher (client, type, description…)',
                      hintStyle:
                          TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                      prefixIcon: Icon(Icons.search,
                          color: Colors.white.withValues(alpha: 0.7), size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear,
                                  color: Colors.white.withValues(alpha: 0.7),
                                  size: 18),
                              onPressed: () => _searchController.clear(),
                            )
                          : null,
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.15),
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.white),
                      ),
                    ),
                  ),
                ),
                TabBar(
                  controller: _tabController,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white60,
                  indicatorColor: AppColors.accent,
                  tabs: const [
                    Tab(text: 'Tous'),
                    Tab(text: 'En cours'),
                    Tab(text: 'Envoyés'),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      body: _showTeamView && showToggle
          ? Column(
              children: [
                const _AppBanner(),
                Expanded(
                  child: _TeamReportsMergedSection(
                    companyId: teamState.companyId ?? '',
                    isAdmin: teamState.isAdmin,
                    currentUid:
                        ref.read(firebaseUserProvider).valueOrNull?.uid ?? '',
                    currentMemberName: currentMemberName,
                  ),
                ),
              ],
            )
          : Column(
              children: [
                // Developer broadcast banner
                const _AppBanner(),
                // Pending approval banner for new team members
                Consumer(builder: (context, ref, _) {
                  final member = ref.watch(currentMemberProvider).valueOrNull;
                  if (member == null || !member.isPending) {
                    return const SizedBox.shrink();
                  }
                  return _PendingApprovalBanner();
                }),
                // Export quota counter
                const _ExportQuotaBanner(),
                Expanded(
                  child: reportsAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Erreur: $e')),
                    data: (allReports) {
                      // (B/L) On masque les rapports archivés (supprimés) de la
                      // liste principale ; ils restent dans l'onglet Archive.
                      final archived = ref.watch(archivedReportsProvider);
                      final reports = allReports
                          .where((r) => !archived.contains(r.id))
                          .toList();
                      final drafts = reports
                          .where((r) => r.status == ReportStatus.draft)
                          .toList();
                      final submitted = reports
                          .where((r) =>
                              r.status == ReportStatus.submitted ||
                              r.status == ReportStatus.pendingValidation ||
                              r.status == ReportStatus.validated ||
                              r.status == ReportStatus.rejected)
                          .toList();

                      return TabBarView(
                        controller: _tabController,
                        children: [
                          _ReportsList(reports: _filter(reports)),
                          _ReportsList(reports: _filter(drafts)),
                          _ReportsList(reports: _filter(submitted)),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
      floatingActionButton: _showTeamView
          ? null
          : FloatingActionButton.extended(
              heroTag: _fabHeroTag,
              onPressed: () => _showNewReportSheet(context),
              icon: const Icon(Icons.add),
              label: const Text('Nouveau rapport'),
            ),
    );
  }
}

// ─── Export quota banner ──────────────────────────────────────────────────────

class _ExportQuotaBanner extends ConsumerStatefulWidget {
  const _ExportQuotaBanner();

  static Future<int> _readUsed() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final key = 'pdf_export_count_${now.year}_${now.month.toString().padLeft(2, '0')}';
    return prefs.getInt(key) ?? 0;
  }

  @override
  ConsumerState<_ExportQuotaBanner> createState() => _ExportQuotaBannerState();
}

class _ExportQuotaBannerState extends ConsumerState<_ExportQuotaBanner>
    with WidgetsBindingObserver {
  late Future<int> _future;

  @override
  void initState() {
    super.initState();
    _future = _ExportQuotaBanner._readUsed();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      // Bloc (pas arrow) → la closure ne RENVOIE pas le Future assigné.
      setState(() {
        _future = _ExportQuotaBanner._readUsed();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPro = ref.watch(effectiveSubscriptionProvider);

    if (isPro) {
      return Container(
        color: AppColors.primary.withValues(alpha: 0.07),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.all_inclusive, size: 14, color: AppColors.primary),
            const SizedBox(width: 8),
            const Text(
              'Exports illimités',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('PRO',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1)),
            ),
          ],
        ),
      );
    }

    return FutureBuilder<int>(
      future: _future,
      builder: (context, snap) {
        final used = snap.data ?? 0;
        final limit = SubscriptionService.freeMonthlyExports;
        final remaining = (limit - used).clamp(0, limit);
        final isNearLimit = remaining <= 1;
        return Container(
          color: isNearLimit
              ? Colors.orange.withValues(alpha: 0.08)
              : Colors.grey.withValues(alpha: 0.06),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Icon(
                Icons.picture_as_pdf_outlined,
                size: 14,
                color: isNearLimit ? Colors.orange.shade700 : Colors.grey.shade600,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$used export${used != 1 ? 's' : ''} ce mois · $remaining restant${remaining != 1 ? 's' : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isNearLimit ? Colors.orange.shade700 : Colors.grey.shade700,
                    fontWeight: isNearLimit ? FontWeight.w500 : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── New report bottom sheet ──────────────────────────────────────────────────

class _NewReportSheet extends StatefulWidget {
  final VoidCallback onNew;
  const _NewReportSheet({required this.onNew});

  @override
  State<_NewReportSheet> createState() => _NewReportSheetState();
}

class _NewReportSheetState extends State<_NewReportSheet> {
  List<ReportPreset>? _templates;
  bool _showTemplates = false;

  @override
  void initState() {
    super.initState();
    LocalDbService().getAllPresets().then((t) {
      if (mounted) setState(() => _templates = t);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Nouveau rapport',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: widget.onNew,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Rapport vierge'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => setState(() => _showTemplates = !_showTemplates),
            icon: const Icon(Icons.copy_outlined),
            label: Text(_showTemplates ? 'Masquer les modèles' : 'Depuis un modèle'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
          if (_showTemplates) ...[
            const SizedBox(height: 12),
            if (_templates == null)
              const Center(child: CircularProgressIndicator())
            else if (_templates!.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('Aucun modèle enregistré.\nSauvegardez un rapport comme modèle depuis son écran de détail.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
              )
            else
              LimitedBox(
                maxHeight: 240,
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _templates!.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final t = _templates![i];
                    return ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: Text(t.name),
                      subtitle: Text(
                          'Créé le ${t.createdAt.day.toString().padLeft(2, '0')}/${t.createdAt.month.toString().padLeft(2, '0')}/${t.createdAt.year}',
                          style: const TextStyle(fontSize: 12)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.pop(context);
                        context.push('/create-report', extra: t);
                      },
                    );
                  },
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ─── Reports list ─────────────────────────────────────────────────────────────

class _ReportsList extends StatelessWidget {
  final List<ReportModel> reports;

  const _ReportsList({required this.reports});

  @override
  Widget build(BuildContext context) {
    if (reports.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.assignment_outlined,
                size: 72, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'Aucun rapport',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: Colors.grey.shade500),
            ),
            const SizedBox(height: 6),
            Text(
              'Créez votre premier bon d\'intervention.',
              style:
                  TextStyle(color: Colors.grey.shade400, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {},
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: reports.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) => _ReportCard(report: reports[i]),
      ),
    );
  }
}

class _ReportCard extends ConsumerWidget {
  final ReportModel report;

  const _ReportCard({required this.report});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateStr =
        DateFormat('dd/MM/yyyy', 'fr_FR').format(report.date);
    final numStr = report.reportNumber > 0
        ? '#${report.reportNumber.toString().padLeft(3, '0')}'
        : '';
    final photoRequestIds =
        ref.watch(photoRequestIdsProvider).valueOrNull ?? {};
    final hasPhotoRequest = photoRequestIds.contains(report.id);

    return Card(
      child: InkWell(
        onTap: () => context.push('/report/${report.id}'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (numStr.isNotEmpty) ...[
                    Text(
                      numStr,
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.primary.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      report.clientName.isEmpty
                          ? 'Client non renseigné'
                          : report.clientName,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  StatusBadge(status: report.status),
                ],
              ),
              if (report.interventionType.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  report.interventionType,
                  style: TextStyle(
                      color: Colors.grey.shade600, fontSize: 13),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.calendar_today,
                      size: 14, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Text(dateStr,
                      style: TextStyle(
                          color: Colors.grey.shade500, fontSize: 13)),
                  if (report.sector != SectorTemplate.generic) ...[
                    const SizedBox(width: 12),
                    Icon(Icons.label_outline,
                        size: 14, color: Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Text(
                      report.sector.label,
                      style: TextStyle(
                          color: Colors.grey.shade500, fontSize: 13),
                    ),
                  ],
                  if (hasPhotoRequest) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        border:
                            Border.all(color: Colors.orange.shade300),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.camera_alt,
                              size: 11,
                              color: Colors.orange.shade700),
                          const SizedBox(width: 3),
                          Text(
                            'Photos dem.',
                            style: TextStyle(
                                fontSize: 10,
                                color: Colors.orange.shade700,
                                fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (report.photosPaths.isNotEmpty) ...[
                    Icon(Icons.photo_camera,
                        size: 14,
                        color: AppColors.primary.withValues(alpha: 0.6)),
                    const SizedBox(width: 3),
                    Text(
                      '${report.photosPaths.length}',
                      style: TextStyle(
                        color: AppColors.primary.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (report.signatureClientData != null)
                    _SignatureThumbnail(data: report.signatureClientData!),
                  if (report.aiEnhanced) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.auto_awesome,
                        size: 13, color: Colors.amber.shade600),
                  ],
                ],
              ),
              if (report.status == ReportStatus.draft) ...[
                const SizedBox(height: 8),
                _DraftProgress(report: report),
              ],
              // (3) Rapport rejeté → CTA « Corriger » bien visible (ouvre le
              // détail où se trouvent le commentaire admin + Modifier/Renvoyer).
              if (report.status == ReportStatus.rejected) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: () => context.push('/report/${report.id}'),
                    icon: const Icon(Icons.build_outlined, size: 18),
                    label: const Text('Corriger et renvoyer'),
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          AppColors.statusRejected.withValues(alpha: 0.12),
                      foregroundColor: AppColors.statusRejected,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SignatureThumbnail extends StatelessWidget {
  final String data;
  const _SignatureThumbnail({required this.data});

  @override
  Widget build(BuildContext context) {
    try {
      final bytes = base64Decode(data);
      return Container(
        width: 48,
        height: 20,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(3),
          color: Colors.white,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: Image.memory(bytes, fit: BoxFit.contain),
        ),
      );
    } catch (_) {
      return Icon(Icons.draw, size: 14, color: AppColors.success.withValues(alpha: 0.7));
    }
  }
}

class _DraftProgress extends StatelessWidget {
  final ReportModel report;
  const _DraftProgress({required this.report});

  // 5 key sections (dots)
  int get _sectionScore {
    int s = 0;
    if (report.clientName.isNotEmpty) s++;
    if (report.interventionType.isNotEmpty) s++;
    if (report.description.isNotEmpty) s++;
    if (report.equipmentType.isNotEmpty) s++;
    if (report.photosPaths.isNotEmpty ||
        report.signatureClientData != null ||
        report.signatureTechData != null ||
        report.materials.isNotEmpty) { s++; }
    return s;
  }

  // Total individual elements filled
  int get _totalFilled {
    int n = 0;
    for (final s in [
      report.clientName, report.clientAddress, report.clientPhone,
      report.clientContact, report.contractNumber, report.interventionType,
      report.description, report.observations, report.equipmentType,
      report.equipmentBrand, report.equipmentModel, report.equipmentSerial,
    ]) {
      if (s.isNotEmpty) n++;
    }
    if (report.laborHours != null) n++;
    if (report.laborRate != null) n++;
    n += report.photosPaths.length;
    n += report.materials.length;
    n += report.sectorFields.values.where((v) => v.toString().isNotEmpty).length;
    if (report.signatureClientStartData != null) n++;
    if (report.signatureTechStartData != null) n++;
    if (report.signatureClientData != null) n++;
    if (report.signatureTechData != null) n++;
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final score = _sectionScore;
    final total = _totalFilled;
    return Row(
      children: [
        Text(
          'Avancement ',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
        ),
        ...List.generate(5, (i) => Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: i < score
                ? AppColors.primary.withValues(alpha: 0.65)
                : Colors.grey.shade200,
          ),
        )),
        if (total > 0) ...[
          const SizedBox(width: 6),
          Text(
            '· $total élément${total > 1 ? 's' : ''}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
          ),
        ],
      ],
    );
  }
}

class _PendingApprovalBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.pending_outlined, color: Colors.amber.shade700, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Votre accès à l\'équipe est en attente d\'approbation par l\'administrateur.',
              style: TextStyle(
                  fontSize: 13, color: Colors.amber.shade800),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Developer broadcast banner ───────────────────────────────────────────────
// Reads current_banner_id + current_banner_message from SharedPrefs (written by gate_screen).
// Hidden until gate saves a non-empty banner_id. Dismissed state persisted per banner_id.

class _AppBanner extends StatefulWidget {
  const _AppBanner();
  @override
  State<_AppBanner> createState() => _AppBannerState();
}

class _AppBannerState extends State<_AppBanner> {
  String? _bannerId;
  String? _bannerMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('current_banner_id');
    final msg = prefs.getString('current_banner_message');
    if (id == null || id.isEmpty || msg == null || msg.isEmpty) return;
    final dismissed = prefs.getBool('dismissed_banner_$id') ?? false;
    if (dismissed) return;
    if (mounted) setState(() { _bannerId = id; _bannerMessage = msg; });
  }

  Future<void> _dismiss() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dismissed_banner_$_bannerId', true);
    if (mounted) setState(() { _bannerId = null; _bannerMessage = null; });
  }

  @override
  Widget build(BuildContext context) {
    if (_bannerId == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.campaign_outlined, color: AppColors.primary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _bannerMessage!,
              style: TextStyle(fontSize: 13, color: AppColors.primary),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 16, color: AppColors.primary.withValues(alpha: 0.6)),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: _dismiss,
          ),
        ],
      ),
    );
  }
}

// ─── Team view toggle ─────────────────────────────────────────────────────────

class _TeamViewToggle extends StatelessWidget {
  final bool showTeamView;
  final void Function(bool) onToggle;
  const _TeamViewToggle({required this.showTeamView, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ToggleButtons(
            isSelected: [!showTeamView, showTeamView],
            onPressed: (i) => onToggle(i == 1),
            borderRadius: BorderRadius.circular(20),
            selectedColor: AppColors.primary,
            fillColor: Colors.white,
            color: Colors.white70,
            borderColor: Colors.white.withValues(alpha: 0.4),
            selectedBorderColor: Colors.white,
            constraints: const BoxConstraints(minHeight: 30, minWidth: 110),
            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            children: const [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('Mes rapports'),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('Équipe'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Team merged reports section ──────────────────────────────────────────────

class _TeamReportsMergedSection extends ConsumerWidget {
  final String companyId;
  final bool isAdmin;
  final String currentUid;
  final String currentMemberName;

  const _TeamReportsMergedSection({
    required this.companyId,
    required this.isAdmin,
    required this.currentUid,
    required this.currentMemberName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: TeamService().streamTeamReports(companyId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Erreur : ${snap.error}'));
        }
        final reports = snap.data ?? [];
        if (reports.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.group_work_outlined,
                    size: 64, color: Colors.grey.shade300),
                const SizedBox(height: 12),
                Text(
                  'Aucun rapport dans l\'équipe.',
                  style:
                      TextStyle(color: Colors.grey.shade500, fontSize: 14),
                ),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: reports.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _TeamMergedTile(
            data: reports[i],
            companyId: companyId,
            isAdmin: isAdmin,
            currentUid: currentUid,
            currentMemberName: currentMemberName,
          ),
        );
      },
    );
  }
}

// ─── Team merged tile ─────────────────────────────────────────────────────────

class _TeamMergedTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final String companyId;
  final bool isAdmin;
  final String currentUid;
  final String currentMemberName;

  const _TeamMergedTile({
    required this.data,
    required this.companyId,
    required this.isAdmin,
    required this.currentUid,
    required this.currentMemberName,
  });

  ReportStatus get _status => ReportStatus.values.firstWhere(
        (s) => s.name == (data['status'] as String? ?? 'draft'),
        orElse: () => ReportStatus.draft,
      );

  bool get _isOwnReport =>
      (data['technician_id'] as String? ?? '') == currentUid;

  void _onTap(BuildContext context) {
    if (!isAdmin && !_isOwnReport) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Accès limité — consultez uniquement vos propres rapports.'),
        ),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _MergedReportDetailSheet(
        data: data,
        companyId: companyId,
        isAdmin: isAdmin,
        currentMemberName: currentMemberName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateRaw = data['date'] as String?;
    final date = dateRaw != null
        ? DateFormat('dd/MM/yyyy').format(DateTime.parse(dateRaw))
        : '—';
    final clientName = data['client_name'] as String? ?? '—';
    final techName = data['technician_name'] as String? ?? '';
    final reportNum = data['report_number'];
    final numStr = reportNum != null
        ? '#${reportNum.toString().padLeft(3, '0')}'
        : '';
    final hasPhotoRequest =
        (data['photo_request_by'] as String? ?? '').isNotEmpty;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _isOwnReport
              ? AppColors.primary.withValues(alpha: 0.35)
              : Colors.grey.shade200,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _onTap(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
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
                    ]),
                    const SizedBox(height: 3),
                    Text(date,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54)),
                    if (techName.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        techName,
                        style: TextStyle(
                          fontSize: 11,
                          color: _isOwnReport
                              ? AppColors.primary.withValues(alpha: 0.75)
                              : Colors.black38,
                          fontStyle: _isOwnReport
                              ? FontStyle.normal
                              : FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  StatusBadge(status: _status),
                  if (isAdmin) ...[
                    const SizedBox(height: 6),
                    _PhotoRequestButton(
                      companyId: companyId,
                      reportId: data['id'] as String,
                      adminName: currentMemberName,
                      hasRequest: hasPhotoRequest,
                    ),
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

// ─── Merged report detail sheet ───────────────────────────────────────────────

class _MergedReportDetailSheet extends StatelessWidget {
  final Map<String, dynamic> data;
  final String companyId;
  final bool isAdmin;
  final String currentMemberName;

  const _MergedReportDetailSheet({
    required this.data,
    required this.companyId,
    required this.isAdmin,
    required this.currentMemberName,
  });

  ReportStatus get _status => ReportStatus.values.firstWhere(
        (s) => s.name == (data['status'] as String? ?? 'draft'),
        orElse: () => ReportStatus.draft,
      );

  @override
  Widget build(BuildContext context) {
    // Admin sees the frozen submission snapshot if available
    final snap = isAdmin ? (data['snapshot'] as Map<String, dynamic>?) : null;
    final d = snap ?? data;

    final dateRaw = (d['date'] as String?) ?? (data['date'] as String?);
    final date = dateRaw != null
        ? DateFormat('dd MMMM yyyy', 'fr_FR').format(DateTime.parse(dateRaw))
        : '—';
    final techName = d['technician_name'] as String? ?? '';
    final rejectionComment = data['rejection_comment'] as String? ?? '';
    final hasPhotoRequest =
        (data['photo_request_by'] as String? ?? '').isNotEmpty;
    final photoCount = d['photo_count'] as int? ?? 0;

    Widget infoRow(String label, String? value) {
      if (value == null || value.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
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
      initialChildSize: 0.65,
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
            Row(children: [
              Expanded(
                child: Text(
                  d['client_name'] as String? ?? '—',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              StatusBadge(status: _status),
            ]),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                controller: controller,
                children: [
                  if (techName.isNotEmpty) infoRow('Technicien', techName),
                  infoRow('Date', date),
                  if (isAdmin) ...[
                    infoRow('Adresse', d['client_address'] as String?),
                    infoRow('Contact', d['client_contact'] as String?),
                    infoRow('Contrat', d['contract_number'] as String?),
                    infoRow('Type', d['intervention_type'] as String?),
                    infoRow('Description', d['description'] as String?),
                    infoRow('Observations', d['observations'] as String?),
                    infoRow(
                        'Équipement',
                        [
                          d['equipment_type'],
                          d['equipment_brand'],
                          d['equipment_model'],
                          if ((d['equipment_serial'] ?? '').toString().isNotEmpty)
                            'n° ${d['equipment_serial']}',
                        ]
                            .where((v) => v != null && (v as String).isNotEmpty)
                            .join(' – ')),
                    if (photoCount > 0) ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        const Icon(Icons.photo_camera_outlined,
                            size: 14, color: Colors.black38),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '$photoCount photo${photoCount > 1 ? 's' : ''} — stockées sur l\'appareil du technicien',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black38),
                          ),
                        ),
                      ]),
                    ],
                  ],
                  if (_status == ReportStatus.rejected &&
                      rejectionComment.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Text(rejectionComment,
                          style: TextStyle(
                              fontSize: 13, color: Colors.red.shade900)),
                    ),
                  ],
                  if (isAdmin) ...[
                    const SizedBox(height: 16),
                    hasPhotoRequest
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: Colors.blue.shade200),
                            ),
                            child: Row(children: [
                              Icon(Icons.hourglass_empty,
                                  size: 14,
                                  color: Colors.blue.shade600),
                              const SizedBox(width: 8),
                              Text(
                                'Demande de photos envoyée au technicien.',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.blue.shade800),
                              ),
                            ]),
                          )
                        : _PhotoRequestButton(
                            companyId: companyId,
                            reportId: data['id'] as String,
                            adminName: currentMemberName,
                            hasRequest: false,
                            fullWidth: true,
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

// ─── Photo request button ─────────────────────────────────────────────────────

class _PhotoRequestButton extends StatefulWidget {
  final String companyId;
  final String reportId;
  final String adminName;
  final bool hasRequest;
  final bool fullWidth;

  const _PhotoRequestButton({
    required this.companyId,
    required this.reportId,
    required this.adminName,
    required this.hasRequest,
    this.fullWidth = false,
  });

  @override
  State<_PhotoRequestButton> createState() => _PhotoRequestButtonState();
}

class _PhotoRequestButtonState extends State<_PhotoRequestButton> {
  bool _loading = false;

  Future<void> _request() async {
    setState(() => _loading = true);
    try {
      await TeamService().requestPhotos(
        widget.companyId,
        widget.reportId,
        widget.adminName,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Demande de photos envoyée au technicien.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.fullWidth ? 44.0 : 26.0;
    final iconSize = widget.fullWidth ? 16.0 : 12.0;
    final fontSize = widget.fullWidth ? 13.0 : 10.0;
    final hPad = widget.fullWidth ? 16.0 : 8.0;

    if (widget.hasRequest) {
      return SizedBox(
        height: height,
        width: widget.fullWidth ? double.infinity : null,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.blue.shade400,
            side: BorderSide(color: Colors.blue.shade200),
            padding:
                EdgeInsets.symmetric(horizontal: hPad),
            textStyle: TextStyle(fontSize: fontSize),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: null,
          icon: Icon(Icons.hourglass_empty, size: iconSize),
          label: Text(widget.fullWidth ? 'Demande envoyée' : 'Photos dem.'),
        ),
      );
    }

    return SizedBox(
      height: height,
      width: widget.fullWidth ? double.infinity : null,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.blue.shade700,
          side: BorderSide(color: Colors.blue.shade300),
          padding: EdgeInsets.symmetric(horizontal: hPad),
          textStyle: TextStyle(fontSize: fontSize),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: _loading ? null : _request,
        icon: _loading
            ? SizedBox(
                width: iconSize,
                height: iconSize,
                child: const CircularProgressIndicator(strokeWidth: 1.5))
            : Icon(Icons.photo_camera_outlined, size: iconSize),
        label: const Text('Dem. photos'),
      ),
    );
  }
}
