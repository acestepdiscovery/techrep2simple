import 'dart:convert';
import 'package:http/http.dart' as http;

class AnalyticsService {
  static const _projectId = 'smallfun';
  static const _collection = 'analytics';

  static Future<void> log({
    required String event,
    String? userUid,
    String? userName,
    String? clientName,
    String? companyName,
    String? technicianName,
    int? reportNumber,
    String? sector,
    String? interventionType,
    String? companyId,       // (monitoring) équipe liée au rapport, si rapport d'équipe
    bool isTeamReport = false,
  }) async {
    try {
      final url = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$_projectId'
        '/databases/(default)/documents/$_collection',
      );

      final fields = <String, dynamic>{
        'event': {'stringValue': event},
        'timestamp': {
          'timestampValue': DateTime.now().toUtc().toIso8601String(),
        },
        if (userUid != null && userUid.isNotEmpty)
          'userUid': {'stringValue': userUid},
        if (userName != null && userName.isNotEmpty)
          'userName': {'stringValue': userName},
        if (clientName != null && clientName.isNotEmpty)
          'clientName': {'stringValue': clientName},
        if (companyName != null && companyName.isNotEmpty)
          'companyName': {'stringValue': companyName},
        if (technicianName != null && technicianName.isNotEmpty)
          'technicianName': {'stringValue': technicianName},
        if (reportNumber != null && reportNumber > 0)
          'reportNumber': {'integerValue': reportNumber.toString()},
        if (sector != null && sector.isNotEmpty)
          'sector': {'stringValue': sector},
        if (interventionType != null && interventionType.isNotEmpty)
          'interventionType': {'stringValue': interventionType},
        if (companyId != null && companyId.isNotEmpty)
          'companyId': {'stringValue': companyId},
        'isTeamReport': {'booleanValue': isTeamReport},
      };

      await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'fields': fields}),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // fire-and-forget — never block the user
    }
  }
}
