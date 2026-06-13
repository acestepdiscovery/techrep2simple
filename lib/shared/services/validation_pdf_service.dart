import 'dart:convert';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Generates a "validation PDF" from a frozen report snapshot.
/// No image pixels — only placeholder rectangles with labels.
/// Used by admins/validators to review a report before approving or rejecting.
class ValidationPdfService {
  static Future<Uint8List> generate(Map<String, dynamic> snap) async {
    final doc = pw.Document();

    final techFont = await PdfGoogleFonts.notoSansRegular();
    final boldFont = await PdfGoogleFonts.notoSansBold();

    // ── Parse snapshot fields ─────────────────────────────────────────────────
    String s(String k) => (snap[k] as String? ?? '').trim();
    String dateStr(String k) {
      final raw = snap[k] as String?;
      if (raw == null) return '';
      try {
        return DateFormat('dd/MM/yyyy').format(DateTime.parse(raw));
      } catch (_) {
        return raw;
      }
    }

    final photoCount = (snap['photo_count'] as int?) ?? 0;
    final photoNames = (snap['photo_names'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        List.generate(photoCount, (i) => 'photo_${i + 1}');

    final materialsRaw = snap['materials'] as List?;
    final materials = materialsRaw?.map((m) => m as Map<String, dynamic>).toList() ?? [];

    final sectorFieldsRaw = snap['sector_fields'];
    Map<String, dynamic> sectorFields = {};
    if (sectorFieldsRaw is Map) {
      sectorFields = Map<String, dynamic>.from(sectorFieldsRaw);
    }

    final laborHours = (snap['labor_hours'] as num?)?.toDouble() ?? 0.0;
    final laborRate = (snap['labor_rate'] as num?)?.toDouble() ?? 0.0;
    final laborTotal = laborHours * laborRate;
    final matsTotal = materials.fold<double>(0, (sum, m) {
      final qty = (m['quantity'] as num?)?.toDouble() ?? 0;
      final up = (m['unitPrice'] as num?)?.toDouble() ?? 0;
      return sum + qty * up;
    });

    final sigClientB64 = snap['signature_client'] as String?;
    final sigTechB64 = snap['signature_tech'] as String?;

    pw.MemoryImage? _decodeB64(String? b64) {
      if (b64 == null || b64.isEmpty) return null;
      try {
        final clean = b64.contains(',') ? b64.split(',').last : b64;
        return pw.MemoryImage(base64Decode(clean));
      } catch (_) {
        return null;
      }
    }

    final sigClient = _decodeB64(sigClientB64);
    final sigTech = _decodeB64(sigTechB64);

    // ── Styles ────────────────────────────────────────────────────────────────
    final sectionTitle = pw.TextStyle(
        font: boldFont, fontSize: 10, color: PdfColors.blueGrey800);
    final label = pw.TextStyle(
        font: boldFont, fontSize: 8, color: PdfColors.blueGrey600);
    final value = pw.TextStyle(font: techFont, fontSize: 9);

    pw.Widget _row(String lbl, String val) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: 110,
                child: pw.Text(lbl, style: label),
              ),
              pw.Expanded(child: pw.Text(val, style: value)),
            ],
          ),
        );

    pw.Widget _section(String title, List<pw.Widget> children) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title.toUpperCase(), style: sectionTitle),
            pw.Divider(color: PdfColors.blueGrey200, thickness: 0.5),
            pw.SizedBox(height: 4),
            ...children,
            pw.SizedBox(height: 14),
          ],
        );

    // ── Build page ────────────────────────────────────────────────────────────
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 36),
        header: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Rapport de validation',
                    style: pw.TextStyle(
                        font: boldFont,
                        fontSize: 16,
                        color: PdfColors.blueGrey900)),
                pw.Text(
                  'Snapshot soumis le ${dateStr('submitted_at'.isEmpty ? 'date' : 'date')}',
                  style: pw.TextStyle(
                      font: techFont,
                      fontSize: 8,
                      color: PdfColors.blueGrey400),
                ),
              ],
            ),
            pw.SizedBox(height: 2),
            pw.Container(
              color: PdfColors.orange200,
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: pw.Text(
                'Document généré depuis le snapshot figé au moment de la soumission — '
                'les modifications ultérieures du rapport ne sont pas reflétées ici.',
                style: pw.TextStyle(
                    font: techFont, fontSize: 7, color: PdfColors.orange900),
              ),
            ),
            pw.SizedBox(height: 12),
          ],
        ),
        build: (ctx) => [
          // ── Client ──────────────────────────────────────────────────────────
          _section('Client', [
            if (s('client_name').isNotEmpty) _row('Nom', s('client_name')),
            if (s('client_address').isNotEmpty) _row('Adresse', s('client_address')),
            if (s('client_phone').isNotEmpty) _row('Téléphone', s('client_phone')),
            if (s('client_contact').isNotEmpty) _row('Contact', s('client_contact')),
            if (s('contract_number').isNotEmpty) _row('N° contrat', s('contract_number')),
          ]),
          // ── Intervention ────────────────────────────────────────────────────
          _section('Intervention', [
            if (dateStr('date').isNotEmpty) _row('Date', dateStr('date')),
            if (s('intervention_type').isNotEmpty) _row('Type', s('intervention_type')),
            if (s('technician_name').isNotEmpty) _row('Technicien', s('technician_name')),
            if (s('description').isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Description', style: label),
                    pw.SizedBox(height: 2),
                    pw.Text(s('description'), style: value),
                  ],
                ),
              ),
            if (s('observations').isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Observations', style: label),
                    pw.SizedBox(height: 2),
                    pw.Text(s('observations'), style: value),
                  ],
                ),
              ),
          ]),
          // ── Équipement ──────────────────────────────────────────────────────
          if ([s('equipment_type'), s('equipment_brand'), s('equipment_model'), s('equipment_serial')]
                  .any((v) => v.isNotEmpty))
            _section('Équipement', [
              if (s('equipment_type').isNotEmpty) _row('Type', s('equipment_type')),
              if (s('equipment_brand').isNotEmpty) _row('Marque', s('equipment_brand')),
              if (s('equipment_model').isNotEmpty) _row('Modèle', s('equipment_model')),
              if (s('equipment_serial').isNotEmpty) _row('N° série', s('equipment_serial')),
            ]),
          // ── Champs secteur ──────────────────────────────────────────────────
          if (sectorFields.isNotEmpty)
            _section('Informations spécifiques', [
              ...sectorFields.entries.where((e) => e.value.toString().isNotEmpty).map(
                    (e) => _row(
                      e.key.replaceAll('_', ' '),
                      e.value.toString(),
                    ),
                  ),
            ]),
          // ── Photos (placeholders) ────────────────────────────────────────
          if (photoCount > 0)
            _section('Photos ($photoCount)', [
              pw.Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(photoCount, (i) {
                  final name = i < photoNames.length ? photoNames[i] : 'Photo ${i + 1}';
                  return pw.Container(
                    width: 120,
                    height: 90,
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey200,
                      borderRadius: pw.BorderRadius.circular(4),
                      border: pw.Border.all(color: PdfColors.grey400),
                    ),
                    alignment: pw.Alignment.center,
                    child: pw.Column(
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      children: [
                        pw.Text('Photo ${i + 1}',
                            style: pw.TextStyle(
                                font: boldFont,
                                fontSize: 9,
                                color: PdfColors.blueGrey600)),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          name.length > 18 ? '${name.substring(0, 16)}…' : name,
                          style: pw.TextStyle(
                              font: techFont,
                              fontSize: 6,
                              color: PdfColors.blueGrey400),
                          textAlign: pw.TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }),
              ),
              pw.SizedBox(height: 6),
            ]),
          // ── Facturation ─────────────────────────────────────────────────────
          if (laborHours > 0 || materials.isNotEmpty)
            _section('Facturation', [
              if (laborHours > 0)
                _row('Main d\'œuvre',
                    '$laborHours h × ${laborRate.toStringAsFixed(2)} € = ${laborTotal.toStringAsFixed(2)} €'),
              ...materials.map((m) {
                final qty = (m['quantity'] as num?)?.toDouble() ?? 0;
                final up = (m['unitPrice'] as num?)?.toDouble() ?? 0;
                return _row(
                  m['label']?.toString() ?? '',
                  '${qty}× ${up.toStringAsFixed(2)} € = ${(qty * up).toStringAsFixed(2)} €',
                );
              }),
              pw.Divider(color: PdfColors.blueGrey200, thickness: 0.5),
              _row('Total',
                  '${(laborTotal + matsTotal).toStringAsFixed(2)} €'),
            ]),
          // ── Signatures ──────────────────────────────────────────────────────
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Signature client', style: label),
                    pw.SizedBox(height: 4),
                    sigClient != null
                        ? pw.Image(sigClient, width: 120, height: 60, fit: pw.BoxFit.contain)
                        : pw.Container(
                            width: 120, height: 60,
                            decoration: pw.BoxDecoration(
                              color: PdfColors.grey100,
                              border: pw.Border.all(color: PdfColors.grey300),
                              borderRadius: pw.BorderRadius.circular(4),
                            ),
                            alignment: pw.Alignment.center,
                            child: pw.Text('Non disponible',
                                style: pw.TextStyle(
                                    font: techFont,
                                    fontSize: 7,
                                    color: PdfColors.grey500)),
                          ),
                  ],
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Signature technicien', style: label),
                    pw.SizedBox(height: 4),
                    sigTech != null
                        ? pw.Image(sigTech, width: 120, height: 60, fit: pw.BoxFit.contain)
                        : pw.Container(
                            width: 120, height: 60,
                            decoration: pw.BoxDecoration(
                              color: PdfColors.grey100,
                              border: pw.Border.all(color: PdfColors.grey300),
                              borderRadius: pw.BorderRadius.circular(4),
                            ),
                            alignment: pw.Alignment.center,
                            child: pw.Text('Non disponible',
                                style: pw.TextStyle(
                                    font: techFont,
                                    fontSize: 7,
                                    color: PdfColors.grey500)),
                          ),
                  ],
                ),
              ),
            ],
          ),
        ],
        footer: (ctx) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Document de validation — ne pas transmettre au client',
                style: pw.TextStyle(
                    font: techFont, fontSize: 7, color: PdfColors.blueGrey300)),
            pw.Text('Page ${ctx.pageNumber}/${ctx.pagesCount}',
                style: pw.TextStyle(
                    font: techFont, fontSize: 7, color: PdfColors.blueGrey300)),
          ],
        ),
      ),
    );

    return doc.save();
  }
}
