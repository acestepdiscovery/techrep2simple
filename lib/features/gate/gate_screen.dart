import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config/app_build.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/services/account_switch_guard.dart';
import '../../shared/services/instance_token_guard.dart';
import '../../shared/services/kill_switch_service.dart';

// Feedback nudge thresholds (app open count)
const _nudgeThresholds = {10, 30, 100};

class GateScreen extends StatefulWidget {
  const GateScreen({super.key});

  @override
  State<GateScreen> createState() => _GateScreenState();
}

class _GateScreenState extends State<GateScreen> {
  bool _checked = false;
  KillSwitchResult? _result;
  String? _blockedReason;
  String? _tokenBlockedMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    KillSwitchService.clearCache();
    final result = await KillSwitchService.check(currentBuild: kAppBuildNumber);
    if (!mounted) return;

    // Kill switch — app blocked
    if (!result.allowed) {
      setState(() { _checked = true; _result = result; });
      return;
    }

    // Force update — must update before proceeding
    if (result.forceUpdate) {
      setState(() { _checked = true; _result = result; });
      return;
    }

    // (4a/4c) Purge l'identité entreprise locale si l'appareil change de compte.
    await AccountSwitchGuard.ensureCleanFor(
        FirebaseAuth.instance.currentUser?.uid);

    // Track usage and schedule feedback nudge if threshold hit
    await _trackUsage();

    // Relay broadcast message to main_shell via SharedPreferences
    await _saveBroadcast(result);

    // Persist store URLs so invite share text stays current without a code push
    await _saveStoreUrls(result);

    // Save banner data for reports list top banner
    await _saveBanner(result);

    // Check if the current user has been individually blocked (cheater/abuse)
    final blockedReason = await _checkIfUserBlocked();
    if (blockedReason != null) {
      if (mounted) setState(() { _checked = true; _blockedReason = blockedReason; });
      return;
    }

    // Instance token — block specific demo/beta builds via Firestore array
    final (tokenBlocked, tokenMsg) = await InstanceTokenGuard.check();
    if (tokenBlocked) {
      if (mounted) setState(() { _checked = true; _tokenBlockedMessage = tokenMsg; });
      return;
    }

    // Soft update — new version available, user can dismiss
    if (result.softUpdate && mounted) {
      _showSoftUpdateDialog(result);
    }

    if (!mounted) return;

    // Route based on persisted state (existing logic)
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('app_mode');
    final onboardingDone = prefs.getBool('onboarding_done') ?? false;

    if (mode == 'offline' || (mode == null && onboardingDone)) {
      if (mode == null) await prefs.setString('app_mode', 'offline');
      if (mounted) context.go('/home');
      return;
    }

    if (mode == 'team') {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          if (mounted) context.go('/home');
          return;
        }
      } catch (_) {}
    }

    if (mounted) context.go('/welcome');
  }

  Future<void> _trackUsage() async {
    final prefs = await SharedPreferences.getInstance();
    final opens = (prefs.getInt('app_opens') ?? 0) + 1;
    await prefs.setInt('app_opens', opens);
    if (_nudgeThresholds.contains(opens)) {
      await prefs.setBool('show_feedback_nudge', true);
    }
  }

  Future<String?> _checkIfUserBlocked() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      final doc = await FirebaseFirestore.instance
          .collection('blocked_users_raptech1')
          .doc(user.uid)
          .get()
          .timeout(const Duration(seconds: 5));
      if (!doc.exists) return null;
      final data = doc.data()!;
      if (data['blocked'] != true) return null;
      final reason = data['reason'] as String?;
      return (reason != null && reason.isNotEmpty)
          ? reason
          : 'Usage non conforme aux conditions d\'utilisation.';
    } catch (_) {
      return null; // fail open — never block the app on a network error
    }
  }

  Future<void> _saveStoreUrls(KillSwitchResult result) async {
    final prefs = await SharedPreferences.getInstance();
    if (result.updateUrlAndroid != null) {
      await prefs.setString('store_url_android', result.updateUrlAndroid!);
    }
    if (result.updateUrlIos != null) {
      await prefs.setString('store_url_ios', result.updateUrlIos!);
    }
  }

  Future<void> _saveBroadcast(KillSwitchResult result) async {
    if (result.broadcastId == null || result.broadcastMessage == null) return;
    final prefs = await SharedPreferences.getInstance();
    // Only relay if not already dismissed by the user
    final dismissedKey = 'dismissed_broadcast_${result.broadcastId}';
    if (prefs.getBool(dismissedKey) == true) return;
    await prefs.setString('pending_broadcast_id', result.broadcastId!);
    await prefs.setString('pending_broadcast_message', result.broadcastMessage!);
  }

  Future<void> _saveBanner(KillSwitchResult result) async {
    final prefs = await SharedPreferences.getInstance();
    if (result.bannerId == null) {
      // No active banner — clear so reports list hides it
      await prefs.remove('current_banner_id');
      await prefs.remove('current_banner_message');
      return;
    }
    await prefs.setString('current_banner_id', result.bannerId!);
    await prefs.setString('current_banner_message', result.bannerMessage!);
  }

  void _showSoftUpdateDialog(KillSwitchResult result) {
    final url = defaultTargetPlatform == TargetPlatform.iOS
        ? result.updateUrlIos
        : result.updateUrlAndroid;
    showDialog(
      context: context,
      builder: (dlg) => AlertDialog(
        title: const Text('Mise à jour disponible'),
        content: Text(result.updateMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlg),
            child: const Text('Plus tard'),
          ),
          if (url != null)
            FilledButton(
              onPressed: () {
                Navigator.pop(dlg);
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              },
              child: const Text('Mettre à jour'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Loading splash
    if (!_checked) {
      return const Scaffold(
        backgroundColor: AppColors.primary,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 24),
              Text(
                'Compte Rendu Technique IA',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Individual user blocked
    if (_blockedReason != null) {
      return _BlockedView(reason: _blockedReason!);
    }

    // Build/instance token blocked
    if (_tokenBlockedMessage != null) {
      return Scaffold(
        backgroundColor: AppColors.primary,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.phonelink_erase_outlined, color: Colors.white, size: 64),
                const SizedBox(height: 24),
                Text(
                  _tokenBlockedMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.6),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Force update screen
    if (_result?.forceUpdate ?? false) {
      final url = defaultTargetPlatform == TargetPlatform.iOS
          ? _result!.updateUrlIos
          : _result!.updateUrlAndroid;
      return Scaffold(
        backgroundColor: AppColors.primary,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.system_update_outlined,
                    color: Colors.white, size: 64),
                const SizedBox(height: 24),
                const Text(
                  'Mise à jour requise',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _result!.updateMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.5),
                ),
                const SizedBox(height: 32),
                if (url != null)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.white),
                    onPressed: () => launchUrl(
                      Uri.parse(url),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: Icon(Icons.download_outlined, color: AppColors.primary),
                    label: Text('Mettre à jour',
                        style: TextStyle(color: AppColors.primary,
                            fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    // Kill switch — app blocked
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, color: Colors.white, size: 64),
              const SizedBox(height: 24),
              Text(
                _result?.message ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                ),
                onPressed: _check,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Individual user blocked screen ──────────────────────────────────────────

class _BlockedView extends StatefulWidget {
  final String reason;
  const _BlockedView({required this.reason});

  @override
  State<_BlockedView> createState() => _BlockedViewState();
}

class _BlockedViewState extends State<_BlockedView> {
  final _msgCtrl = TextEditingController();
  bool _sending = false;
  bool _sent = false;

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendAppeal() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      await FirebaseFirestore.instance.collection('feedback_raptech1').add({
        'type': 'account_blocked_appeal',
        'uid': user?.uid ?? '',
        'email': user?.email ?? '',
        'message': text,
        'block_reason': widget.reason,
        'created_at': FieldValue.serverTimestamp(),
      });
      if (mounted) setState(() { _sent = true; _sending = false; });
    } catch (_) {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.red.shade50,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
          child: Column(
            children: [
              Icon(Icons.block_outlined, size: 64, color: Colors.red.shade400),
              const SizedBox(height: 16),
              const Text(
                'Compte suspendu',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  widget.reason,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 14, height: 1.5),
                ),
              ),
              const SizedBox(height: 32),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Vous pensez qu\'il s\'agit d\'une erreur ?',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
              ),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Envoyez-nous votre réclamation ci-dessous.',
                  style: TextStyle(color: Colors.black54, fontSize: 13),
                ),
              ),
              const SizedBox(height: 12),
              if (!_sent) ...[
                TextField(
                  controller: _msgCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Expliquez votre situation...',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _sending ? null : _sendAppeal,
                    icon: _sending
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send_outlined, size: 18),
                    label: const Text('Envoyer la réclamation'),
                    style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                  ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: const Row(children: [
                    Icon(Icons.check_circle_outline, color: Colors.green),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Réclamation envoyée. Nous l\'examinons et vous répondrons par email.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ]),
                ),
              ],
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                  if (context.mounted) context.go('/welcome');
                },
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Se déconnecter et utiliser un autre compte'),
                style: TextButton.styleFrom(foregroundColor: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
