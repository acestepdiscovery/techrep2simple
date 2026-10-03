import 'dart:convert';
import 'dart:typed_data';
import 'package:easy_localization/easy_localization.dart';
import '../../features/reports/models/sector_options.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'pdf_fonts.dart';

/// Generates a "validation PDF" from a frozen report snapshot.
/// No image pixels — only placeholder rectangles with labels.
/// Used by admins/validators to review a report before approving or rejecting.
class ValidationPdfService {
  static Future<Uint8List> generate(Map<String, dynamic> snap) async {
    final doc = pw.Document();

    // (2026-10-03) Polices embarquées dans l'app (avant : téléchargées → échouait hors connexion).
    final techFont = await PdfFonts.regular();
    final boldFont = await PdfFonts.bold();

    // ── Parse snapshot fields ─────────────────────────────────────────────────
    String s(String k) => (snap[k] as String? ?? '').trim();
    String dateStr(String k) {
      final raw = snap[k] as String?;
      if (raw == null) return '';
      try {
        return DateFormat.yMd().format(DateTime.parse(raw));
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
                pw.Text('vp_title'.tr(),
                    style: pw.TextStyle(
                        font: boldFont,
                        fontSize: 16,
                        color: PdfColors.blueGrey900)),
                pw.Text(
                  'vp_snapshot_submitted'.tr(args: [dateStr('date')]),
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
                'vp_snapshot_warning'.tr(),
                style: pw.TextStyle(
                    font: techFont, fontSize: 7, color: PdfColors.orange900),
              ),
            ),
            pw.SizedBox(height: 12),
          ],
        ),
        build: (ctx) => [
          // ── Client ──────────────────────────────────────────────────────────
          _section('pdf_sec_client'.tr(), [
            if (s('client_name').isNotEmpty) _row('pdf_lbl_name'.tr(), s('client_name')),
            if (s('client_address').isNotEmpty) _row('pdf_lbl_address'.tr(), s('client_address')),
            if (s('client_phone').isNotEmpty) _row('pdf_lbl_phone'.tr(), s('client_phone')),
            if (s('client_contact').isNotEmpty) _row('pdf_lbl_contact_short'.tr(), s('client_contact')),
            if (s('contract_number').isNotEmpty) _row('pdf_lbl_contract'.tr(), s('contract_number')),
          ]),
          // ── Intervention ────────────────────────────────────────────────────
          _section('pdf_sec_intervention'.tr(), [
            if (dateStr('date').isNotEmpty) _row('pdf_lbl_date'.tr(), dateStr('date')),
            if (s('intervention_type').isNotEmpty) _row('pdf_lbl_type'.tr(), s('intervention_type')),
            if (s('technician_name').isNotEmpty) _row('pdf_lbl_technician'.tr(), s('technician_name')),
            if (s('description').isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('pdf_lbl_description'.tr(), style: label),
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
                    pw.Text('pdf_lbl_observations'.tr(), style: label),
                    pw.SizedBox(height: 2),
                    pw.Text(s('observations'), style: value),
                  ],
                ),
              ),
          ]),
          // ── Équipement ──────────────────────────────────────────────────────
          if ([s('equipment_type'), s('equipment_brand'), s('equipment_model'), s('equipment_serial')]
                  .any((v) => v.isNotEmpty))
            _section('pdf_sec_equipment'.tr(), [
              if (s('equipment_type').isNotEmpty) _row('pdf_lbl_type'.tr(), s('equipment_type')),
              if (s('equipment_brand').isNotEmpty) _row('pdf_lbl_brand'.tr(), s('equipment_brand')),
              if (s('equipment_model').isNotEmpty) _row('pdf_lbl_model'.tr(), s('equipment_model')),
              if (s('equipment_serial').isNotEmpty) _row('pdf_lbl_serial'.tr(), s('equipment_serial')),
            ]),
          // ── Champs secteur ──────────────────────────────────────────────────
          if (sectorFields.isNotEmpty)
            _section('vp_sec_specific'.tr(), [
              ...sectorFields.entries.where((e) => e.value.toString().isNotEmpty).map(
                    (e) => _row(
                      e.key.replaceAll('_', ' '),
                      sectorValueLabel(e.value.toString()),
                    ),
                  ),
            ]),
          // ── Photos (placeholders) ────────────────────────────────────────
          if (photoCount > 0)
            _section('vp_photos_count'.tr(args: ['$photoCount']), [
              pw.Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(photoCount, (i) {
                  final name = i < photoNames.length ? photoNames[i] : 'vp_photo_n'.tr(args: ['${i + 1}']);
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
                        pw.Text('vp_photo_n'.tr(args: ['${i + 1}']),
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
            _section('pdf_sec_billing'.tr(), [
              if (laborHours > 0)
                _row('pdf_lbl_labor'.tr(),
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
              _row('pdf_lbl_total'.tr(),
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
                    pw.Text('pdf_sig_client_base'.tr(), style: label),
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
                            child: pw.Text('vp_not_available'.tr(),
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
                    pw.Text('pdf_sig_tech_base'.tr(), style: label),
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
                            child: pw.Text('vp_not_available'.tr(),
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
            pw.Text('vp_footer_warning'.tr(),
                style: pw.TextStyle(
                    font: techFont, fontSize: 7, color: PdfColors.blueGrey300)),
            pw.Text('pdf_page'.tr(args: ['${ctx.pageNumber}', '${ctx.pagesCount}']),
                style: pw.TextStyle(
                    font: techFont, fontSize: 7, color: PdfColors.blueGrey300)),
          ],
        ),
      ),
    );

    return doc.save();
  }
}
