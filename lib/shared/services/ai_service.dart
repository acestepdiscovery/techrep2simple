import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../../core/config/cf_config.dart';

class AiActionResult {
  final Map<String, String> fields;
  final int used;
  final int quota;
  final String? error;

  const AiActionResult({
    this.fields = const {},
    this.used = 0,
    this.quota = 10,
    this.error,
  });

  bool get isSuccess => error == null;
  bool get isQuotaExceeded => error == 'quota_exceeded';
  bool get needsSubscription => error == 'subscription_required';
  bool get isNetworkError => error != null && error!.startsWith('network_error');

  String get errorMessage {
    if (isQuotaExceeded) return 'Quota mensuel atteint ($used/$quota utilisations).';
    if (needsSubscription) return 'Cette fonctionnalité est réservée aux abonnés.';
    if (isNetworkError) return 'Impossible de joindre le serveur. Vérifiez votre connexion.';
    return 'Erreur inattendue. Réessayez dans quelques instants.';
  }
}

class AiService {
  static const _cfBaseUrl = kCfBaseUrl;

  Future<AiActionResult> _callCf(Map<String, dynamic> body) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return const AiActionResult(error: 'not_authenticated');
      final token = await user.getIdToken();

      final resp = await http
          .post(
            Uri.parse('$_cfBaseUrl/ai-action'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 90));

      final data = jsonDecode(resp.body) as Map<String, dynamic>;

      if (resp.statusCode == 200) {
        final rawFields = data['fields'] as Map<String, dynamic>? ?? {};
        final fields =
            rawFields.map((k, v) => MapEntry(k, (v ?? '').toString()));
        final usage = data['usage'] as Map<String, dynamic>? ?? {};
        return AiActionResult(
          fields: fields,
          used: (usage['used'] as int?) ?? 0,
          quota: (usage['quota'] as int?) ?? 10,
        );
      }

      final error = (data['error'] as String?) ?? 'unknown_error';
      final used = (data['used'] as int?) ?? 0;
      final quota = (data['quota'] as int?) ?? 10;
      return AiActionResult(error: error, used: used, quota: quota);
    } catch (e) {
      return AiActionResult(error: 'network_error: $e');
    }
  }

  Future<AiActionResult> audioToReport({
    required String audioB64,
    required String audioMime,
    String? companyId,
    String? note,
  }) =>
      _callCf({
        'action': 'audio_to_report',
        'audio_b64': audioB64,
        'audio_mime': audioMime,
        if (companyId != null) 'company_id': companyId,
        if (note != null && note.isNotEmpty) 'note': note,
      });

  Future<AiActionResult> imageToReport({
    required String imageB64,
    String imageMime = 'image/jpeg',
    String? companyId,
    String? note,
  }) =>
      _callCf({
        'action': 'image_to_report',
        'image_b64': imageB64,
        'image_mime': imageMime,
        if (companyId != null) 'company_id': companyId,
        if (note != null && note.isNotEmpty) 'note': note,
      });

  Future<AiActionResult> documentToReport({
    required String content,       // plain text for TXT, base64 for PDF/DOCX
    required String contentType,   // 'text', 'pdf_b64', 'docx_b64'
    String? companyId,
    String? note,
  }) =>
      _callCf({
        'action': 'document_to_report',
        'content': content,
        'content_type': contentType,
        if (companyId != null) 'company_id': companyId,
        if (note != null && note.isNotEmpty) 'note': note,
      });

  Future<AiActionResult> improveReport({
    required Map<String, String> fields,
    String? companyId,
    String? note,
    String? noteAudioB64,
    String? noteAudioMime,
  }) =>
      _callCf({
        'action': 'improve_report',
        'fields': fields,
        if (companyId != null) 'company_id': companyId,
        if (note != null && note.isNotEmpty) 'note': note,
        if (noteAudioB64 != null && noteAudioB64.isNotEmpty)
          'note_audio_b64': noteAudioB64,
        if (noteAudioMime != null) 'note_audio_mime': noteAudioMime,
      });
}
