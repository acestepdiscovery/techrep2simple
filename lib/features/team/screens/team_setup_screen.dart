import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../subscription/paywall_bottom_sheet.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/services/team_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../settings/providers/settings_provider.dart';

class TeamSetupScreen extends ConsumerStatefulWidget {
  final String? initialInviteCode;
  const TeamSetupScreen({super.key, this.initialInviteCode});

  @override
  ConsumerState<TeamSetupScreen> createState() => _TeamSetupScreenState();
}

class _TeamSetupScreenState extends ConsumerState<TeamSetupScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _createFormKey = GlobalKey<FormState>();
  final _joinFormKey = GlobalKey<FormState>();

  // Create tab
  final _companyNameCreate = TextEditingController();

  // Join tab — (#3) plus de champ « nom », on rejoint par CODE SEUL.
  final _inviteCode = TextEditingController();

  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    if (widget.initialInviteCode != null && widget.initialInviteCode!.isNotEmpty) {
      _inviteCode.text = widget.initialInviteCode!.toUpperCase();
      WidgetsBinding.instance.addPostFrameCallback((_) => _tabs.animateTo(1));
    } else {
      _applyTeamIntent();
    }
  }

  Future<void> _applyTeamIntent() async {
    final prefs = await SharedPreferences.getInstance();
    final intent = prefs.getString('team_intent');
    if (intent == 'join') {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tabs.animateTo(1));
    }
    await prefs.remove('team_intent');
  }

  @override
  void dispose() {
    _tabs.dispose();
    _companyNameCreate.dispose();
    _inviteCode.dispose();
    super.dispose();
  }

  User get _user => FirebaseAuth.instance.currentUser!;

  Future<void> _createCompany() async {
    if (!_createFormKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      final company = await TeamService().createCompany(
        name: _companyNameCreate.text.trim(),
        adminUid: _user.uid,
        adminEmail: _user.email ?? '',
        adminDisplayName: _user.displayName ?? _user.email ?? '',
      );
      await ref.read(teamStateProvider.notifier).saveTeam(company, 'admin');
      await ref
          .read(settingsProvider.notifier)
          .set('company_name', company.name);
      if (mounted) {
        _showInviteCodeDialog(company.inviteCode, company.name, () async {
          // (3a) Si la création d'équipe a été lancée DEPUIS le paywall, on rouvre
          // le paywall (onglet équipe) pour que l'admin s'abonne tout de suite, PUIS
          // on retourne à l'accueil. Sinon (page de garde) → directement l'accueil.
          final prefs = await SharedPreferences.getInstance();
          final fromPaywall = prefs.getBool('team_from_paywall') ?? false;
          await prefs.remove('team_from_paywall');
          if (!mounted) return;
          if (fromPaywall) {
            await PaywallBottomSheet.show(context, initialForTeam: true);
            if (!mounted) return;
          }
          context.go('/home');
        });
      }
    } catch (e) {
      setState(() { _error = 'common_error'.tr(args: ['$e']); });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<void> _joinCompany() async {
    if (!_joinFormKey.currentState!.validate()) return;

    // (#3) Déjà dans une équipe ? Rejoindre une autre = QUITTER l'actuelle.
    final current = ref.read(teamStateProvider).valueOrNull;
    if (current?.hasTeam ?? false) {
      if (current!.isAdmin) {
        // CEO : compter les autres membres.
        int others = 0;
        try {
          final members = await TeamService().getMembers(current.companyId!);
          others = members.where((m) => m.uid != _user.uid).length;
        } catch (_) {}
        if (!mounted) return;
        if (others > 0) {
          // Bloqué : il orphelinerait son équipe.
          await showDialog<void>(
            context: context,
            builder: (dlg) => AlertDialog(
              icon: Icon(Icons.groups_outlined, color: Colors.orange.shade700),
              title: Text('pw_you_are_admin'.tr()),
              content: Text(
                'ts_admin_block_desc'.tr(args: [current.companyName ?? '', '$others']),
              ),
              actions: [
                FilledButton(
                    onPressed: () => Navigator.pop(dlg),
                    child: Text('common_understood'.tr())),
              ],
            ),
          );
          return;
        }
        // CEO seul → confirmation FORTE : quitter + DISSOUDRE son équipe vide.
        final ok = await _confirmLeaveCurrent(
          current.companyName,
          isCeo: true,
        );
        if (ok != true) return;
        try {
          await TeamService().leaveCompany(current.companyId!, _user.uid);
          await TeamService().dissolveCompany(current.companyId!);
        } catch (_) {}
      } else {
        // Membre (tech) → simple confirmation de quitter.
        final ok = await _confirmLeaveCurrent(current.companyName, isCeo: false);
        if (ok != true) return;
        try {
          await TeamService().leaveCompany(current.companyId!, _user.uid);
        } catch (_) {}
      }
      await ref.read(teamStateProvider.notifier).clearTeam(removeLink: true);
    }

    setState(() { _loading = true; _error = null; });
    try {
      final company = await TeamService().joinCompany(
        inviteCode: _inviteCode.text.trim().toUpperCase(),
        uid: _user.uid,
        email: _user.email ?? '',
        displayName: _user.displayName ?? _user.email ?? '',
      );
      if (company == null) {
        setState(() { _error = 'ts_invalid_code'.tr(); });
        return;
      }
      await ref.read(teamStateProvider.notifier).saveTeam(company, 'tech');
      await ref
          .read(settingsProvider.notifier)
          .set('company_name', company.name);
      if (mounted) context.go('/home');
    } catch (e) {
      setState(() { _error = 'common_error'.tr(args: ['$e']); });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  // (#3) Confirmation avant de quitter l'équipe actuelle pour en rejoindre une
  // autre. CEO seul (équipe vide) → avertissement FORT (dissolution).
  Future<bool?> _confirmLeaveCurrent(String? currentName, {required bool isCeo}) {
    final name = (currentName ?? '').trim();
    return showDialog<bool>(
      context: context,
      builder: (dlg) => AlertDialog(
        icon: Icon(isCeo ? Icons.warning_amber_rounded : Icons.swap_horiz,
            color: isCeo ? Colors.red : Colors.orange),
        title: Text(isCeo ? 'ts_dissolve_q'.tr() : 'ts_leave_q'.tr()),
        content: Text(
          isCeo
              ? 'ts_dissolve_desc'.tr(args: [name, name])
              : 'ts_leave_desc'.tr(args: [name]),
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dlg, false),
              child: Text('common_cancel'.tr())),
          FilledButton(
            style: isCeo
                ? FilledButton.styleFrom(backgroundColor: Colors.red)
                : null,
            onPressed: () => Navigator.pop(dlg, true),
            child: Text(isCeo ? 'ts_dissolve_join'.tr() : 'ts_leave_join'.tr()),
          ),
        ],
      ),
    );
  }

  void _showInviteCodeDialog(String code, String name, VoidCallback onDone) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.group_add, color: AppColors.primary),
            const SizedBox(width: 8),
            Text('ts_team_created'.tr()),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ts_team_ready'.tr(args: [name])),
            const SizedBox(height: 16),
            Text('ts_invite_code_for_techs'.tr(),
                style: const TextStyle(color: Colors.black54, fontSize: 13)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    code,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 6,
                      color: AppColors.primary,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    icon: const Icon(Icons.copy_outlined, size: 20, color: AppColors.primary),
                    tooltip: 'ts_copy_code'.tr(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('ts_code_copied'.tr())),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'ts_code_available'.tr(),
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () { Navigator.pop(dialogCtx); onDone(); },
            child: Text('onboarding_start'.tr()),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Guard: redirect unauthenticated users to auth screen
    if (FirebaseAuth.instance.currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: Text('ts_team_config'.tr())),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('ts_login_to_config'.tr()),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go('/auth'),
                child: Text('auth_sign_in'.tr()),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.primary,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('ts_configure_team'.tr()),
        actions: [
          // (#1) Échappatoire : abandonner la configuration et entrer dans l'app
          // (utile si on arrive ici depuis la page de garde et qu'on veut juste
          // voir l'app d'abord).
          TextButton(
            onPressed: () => context.go('/home'),
            child: Text('common_later'.tr(),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          indicatorColor: Colors.white,
          tabs: [
            Tab(text: 'ts_create_team'.tr()),
            Tab(text: 'welcome_join_title'.tr()),
          ],
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabs,
          children: [
            _buildCreate(),
            _buildJoin(),
          ],
        ),
      ),
    );
  }

  Widget _buildCreate() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _createFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            _header(
              Icons.business,
              'ts_create_company'.tr(),
              'ts_create_company_sub'.tr(),
            ),
            const SizedBox(height: 16),
            // (3.3) Clarifier : pas besoin d'une équipe pour un pro solo.
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.info_outline,
                        size: 16, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text('ts_work_alone_q'.tr(),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                  ]),
                  const SizedBox(height: 4),
                  Text(
                    'ts_work_alone_desc'.tr(),
                    style: TextStyle(
                        fontSize: 11.5, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 4),
                  TextButton.icon(
                    onPressed: () => context.go('/settings'),
                    icon: const Icon(Icons.settings_outlined, size: 16),
                    label: Text('ts_fill_company_settings'.tr()),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _whiteField(
              controller: _companyNameCreate,
              label: 'settings_company_name'.tr(),
              icon: Icons.business_outlined,
              validator: (v) => (v == null || v.trim().length < 2)
                  ? 'ts_name_too_short'.tr()
                  : null,
            ),
            if (_error != null && _tabs.index == 0) ...[
              const SizedBox(height: 12),
              _errorBox(_error!),
            ],
            const SizedBox(height: 24),
            _submitBtn('ts_create_team_btn'.tr(), _loading ? null : _createCompany),
          ],
        ),
      ),
    );
  }

  Widget _buildJoin() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _joinFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            _header(
              Icons.group_add,
              'welcome_join_title'.tr(),
              'ts_join_sub'.tr(),
            ),
            const SizedBox(height: 28),
            // (#3) Rejoindre par CODE SEUL (le code est unique). Plus de champ
            // « nom de l'entreprise » : renommer l'équipe ne casse plus rien.
            _whiteField(
              controller: _inviteCode,
              label: 'ts_invite_code_label'.tr(),
              icon: Icons.key_outlined,
              textCapitalization: TextCapitalization.characters,
              maxLength: 8,
              validator: (v) => (v == null || v.trim().length < 6)
                  ? 'ts_invite_code_required'.tr()
                  : null,
            ),
            if (_error != null && _tabs.index == 1) ...[
              const SizedBox(height: 12),
              _errorBox(_error!),
            ],
            const SizedBox(height: 24),
            _submitBtn('ts_join_btn'.tr(), _loading ? null : _joinCompany),
          ],
        ),
      ),
    );
  }

  Widget _header(IconData icon, String title, String subtitle) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 36),
        ),
        const SizedBox(height: 16),
        Text(title,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(subtitle,
            textAlign: TextAlign.center,
            style:
                const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
      ],
    );
  }

  Widget _whiteField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
    TextCapitalization textCapitalization = TextCapitalization.none,
    int? maxLength,
  }) {
    return TextFormField(
      controller: controller,
      textCapitalization: textCapitalization,
      maxLength: maxLength,
      style: const TextStyle(color: Colors.white),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        labelStyle: const TextStyle(color: Colors.white70),
        prefixIcon: Icon(icon, color: Colors.white70),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        errorStyle: const TextStyle(color: Colors.orangeAccent),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.08),
      ),
    );
  }

  Widget _errorBox(String msg) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.shade700.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(msg, style: const TextStyle(color: Colors.white, fontSize: 13)),
      );

  Widget _submitBtn(String label, VoidCallback? onPressed) => FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.primary,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: onPressed,
        child: _loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Text(label,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      );
}
