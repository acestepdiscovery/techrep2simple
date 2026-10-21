// (2026-10-21) « Votre rapport sur mesure » : l'utilisateur nous envoie son rapport
// actuel (ou un formulaire qu'il aimerait retrouver dans l'app) pour qu'on l'ajoute
// comme modèle. Pro : envoi direct (Firebase Storage, dossier réservé à cette app) ;
// sinon : adresse e-mail. Fonctions pures ici (testées), écran dans
// screens/custom_report_request_screen.dart.

/// Adresse de contact de l'app (donnée par le user le 21/10).
const String kContactEmail = 'businessKC123@proton.me';

/// Dossier Storage réservé à cette app (règles Storage à part, voir le GUI).
const String kTemplateRequestsFolder = 'raptech1_template_requests';

const int kTemplateMaxFiles = 5;
const int kTemplateMaxBytes = 15 * 1024 * 1024;

const Map<String, String> _types = {
  'pdf': 'application/pdf',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'heic': 'image/heic',
};

/// Extensions acceptées (sélecteur de fichiers).
List<String> get templateAllowedExtensions => _types.keys.toList();

String _ext(String name) {
  final i = name.lastIndexOf('.');
  return i < 0 ? '' : name.substring(i + 1).toLowerCase();
}

/// Type MIME du fichier, null s'il n'est pas accepté.
String? templateContentType(String fileName) => _types[_ext(fileName)];

/// Raison du refus (« type » / « size »), null si le fichier est accepté.
String? templateFileError(String fileName, int sizeBytes) {
  if (templateContentType(fileName) == null) return 'type';
  if (sizeBytes > kTemplateMaxBytes) return 'size';
  return null;
}

/// Chemin Storage : raptech1_template_requests/UID/AAAAMMJJ-HHMMSS_N_nom.ext
/// (nom nettoyé : lettres, chiffres, . _ - ; 80 caractères max).
String templateRequestPath(String uid, DateTime now, int index, String fileName) {
  String two(int v) => v.toString().padLeft(2, '0');
  final stamp = '${now.year}${two(now.month)}${two(now.day)}-'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  var safe = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  if (safe.length > 80) safe = safe.substring(safe.length - 80);
  return '$kTemplateRequestsFolder/$uid/${stamp}_${index}_$safe';
}
