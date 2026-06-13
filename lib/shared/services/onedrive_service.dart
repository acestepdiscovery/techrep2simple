import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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

    final folder = _resolveFolder(folderPattern, companyName, technicianName);

    final uploadUrl = Uri.parse(
      'https://graph.microsoft.com/v1.0/me/drive/special/approot:/$folder/$filename:/content',
    );

    var resp = await http.put(
      uploadUrl,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/pdf',
      },
      body: bytes,
    );

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
      );
    }

    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw Exception('Échec upload OneDrive (${resp.statusCode})');
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
    );
    if (shareResp.statusCode == 200 || shareResp.statusCode == 201) {
      final shareData = jsonDecode(shareResp.body) as Map<String, dynamic>;
      return (shareData['link'] as Map<String, dynamic>)['webUrl'] as String?;
    }

    return data['webUrl'] as String?;
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
      );
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
    );
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
      );
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
