import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Manages remote signature requests stored in Firestore.
///
/// Flow:
///   1. Tech calls [createRequest] → gets token + code + share URL.
///   2. Client opens share URL (Cloudflare Worker page), draws signature, enters code.
///   3. Cloudflare Worker calls Firebase CF /receive-signature.
///   4. Firebase CF verifies code, writes signature_b64 + status=signed.
///   5. Tech's app [streamRequest] fires, app applies signature to report.
///
/// Firestore collection: signature_requests_raptech1/{token}
class RemoteSignatureService {
  static final _db = FirebaseFirestore.instance;
  static const _collection = 'signature_requests_raptech1';

  static const String workerBaseUrl = 'https://sign-raptech.satimatyka-cbd.workers.dev';

  static String _randomCode(int length) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no confusable chars
    final rnd = Random.secure();
    return List.generate(length, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  /// Creates a signature request. Returns `(token, code, shareUrl)`.
  static Future<({String token, String code, String shareUrl})> createRequest({
    required String reportId,
    required String techUid,
    String? companyId,
    String? clientName,
  }) async {
    final token = _randomCode(32);
    final code = _randomCode(5);
    await _db.collection(_collection).doc(token).set({
      'code': code,
      'report_id': reportId,
      'tech_uid': techUid,
      'company_id': companyId,
      'client_name': clientName,
      'status': 'pending',
      'created_at': FieldValue.serverTimestamp(),
    });
    final shareUrl = '$workerBaseUrl/$token';
    return (token: token, code: code, shareUrl: shareUrl);
  }

  /// Streams the status doc. Emits the full doc map on every change.
  static Stream<Map<String, dynamic>?> streamRequest(String token) =>
      _db.collection(_collection).doc(token).snapshots().map((s) => s.data());

  /// Cancels/expires a pending request.
  static Future<void> cancelRequest(String token) async {
    await _db.collection(_collection).doc(token).update({'status': 'cancelled'});
  }
}
