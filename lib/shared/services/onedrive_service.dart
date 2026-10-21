import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart' show StringTranslateExtension;

class OneDriveService {
  static const _clientId = '7fb64aa4-70d7-4f1f-9d9c-c77100e537a2';
  static const _redirectScheme = 'com.tec.reportnew1cld';
  static const _redirectUri = '$_redirectScheme://oauth/onedrive';
  static const _scope = 'Files.ReadWrite.AppFolder offline_access User.Read';

  static const _tokenKey = 'onedrive_access_token';
  static const _refreshKey = 'onedrive_refresh_token';
  static const _displayNameKey = 'onedrive_display_name';

  static Future<String?> get displayName async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_displayNameKey);
  }

  static Future<bool> get isConnected async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_tokenKey);
  }

  static Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshKey);
    await prefs.remove(_displayNameKey);
  }

  /// Returns shareable link, null if user cancelled, throws on error.
  static const _defaultFolder = 'Rapport Technique';

  static String _resolveFolder(String? pattern, String? company, String? tech) {
    var p = (pattern ?? '').trim();
    if (p.isEmpty) {
      p = (company?.trim().isNotEmpty == true)
          ? '$_defaultFolder - {société}'
          : _defaultFolder;
    }
    final now = DateTime.now();
    var r = p
        .replaceAll('{société}', company?.trim() ?? '')
        .replaceAll('{technicien}', tech?.trim() ?? '')
        .replaceAll('{année}', now.year.toString())
        .replaceAll('{mois}', now.month.toString().padLeft(2, '0'));
    final segments = r.split('/').map((s) {
      s = s.replaceAll(RegExp(r'\s*-\s*$'), '').trim();
      s = s.replaceAll(RegExp(r'^\s*-\s*'), '').trim();
      return s;
    }).where((s) => s.isNotEmpty).toList();
    return segments.isEmpty ? _defaultFolder : segments.join('/');
  }

  static Future<String?> uploadPdf(
    Uint8List bytes,
    String filename, {
    String? companyName,
    String? technicianName,
    String? folderPattern,
  }) async {
    var token = await _getValidToken();
    if (token == null) return null; // user cancelled

    // (2026-10-21) Crée d'abord le dossier de l'app (« Applications/<nom de l'app> ») :
    // sur un compte où l'app n'avait encore rien envoyé, l'envoi direct dans
    // approot:/… répondait 404 (vu au test sur émulateur).
    if (await _ensureAppFolder(token) == 401) {
      if (!await _refresh()) return null;
      token = (await SharedPreferences.getInstance()).getString(_tokenKey);
      if (token == null) return null;
      await _ensureAppFolder(token);
    }

    final folder = _resolveFolder(folderPattern, companyName, technicianName);
    // (2026-10-21) L'envoi par chemin ne crée PAS les sous-dossiers du dossier de l'app
    // (404 itemNotFound vu au test) → on les crée d'abord, un par un.
    await _ensureFolders(token, folder);

    final uploadUrl = Uri.parse(
      'https://graph.microsoft.com/v1.0/me/drive/special/approot:/'
      '${graphPath([...folder.split('/'), filename])}:/content',
    );

    var resp = await http.put(
      uploadUrl,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/pdf',
      },
      body: bytes,
    ).timeout(const Duration(seconds: 120));

    if (resp.statusCode == 401) {
      final refreshed = await _refresh();
      if (!refreshed) return null;
      final prefs = await SharedPreferences.getInstance();
      token = prefs.getString(_tokenKey);
      if (token == null) return null;
      resp = await http.put(
        uploadUrl,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/pdf',
        },
        body: bytes,
      ).timeout(const Duration(seconds: 120));
    }

    if (resp.statusCode != 200 && resp.statusCode != 201) {
      // (2026-10-21) + code d'erreur Microsoft (ex. « itemNotFound ») : diagnostic possible.
      final body = resp.body.length > 300 ? resp.body.substring(0, 300) : resp.body;
      debugPrint('[onedrive] envoi ${resp.statusCode} $body');
      throw Exception('cloud_err_upload'.tr(
          args: ['OneDrive', '${resp.statusCode}${graphErrorCode(resp.body)}']));
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;

    // Make shareable link
    final shareResp = await http.post(
      Uri.parse(
          'https://graph.microsoft.com/v1.0/me/drive/items/${data['id']}/createLink'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'type': 'view', 'scope': 'anonymous'}),
    ).timeout(const Duration(seconds: 30));
    if (shareResp.statusCode == 200 || shareResp.statusCode == 201) {
      final shareData = jsonDecode(shareResp.body) as Map<String, dynamic>;
      return (shareData['link'] as Map<String, dynamic>)['webUrl'] as String?;
    }

    return data['webUrl'] as String?;
  }

  /// (2026-10-21) GET approot = crée le dossier de l'app s'il n'existe pas encore.
  static Future<int> _ensureAppFolder(String token) async {
    try {
      final r = await http.get(
        Uri.parse('https://graph.microsoft.com/v1.0/me/drive/special/approot'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 30));
      if (r.statusCode != 200) {
        debugPrint('[onedrive] approot ${r.statusCode} ${r.body.length > 300 ? r.body.substring(0, 300) : r.body}');
      }
      // (2026-10-21) Compte Microsoft dont le OneDrive n'a jamais été ouvert : Microsoft
      // répond 503 « User is pending provisioning » → message clair (vu au test).
      if (isPendingProvisioning(r.body)) {
        throw Exception('cloud_err_onedrive_not_ready'.tr());
      }
      return r.statusCode;
    } on TimeoutException {
      return 0; // réseau : l'envoi qui suit donnera le vrai message
    } on http.ClientException {
      return 0;
    }
  }

  /// OneDrive pas encore activé pour ce compte (« itemDisabledDueToPendingProvisioning »).
  static bool isPendingProvisioning(String body) =>
      body.contains('itemDisabledDueToPendingProvisioning') ||
      body.contains('User is pending provisioning');

  /// Chemin Graph : segments vides retirés, chacun encodé (espaces, accents, « & »…).
  static String graphPath(List<String> segments) => segments
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .map(Uri.encodeComponent)
      .join('/');

  /// (2026-10-21) Crée chaque dossier du chemin dans le dossier de l'app ; « existe
  /// déjà » (409) n'est pas une erreur. Les autres erreurs sont laissées à l'envoi.
  static Future<void> _ensureFolders(String token, String folder) async {
    final segs = folder.split('/').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    for (var i = 0; i < segs.length; i++) {
      final parent = graphPath(segs.sublist(0, i));
      final url = parent.isEmpty
          ? 'https://graph.microsoft.com/v1.0/me/drive/special/approot/children'
          : 'https://graph.microsoft.com/v1.0/me/drive/special/approot:/$parent:/children';
      try {
        final r = await http.post(
          Uri.parse(url),
          headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
          body: jsonEncode({
            'name': segs[i],
            'folder': <String, dynamic>{},
            '@microsoft.graph.conflictBehavior': 'fail',
          }),
        ).timeout(const Duration(seconds: 30));
        if (r.statusCode != 201 && r.statusCode != 409) {
          debugPrint('[onedrive] dossier « ${segs[i]} » ${r.statusCode} '
              '${r.body.length > 200 ? r.body.substring(0, 200) : r.body}');
        }
      } catch (_) {}
    }
  }

  /// Code d'erreur Microsoft Graph lisible (« {"error":{"code":"itemNotFound"…}} » →
  /// « itemNotFound »), préfixé d'un espace ; '' si absent.
  static String graphErrorCode(String body) {
    try {
      final err = (jsonDecode(body) as Map<String, dynamic>)['error'];
      final code = err is Map ? err['code'] : null;
      return code is String && code.isNotEmpty ? ' $code' : '';
    } catch (_) {
      return '';
    }
  }

  static Future<String?> _getValidToken() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_tokenKey);
    if (stored != null) return stored;
    final ok = await _signIn();
    if (!ok) return null;
    return prefs.getString(_tokenKey);
  }

  static Future<bool> _signIn() async {
    final verifier = _codeVerifier();
    final challenge = _codeChallenge(verifier);

    final authUrl = Uri.https(
      'login.microsoftonline.com',
      '/common/oauth2/v2.0/authorize',
      {
        'client_id': _clientId,
        'response_type': 'code',
        'redirect_uri': _redirectUri,
        'scope': _scope,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
      },
    );

    try {
      final result = await FlutterWebAuth2.authenticate(
        url: authUrl.toString(),
        callbackUrlScheme: _redirectScheme,
      );
      final code = Uri.parse(result).queryParameters['code'];
      if (code == null) return false;

      final tokenResp = await http.post(
        Uri.https('login.microsoftonline.com', '/common/oauth2/v2.0/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': _clientId,
          'code': code,
          'redirect_uri': _redirectUri,
          'grant_type': 'authorization_code',
          'code_verifier': verifier,
        },
      ).timeout(const Duration(seconds: 30));
      if (tokenResp.statusCode != 200) return false;

      final data = jsonDecode(tokenResp.body) as Map<String, dynamic>;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, data['access_token'] as String);
      if (data['refresh_token'] != null) {
        await prefs.setString(_refreshKey, data['refresh_token'] as String);
      }
      await _fetchDisplayName(data['access_token'] as String);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _refresh() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString(_refreshKey);
    if (refreshToken == null) return false;

    final resp = await http.post(
      Uri.https('login.microsoftonline.com', '/common/oauth2/v2.0/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': _clientId,
        'refresh_token': refreshToken,
        'grant_type': 'refresh_token',
      },
    ).timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) return false;
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    await prefs.setString(_tokenKey, data['access_token'] as String);
    if (data['refresh_token'] != null) {
      await prefs.setString(_refreshKey, data['refresh_token'] as String);
    }
    return true;
  }

  static Future<void> _fetchDisplayName(String token) async {
    try {
      final resp = await http.get(
        Uri.parse('https://graph.microsoft.com/v1.0/me'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 30));
      if (resp.statusCode == 200) {
        final d = jsonDecode(resp.body) as Map<String, dynamic>;
        final name = d['displayName'] ?? d['mail'] ?? d['userPrincipalName'];
        if (name != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_displayNameKey, name as String);
        }
      }
    } catch (_) {}
  }

  static String _codeVerifier() {
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String _codeChallenge(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }
}
