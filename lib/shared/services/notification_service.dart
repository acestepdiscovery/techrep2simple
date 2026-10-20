import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' show Intl;
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/config/cf_config.dart';

// Background message handler — must be a top-level function.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase is already initialized when this runs.
  // We don't show a local notification here — the system tray handles it.
}

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  static const _tokenPrefsKey = 'fcm_current_token';
  static const _channelId = 'raptech_default';
  static const _channelName = 'Notifications';
  static const _cfUrl = kCfBaseUrl;

  GoRouter? _router;
  final _local = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  // (2026-10-19) UN seul écouteur de renouvellement du jeton : avant, chaque
  // connexion en ajoutait un (et celui de l'ancien compte restait actif).
  StreamSubscription<String>? _tokenRefreshSub;

  // ── Setup ────────────────────────────────────────────────────────────────

  // Call once after Firebase.initializeApp(), passing the app's GoRouter.
  Future<void> initialize(GoRouter router) async {
    if (_initialized) return;
    _initialized = true;
    _router = router;

    if (kIsWeb) return; // FCM web needs VAPID key — skip for now

    // Background handler must be registered at top level.
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Android: create high-importance notification channel.
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      importance: Importance.high,
    );
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Local notifications init.
    // NOTE: replace '@mipmap/ic_launcher' with a white-on-transparent drawable
    //       'ic_notification' once the asset is created.
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _local.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onLocalTap,
    );

    // iOS: show alerts even when app is in foreground.
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Foreground: show via flutter_local_notifications (FCM suppresses UI in fg).
    FirebaseMessaging.onMessage.listen(_onForeground);

    // Tap: app was in background, user tapped notification.
    FirebaseMessaging.onMessageOpenedApp.listen(_onTap);

    // Tap: app was terminated (cold launch from notification).
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _onTap(initial);
  }

  // Call after Firebase Auth login is confirmed.
  // Requests permission and registers/rotates the FCM token for this user.
  Future<void> initializeForUser(String uid) async {
    if (kIsWeb) return;
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await _saveToken(uid, token);

    // Re-register if token rotates (e.g. after app reinstall or token expiry).
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh
        .listen((newToken) => _saveToken(uid, newToken));
  }

  // ── Token management ─────────────────────────────────────────────────────

  Future<void> _saveToken(String uid, String newToken) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final oldToken = prefs.getString(_tokenPrefsKey);
      final db = FirebaseFirestore.instance;

      await db.runTransaction((tx) async {
        final ref = db.collection('users_raptech1').doc(uid);
        final snap = await tx.get(ref);
        final tokens = List<String>.from(
            snap.data()?['fcmTokens'] as List<dynamic>? ?? []);

        // Remove old token (rotation) and avoid duplicates.
        if (oldToken != null) tokens.remove(oldToken);
        if (!tokens.contains(newToken)) tokens.add(newToken);

        // Keep at most 5 tokens (most recent = last in list).
        final capped =
            tokens.length > 5 ? tokens.sublist(tokens.length - 5) : tokens;

        tx.set(ref, {'fcmTokens': capped}, SetOptions(merge: true));
      });

      await prefs.setString(_tokenPrefsKey, newToken);

      // Anti-contamination : demande au serveur de retirer ce token de tout
      // AUTRE compte (cas changement de compte sans logout propre). Best-effort.
      await _claimTokenOnServer(newToken);
    } catch (e) {
      debugPrint('[NotificationService] token save error: $e');
    }
  }

  // Rattache le token au compte courant côté serveur (admin SDK), en le retirant
  // de tout autre compte qui le porterait encore. Best-effort, non bloquant.
  Future<void> _claimTokenOnServer(String token, {String? lang}) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final idToken = await user.getIdToken();
      await http.post(
        Uri.parse('$_cfUrl/claim-push-token'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        // (2026-10-20) + langue de l'app → notifications d'équipe dans cette
        // langue (avant : toujours en français).
        body: jsonEncode({'token': token, 'lang': lang ?? notifLang()}),
      ).timeout(const Duration(seconds: 15));
    } catch (_) {
      // non bloquant
    }
  }

  /// Langue de l'app transmise au serveur pour les notifications (« fr », « de »…).
  @visibleForTesting
  static String notifLang() => (Intl.defaultLocale ?? 'fr').split(RegExp('[_-]')).first;

  /// (2026-10-20) Après un changement de langue dans l'app : prévient le serveur
  /// pour que les prochaines notifications arrivent dans la nouvelle langue.
  Future<void> syncLanguage(String lang) async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenPrefsKey);
    if (token != null) await _claimTokenOnServer(token, lang: lang);
  }

  // Removes the current token from Firestore on sign-out so this device
  // stops receiving notifications after logout.
  Future<void> clearTokenForUser(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_tokenPrefsKey);
      if (token == null) return;
      // (2026-10-19) Délai : hors ligne, la DÉCONNEXION (qui attend ceci)
      // restait bloquée. L'écriture partira d'elle-même au retour du réseau.
      await FirebaseFirestore.instance
          .collection('users_raptech1')
          .doc(uid)
          .update({'fcmTokens': FieldValue.arrayRemove([token])})
          .timeout(const Duration(seconds: 5), onTimeout: () {});
      await prefs.remove(_tokenPrefsKey);
      await _tokenRefreshSub?.cancel();
      _tokenRefreshSub = null;
    } catch (_) {}
  }

  // ── Message handling ─────────────────────────────────────────────────────

  void _onForeground(RemoteMessage msg) {
    final notif = msg.notification;
    if (notif == null) return;
    _local.show(
      msg.hashCode,
      notif.title,
      notif.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: jsonEncode(msg.data),
    );
  }

  // Tapped from system tray while app was in foreground (local notification).
  void _onLocalTap(NotificationResponse response) {
    if (response.payload == null) return;
    try {
      final data = jsonDecode(response.payload!) as Map<String, dynamic>;
      _navigate(data);
    } catch (_) {}
  }

  // Tapped from system tray while app was in background/terminated.
  void _onTap(RemoteMessage msg) => _navigate(msg.data);

  void _navigate(Map<String, dynamic> data) {
    final router = _router;
    if (router == null) return;
    final type = data['type'] as String?;
    final reportId = data['reportId'] as String?;

    switch (type) {
      // (2026-10-19) « Rapport envoyé » (reçu par le responsable) : ce rapport
      // est celui d'un technicien, il n'est PAS sur ce téléphone → onglet Équipe
      // (avant : écran « rapport introuvable »).
      case 'report_submitted':
        router.go('/team-tab');
      case 'report_validated':
      case 'report_rejected':
        if (reportId != null) {
          router.push('/report/$reportId');
        } else {
          router.go('/team-tab');
        }
      case 'member_joined':
      case 'member_approved':
        router.go('/team-tab');
    }
  }
}
