import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;

/// Polices des PDF (2026-10-03).
///
/// La police par défaut du package pdf (Helvetica) ne sait dessiner que les codes
/// 0–255 : sans aide, « € », « — », « ’ » (apostrophe automatique de l'iPhone),
/// « … », « • » ou les lettres d'Europe centrale sortaient EN BLANC dans le PDF.
///
/// - Cas général : on GARDE Helvetica (aspect historique des PDF, mise en page
///   inchangée) et on ajoute Noto Sans comme POLICE DE SECOURS, utilisée seulement
///   pour les caractères qu'Helvetica ne connaît pas.
/// - Langues dont l'alphabet sort d'Helvetica ([unicodeLanguages], ex. polonais) :
///   Noto Sans pour TOUT le document, pour un rendu homogène (le secours ne
///   distingue pas le gras).
///
/// Polices embarquées dans l'app (`assets/fonts/`, licence OFL) → fonctionne hors
/// connexion. Les PDF n'embarquent que les lettres utilisées (sous-ensemble).
class PdfFonts {
  static const unicodeLanguages = {'pl'};

  static pw.Font? _regular;
  static pw.Font? _bold;

  static Future<void> _load() async {
    _regular ??= pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    _bold ??= pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
  }

  static Future<pw.Font> regular() async {
    await _load();
    return _regular!;
  }

  static Future<pw.Font> bold() async {
    await _load();
    return _bold!;
  }

  /// Thème de police d'un PDF. [language] = code langue (défaut : langue de l'app).
  static Future<pw.ThemeData> theme({String? language}) async {
    await _load();
    final lang = (language ?? Intl.defaultLocale ?? 'fr').split(RegExp('[_-]')).first;
    if (unicodeLanguages.contains(lang)) {
      return pw.ThemeData.withFont(
        base: _regular,
        bold: _bold,
        fontFallback: [_regular!, _bold!],
      );
    }
    return pw.ThemeData.withFont(
      base: pw.Font.helvetica(),
      bold: pw.Font.helveticaBold(),
      italic: pw.Font.helveticaOblique(),
      boldItalic: pw.Font.helveticaBoldOblique(),
      fontFallback: [_regular!, _bold!],
    );
  }
}
