import 'dart:convert';
import 'dart:typed_data';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

class GoogleDriveService {
  static const _defaultFolderName = 'Rapport Technique';
  static const _scope = 'https://www.googleapis.com/auth/drive.file';

  static final _signIn = GoogleSignIn(scopes: [_scope]);

  static Future<String?> get currentEmail async {
    final current = _signIn.currentUser ?? await _signIn.signInSilently();
    return current?.email;
  }

  static Future<void> signOut() => _signIn.signOut();

  /// Resolves folder pattern with variables {société} and {technicien}.
  static String resolveFolderName(
    String? pattern, {
    String? companyName,
    String? technicianName,
  }) {
    var p = (pattern ?? '').trim();
    if (p.isEmpty) {
      p = (companyName?.trim().isNotEmpty == true)
          ? '$_defaultFolderName - {société}'
          : _defaultFolderName;
    }
    final now = DateTime.now();
    var result = p
        .replaceAll('{société}', companyName?.trim() ?? '')
        .replaceAll('{technicien}', technicianName?.trim() ?? '')
        .replaceAll('{année}', now.year.toString())
        .replaceAll('{mois}', now.month.toString().padLeft(2, '0'));
    final segments = result.split('/').map((s) {
      s = s.replaceAll(RegExp(r'\s*-\s*$'), '').trim();
      s = s.replaceAll(RegExp(r'^\s*-\s*'), '').trim();
      return s;
    }).where((s) => s.isNotEmpty).toList();
    return segments.isEmpty ? _defaultFolderName : segments.join('/');
  }

  static String folderNameFor(String? companyName) =>
      resolveFolderName(null, companyName: companyName);

  /// Returns the shareable web link, or null if user cancelled sign-in.
  /// Throws on upload error.
  static Future<String?> uploadPdf(
    Uint8List bytes,
    String filename, {
    String? companyName,
    String? technicianName,
    String? folderPattern,
  }) async {
    var account = _signIn.currentUser ?? await _signIn.signInSilently();
    account ??= await _signIn.signIn();
    if (account == null) return null; // user cancelled

    final auth = await account.authentication;
    final token = auth.accessToken;
    if (token == null) throw Exception('Impossible d\'obtenir le token Google');

    final headers = {'Authorization': 'Bearer $token'};
    final folderId = await _getOrCreateFolder(
        headers,
        resolveFolderName(folderPattern,
            companyName: companyName, technicianName: technicianName));

    // Multipart upload: metadata + PDF bytes in one request
    final boundary = 'tr_boundary_${DateTime.now().millisecondsSinceEpoch}';
    final metadata = jsonEncode({'name': filename, 'parents': [folderId]});
    final bodyStart = '--$boundary\r\n'
        'Content-Type: application/json; charset=UTF-8\r\n\r\n'
        '$metadata\r\n'
        '--$boundary\r\n'
        'Content-Type: application/pdf\r\n\r\n';

    final fullBody = Uint8List.fromList([
      ...utf8.encode(bodyStart),
      ...bytes,
      ...utf8.encode('\r\n--$boundary--'),
    ]);

    final uploadResp = await http.post(
      Uri.parse(
        'https://www.googleapis.com/upload/drive/v3/files'
        '?uploadType=multipart&fields=id,webViewLink',
      ),
      headers: {
        ...headers,
        'Content-Type': 'multipart/related; boundary=$boundary',
      },
      body: fullBody,
    );

    if (uploadResp.statusCode != 200) {
      throw Exception('Échec upload Drive (${uploadResp.statusCode})');
    }

    final data = jsonDecode(uploadResp.body) as Map<String, dynamic>;
    final fileId = data['id'] as String;

    // Make readable by anyone with the link
    await http.post(
      Uri.parse(
          'https://www.googleapis.com/drive/v3/files/$fileId/permissions'),
      headers: {...headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'type': 'anyone', 'role': 'reader'}),
    );

    return data['webViewLink'] as String?;
  }

  static Future<String> _getOrCreateFolder(
      Map<String, String> headers, String folderPath) async {
    final segments = folderPath.split('/').where((s) => s.isNotEmpty).toList();
    String? parentId;
    for (final segment in segments) {
      parentId = await _getOrCreateSingleFolder(headers, segment, parentId: parentId);
    }
    return parentId!;
  }

  static Future<String> _getOrCreateSingleFolder(
      Map<String, String> headers, String name, {String? parentId}) async {
    final parentClause = parentId != null ? " and '$parentId' in parents" : '';
    final query = Uri.encodeQueryComponent(
      "name='$name' and "
      "mimeType='application/vnd.google-apps.folder' and trashed=false$parentClause",
    );
    final search = await http.get(
      Uri.parse(
          'https://www.googleapis.com/drive/v3/files?q=$query&fields=files(id)'),
      headers: headers,
    );
    final files = (jsonDecode(search.body)['files'] as List);
    if (files.isNotEmpty) return files.first['id'] as String;

    final body = <String, dynamic>{
      'name': name,
      'mimeType': 'application/vnd.google-apps.folder',
    };
    if (parentId != null) body['parents'] = [parentId];
    final create = await http.post(
      Uri.parse('https://www.googleapis.com/drive/v3/files?fields=id'),
      headers: {...headers, 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return (jsonDecode(create.body) as Map<String, dynamic>)['id'] as String;
  }
}
