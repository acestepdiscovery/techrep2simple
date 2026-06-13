import 'dart:convert';
import 'package:http/http.dart' as http;

/// Remote kill switch + version gating via Firestore REST API (no Firebase SDK needed).
///
/// Firestore setup — document  config/app_control  fields:
///   status              (string)  = "ACTIVE"  — anything else blocks the app
///   message             (string)  = shown when blocked
///   min_build           (integer) = build number below this → force update (can't proceed)
///   latest_build        (integer) = build number below this → soft nudge (dismissable)
///   update_message      (string)  = shown in update dialogs
///   update_url_android  (string)  = Play Store URL
///   update_url_ios      (string)  = App Store URL
///   broadcast_id        (string)  = unique ID per broadcast message (changes to re-show)
///   broadcast_message   (string)  = one-time message shown to all users
///   broadcast_max_build (integer) = optional: only show to builds <= this number
///   banner_id           (string)  = unique ID for persistent top banner (change to refresh)
///   banner_message      (string)  = text shown in banner on reports home page
///
/// Behaviour:
///   • status != "ACTIVE"         → app blocked, shows message
///   • current build < min_build  → force update screen (non-dismissable)
///   • current build < latest     → soft update dialog (dismissable)
///   • broadcast_id present       → dismissable dialog, dismissed state per-user
///   • banner_id present          → dismissable top banner on reports list, per-user dismiss
///   • Network error / timeout    → fail-open (app runs normally)

class KillSwitchResult {
  final bool allowed;
  final String message;
  final bool forceUpdate;
  final bool softUpdate;
  final String updateMessage;
  final String? updateUrlAndroid;
  final String? updateUrlIos;
  final String? broadcastId;
  final String? broadcastMessage;
  final String? bannerId;
  final String? bannerMessage;

  const KillSwitchResult._({
    required this.allowed,
    this.message = '',
    this.forceUpdate = false,
    this.softUpdate = false,
    this.updateMessage = 'Une nouvelle version est disponible.',
    this.updateUrlAndroid,
    this.updateUrlIos,
    this.broadcastId,
    this.broadcastMessage,
    this.bannerId,
    this.bannerMessage,
  });

  factory KillSwitchResult.allowed({
    bool softUpdate = false,
    bool forceUpdate = false,
    String updateMessage = 'Une nouvelle version est disponible.',
    String? updateUrlAndroid,
    String? updateUrlIos,
    String? broadcastId,
    String? broadcastMessage,
    String? bannerId,
    String? bannerMessage,
  }) =>
      KillSwitchResult._(
        allowed: true,
        forceUpdate: forceUpdate,
        softUpdate: softUpdate,
        updateMessage: updateMessage,
        updateUrlAndroid: updateUrlAndroid,
        updateUrlIos: updateUrlIos,
        broadcastId: broadcastId,
        broadcastMessage: broadcastMessage,
        bannerId: bannerId,
        bannerMessage: bannerMessage,
      );

  factory KillSwitchResult.blocked(String msg) =>
      KillSwitchResult._(allowed: false, message: msg);
}

class KillSwitchService {
  static const _projectId = 'smallfun';
  static const _collection = 'config';
  static const _document = 'app_control';
  static const _activeValue = 'ACTIVE';
  static const _cacheDuration = Duration(minutes: 2);
  static const _defaultBlockedMessage =
      'Application temporairement indisponible.\nVeuillez contacter votre administrateur.';

  static KillSwitchResult? _cache;
  static DateTime? _cacheTime;

  static void clearCache() {
    _cache = null;
    _cacheTime = null;
  }

  static Future<KillSwitchResult> check({int currentBuild = 0}) async {
    if (_cache != null && _cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < _cacheDuration) {
      return _cache!;
    }

    try {
      final url = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$_projectId'
        '/databases/(default)/documents/$_collection/$_document',
      );

      final response = await http
          .get(url, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 404) {
        return _cacheAndReturn(KillSwitchResult.allowed());
      }
      if (response.statusCode != 200) {
        return KillSwitchResult.allowed();
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final fields = body['fields'] as Map<String, dynamic>?;

      String? _str(String key) =>
          (fields?[key] as Map<String, dynamic>?)?['stringValue'] as String?;
      int? _int(String key) {
        final raw = (fields?[key] as Map<String, dynamic>?)?['integerValue'];
        if (raw is int) return raw;
        if (raw is String) return int.tryParse(raw);
        return null;
      }

      final status = _str('status');

      // Kill switch: app blocked entirely
      if (status != _activeValue) {
        return _cacheAndReturn(KillSwitchResult.blocked(
          _str('message') ?? _defaultBlockedMessage,
        ));
      }

      // Version gating
      final minBuild = _int('min_build');
      final latestBuild = _int('latest_build');
      final updateMsg = _str('update_message') ?? 'Une nouvelle version est disponible.';
      final urlAndroid = _str('update_url_android');
      final urlIos = _str('update_url_ios');

      final forceUpdate = minBuild != null && currentBuild > 0 && currentBuild < minBuild;
      final softUpdate = !forceUpdate &&
          latestBuild != null && currentBuild > 0 && currentBuild < latestBuild;

      // Broadcast message
      final broadcastId = _str('broadcast_id');
      final broadcastMsg = _str('broadcast_message');
      final broadcastMaxBuild = _int('broadcast_max_build');
      final broadcastActive = broadcastId != null && broadcastMsg != null &&
          (broadcastMaxBuild == null || currentBuild <= broadcastMaxBuild);

      // Banner (persistent top message on reports list)
      final bannerId = _str('banner_id');
      final bannerMsg = _str('banner_message');
      final bannerActive = bannerId != null && bannerId.isNotEmpty &&
          bannerMsg != null && bannerMsg.isNotEmpty;

      return _cacheAndReturn(KillSwitchResult.allowed(
        forceUpdate: forceUpdate,
        softUpdate: softUpdate,
        updateMessage: updateMsg,
        updateUrlAndroid: urlAndroid,
        updateUrlIos: urlIos,
        broadcastId: broadcastActive ? broadcastId : null,
        broadcastMessage: broadcastActive ? broadcastMsg : null,
        bannerId: bannerActive ? bannerId : null,
        bannerMessage: bannerActive ? bannerMsg : null,
      ));
    } catch (_) {
      return KillSwitchResult.allowed();
    }
  }

  static KillSwitchResult _cacheAndReturn(KillSwitchResult result) {
    _cache = result;
    _cacheTime = DateTime.now();
    return result;
  }
}
