import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class DropboxService {
  static const _appKey = '6je4pzzft5wimfo';
  static const _redirectScheme = 'com.tec.reportnew1cld';
  static const _redirectUri = '$_redirectScheme://oauth/dropbox';

  static const _tokenKey = 'dropbox_access_token';
  static const _refreshKey = 'dropbox_refresh_token';
  static const _displayNameKey = 'dropbox_display_name';

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

    final folder = '/${_resolveFolder(folderPattern, companyName, technicianName)}';

    final uploadResp = await http.post(
      Uri.parse('https://content.dropboxapi.com/2/files/upload'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/octet-stream',
        'Dropbox-API-Arg': jsonEncode({
          'path': '$folder/$filename',
          'mode': 'overwrite',
          'autorename': true,
        }),
      },
      body: bytes,
    );

    if (uploadResp.statusCode == 401) {
      final refreshed = await _refresh();
      if (!refreshed) return null;
      final prefs = await SharedPreferences.getInstance();
      token = prefs.getString(_tokenKey);
      if (token == null) return null;
      final retry = await http.post(
        Uri.parse('https://content.dropboxapi.com/2/files/upload'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/octet-stream',
          'Dropbox-API-Arg': jsonEncode({
            'path': '$folder/$filename',
            'mode': 'overwrite',
            'autorename': true,
          }),
        },
        body: bytes,
      );
      if (retry.statusCode != 200) {
        throw Exception('Échec upload Dropbox (${retry.statusCode})');
      }
    } else if (uploadResp.statusCode != 200) {
      throw Exception('Échec upload Dropbox (${uploadResp.statusCode})');
    }

    // Create shared link
    final shareResp = await http.post(
      Uri.parse(
          'https://api.dropboxapi.com/2/sharing/create_shared_link_with_settings'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'path': '$folder/$filename'}),
    );

    if (shareResp.statusCode == 200) {
      final shareData = jsonDecode(shareResp.body) as Map<String, dynamic>;
      return (shareData['url'] as String?)?.replaceAll('dl=0', 'dl=0');
    }
    // Link may already exist (409) — try get_shared_links
    if (shareResp.statusCode == 409) {
      final getResp = await http.post(
        Uri.parse('https://api.dropboxapi.com/2/sharing/list_shared_links'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'path': '$folder/$filename', 'direct_only': true}),
      );
      if (getResp.statusCode == 200) {
        final links = (jsonDecode(getResp.body)['links'] as List);
        if (links.isNotEmpty) return links.first['url'] as String?;
      }
    }
    return null;
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
      'www.dropbox.com',
      '/oauth2/authorize',
      {
        'client_id': _appKey,
        'response_type': 'code',
        'redirect_uri': _redirectUri,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'token_access_type': 'offline',
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
        Uri.parse('https://api.dropboxapi.com/oauth2/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': _appKey,
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
      Uri.parse('https://api.dropboxapi.com/oauth2/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': _appKey,
        'refresh_token': refreshToken,
        'grant_type': 'refresh_token',
      },
    );
    if (resp.statusCode != 200) return false;
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    await prefs.setString(_tokenKey, data['access_token'] as String);
    return true;
  }

  static Future<void> _fetchDisplayName(String token) async {
    try {
      final resp = await http.post(
        Uri.parse(
            'https://api.dropboxapi.com/2/users/get_current_account'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) {
        final d = jsonDecode(resp.body) as Map<String, dynamic>;
        final name =
            (d['name'] as Map<String, dynamic>?)?['display_name'] ?? d['email'];
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
