import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/config/app_build.dart';

/// Per-build kill switch. Add the build's kAppInstanceToken to
/// config/app_control.blocked_tokens (array) in Firestore to block it.
/// Result is cached for 1 hour in SharedPreferences.
class InstanceTokenGuard {
  static const _blockedKey = 'instance_token_blocked';
  static const _msgKey = 'instance_token_msg';
  static const _lastCheckKey = 'instance_token_last_check_ms';
  static final _cacheMs = Duration(minutes: kInstanceTokenCacheMinutes).inMilliseconds;

  static const _defaultMessage =
      'Cette version de démonstration n\'est plus active.\n'
      'Merci de nous contacter pour accéder à l\'application.';

  /// Returns (isBlocked, message). Fails open on network error.
  static Future<(bool, String)> check() async {
    final prefs = await SharedPreferences.getInstance();
    final lastCheck = prefs.getInt(_lastCheckKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (now - lastCheck < _cacheMs) {
      return (
        prefs.getBool(_blockedKey) ?? false,
        prefs.getString(_msgKey) ?? _defaultMessage,
      );
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('config')
          .doc('app_control')
          .get()
          .timeout(const Duration(seconds: 5));
      final data = doc.data() ?? {};
      final tokens = List<String>.from(data['blocked_tokens'] as List? ?? []);
      final blocked = tokens.contains(kAppInstanceToken);
      final raw = (data['blocked_token_message'] as String?)?.trim() ?? '';
      final msg = raw.isNotEmpty ? raw : _defaultMessage;

      await prefs.setBool(_blockedKey, blocked);
      await prefs.setString(_msgKey, msg);
      await prefs.setInt(_lastCheckKey, now);
      return (blocked, msg);
    } catch (_) {
      return (
        prefs.getBool(_blockedKey) ?? false,
        prefs.getString(_msgKey) ?? _defaultMessage,
      );
    }
  }

  /// Force next check to hit Firestore instead of cache.
  static Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastCheckKey);
  }

  /// Show a modal dialog. Awaitable — resolves when user taps OK.
  static Future<void> showBlockedDialog(BuildContext context, String message) async {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dlg) => AlertDialog(
        title: const Text('Version non disponible'),
        content: Text(message, style: const TextStyle(height: 1.5)),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dlg),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
