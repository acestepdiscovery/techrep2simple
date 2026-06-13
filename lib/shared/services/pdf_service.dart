import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:image_picker/image_picker.dart';
import '../../features/reports/models/report_model.dart';

class PdfService {
  static const _blue = PdfColor.fromInt(0xFF1565C0);
  static const _blueLight = PdfColor.fromInt(0xFFE3F2FD);
  static const _grey = PdfColor.fromInt(0xFF757575);
  static const _divider = PdfColor.fromInt(0xFFDEE2E6);
  static const _white70 = PdfColor(1, 1, 1, 0.7);

  Future<Uint8List> generateReport(
    ReportModel report, {
    List<XFile> photos = const [],
    String? companyName,
    String? technicianName,
    Uint8List? logoBytes,
    String? companyAddress,
    String? companyPhone,
    String? companyEmail,
    String? companySiret,
    String? companyTva,
    String pdfTemplate = 'professionnel',
    String reportNumberFormat = '{num}',
  }) async {
    // Load signature images
    pw.MemoryImage? sigClientStart;
    pw.MemoryImage? sigTechStart;
    pw.MemoryImage? sigClient;
    pw.MemoryImage? sigTech;
    if (report.signatureClientStartData != null) {
      sigClientStart = pw.MemoryImage(base64Decode(report.signatureClientStartData!));
    }
    if (report.signatureTechStartData != null) {
      sigTechStart = pw.MemoryImage(base64Decode(report.signatureTechStartData!));
    }
    if (report.signatureClientData != null) {
      sigClient = pw.MemoryImage(base64Decode(report.signatureClientData!));
    }
    if (report.signatureTechData != null) {
      sigTech = pw.MemoryImage(base64Decode(report.signatureTechData!));
    }

    // Load photo images (mobile only)
    final photoImages = <pw.MemoryImage>[];
    if (!kIsWeb) {
      for (final xFile in photos) {
        try {
          final bytes = await xFile.readAsBytes();
          photoImages.add(pw.MemoryImage(bytes));
        } catch (_) {}
      }
    }

    final logo = logoBytes != null ? pw.MemoryImage(logoBytes) : null;
    final fmt = DateFormat('dd/MM/yyyy', 'fr_FR');
    final dateStr = report.endDate != null
        ? 'Du ${fmt.format(report.date)} au ${fmt.format(report.endDate!)}'
        : fmt.format(report.date);
    final reportNumber = resolveReportNumber(
      report.reportNumber,
      reportNumberFormat,
      clientName: report.clientName,
      date: report.date,
      technicianName: technicianName,
      companyName: companyName,
    );

    if (pdfTemplate == 'professionnel' || pdfTemplate == 'pro') {
      return _buildProfessionalDoc(
        report,
        sigClientStart: sigClientStart,
        sigTechStart: sigTechStart,
        sigClient: sigClient,
        sigTech: sigTech,
        photoImages: photoImages,
        dateStr: dateStr,
        reportNumber: reportNumber,
        companyName: companyName,
        technicianName: technicianName,
        logo: logo,
        companyAddress: companyAddress,
        companyPhone: companyPhone,
        companyEmail: companyEmail,
        companySiret: companySiret,
        companyTva: companyTva,
      );
    }

    // ── Simple layout (default) ──────────────────────────────────────────────
    final doc = pw.Document(
      title: 'Rapport d\'intervention — ${report.clientName}',
      author: companyName ?? 'Tech Report',
    );

    final baseStyle = pw.TextStyle(fontSize: 9);
    final boldStyle = pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 36),
        header: (ctx) => _buildHeader(
            report, companyName, technicianName, dateStr, reportNumber,
            logo: logo,
            companyAddress: companyAddress,
            companyPhone: companyPhone,
            companyEmail: companyEmail,
            companySiret: companySiret,
            companyTva: companyTva),
        footer: (ctx) => _buildFooter(ctx),
        build: (ctx) => [
          pw.SizedBox(height: 12),
          _buildClientSection(report, baseStyle, boldStyle),
          pw.SizedBox(height: 10),
          _buildInterventionSection(report, dateStr, baseStyle, boldStyle),
          if (_hasEquipment(report)) ...[
            pw.SizedBox(height: 10),
            _buildEquipmentSection(report, baseStyle, boldStyle),
          ],
          if (report.sectorFields.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            _buildSectorFieldsSection(report, baseStyle, boldStyle),
          ],
          pw.SizedBox(height: 10),
          _buildWorkSection(report, baseStyle),
          if (_hasBilling(report)) ...[
            pw.SizedBox(height: 10),
            _buildBillingSection(report, baseStyle, boldStyle),
          ],
          if (photoImages.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            _buildPhotosSection(photoImages),
          ],
          pw.SizedBox(height: 14),
          _buildSignaturesSection(
              sigClientStart: sigClientStart,
              sigTechStart: sigTechStart,
              sigClient: sigClient,
              sigTech: sigTech,
              date: dateStr,
              technicianName: technicianName,
              baseStyle: baseStyle,
              boldStyle: boldStyle),
        ],
      ),
    );

    return doc.save();
  }

  // ── Professional layout ──────────────────────────────────────────────────

  Future<Uint8List> _buildProfessionalDoc(
    ReportModel report, {
    pw.MemoryImage? sigClientStart,
    pw.MemoryImage? sigTechStart,
    required pw.MemoryImage? sigClient,
    required pw.MemoryImage? sigTech,
    required List<pw.MemoryImage> photoImages,
    required String dateStr,
    required String reportNumber,
    String? companyName,
    String? technicianName,
    pw.MemoryImage? logo,
    String? companyAddress,
    String? companyPhone,
    String? companyEmail,
    String? companySiret,
    String? companyTva,
  }) async {
    bool f(String? v) => v != null && v.trim().isNotEmpty;

    final doc = pw.Document(
      title: 'Rapport d\'intervention — ${report.clientName}',
      author: companyName ?? '',
    );

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 36),
      header: (ctx) {
        if (ctx.pageNumber > 1) {
          return pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(companyName ?? '',
                    style: const pw.TextStyle(fontSize: 8, color: _grey)),
                pw.Text('N° $reportNumber',
                    style: const pw.TextStyle(fontSize: 8, color: _grey)),
              ],
            ),
          );
        }
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (logo != null) ...[
                      pw.Container(
                          width: 60,
                          height: 60,
                          alignment: pw.Alignment.center,
                          child: pw.Image(logo, fit: pw.BoxFit.contain)),
                      pw.SizedBox(width: 12),
                    ],
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        if (f(companyName))
                          pw.Text(companyName!,
                              style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold, fontSize: 11)),
                        if (f(companyAddress))
                          pw.Text(companyAddress!,
                              style: const pw.TextStyle(fontSize: 9)),
                        pw.SizedBox(height: 3),
                        if (f(companyPhone))
                          pw.Text('TÉL : ${companyPhone!}',
                              style: const pw.TextStyle(fontSize: 9)),
                        if (f(companyEmail))
                          pw.Text('Mail : ${companyEmail!}',
                              style: const pw.TextStyle(fontSize: 9)),
                        if (f(companySiret))
                          pw.Text('Siret : ${companySiret!}',
                              style: const pw.TextStyle(fontSize: 9)),
                        if (f(companyTva))
                          pw.Text('N° Tva : ${companyTva!}',
                              style: const pw.TextStyle(fontSize: 9)),
                      ],
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('RAPPORT D\'INTERVENTION',
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold, fontSize: 15)),
                    pw.SizedBox(height: 4),
                    pw.Text('N° $reportNumber',
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold, fontSize: 10)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Divider(color: _grey, thickness: 0.5),
          ],
        );
      },
      footer: (ctx) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 8),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('N° $reportNumber',
                style: const pw.TextStyle(color: _grey, fontSize: 8)),
            pw.Text('Page ${ctx.pageNumber} / ${ctx.pagesCount}',
                style: const pw.TextStyle(color: _grey, fontSize: 8)),
          ],
        ),
      ),
      build: (ctx) => [
        pw.SizedBox(height: 8),
        // ── 2 columns: INFOS | SIGNATURES ───────────────────────────────────
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _divider),
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('INFOS',
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold, fontSize: 11)),
                    pw.SizedBox(height: 8),
                    _profRow('Client', report.clientName),
                    if (f(report.clientAddress))
                      _profRow('Adresse', report.clientAddress),
                    if (f(report.clientAddress))
                      _profRow('Lieu d\'intervention', report.clientAddress),
                    if (f(report.clientContact))
                      _profRow('Interlocuteur', report.clientContact),
                    if (f(technicianName)) _profRow('Technicien', technicianName!),
                    if (report.startTime != null)
                      _profRow('Début d\'intervention',
                          '$dateStr ${_timeStr(report.startTime!)}'),
                    if (report.endTime != null)
                      _profRow('Fin d\'intervention',
                          '$dateStr ${_timeStr(report.endTime!)}'),
                    _profRow('Sous contrat',
                        report.sousContrat ? 'Oui' : 'Non'),
                    // (#4b) Champs personnalisés saisis par l'utilisateur.
                    ...report.customFields.entries
                        .map((e) => _profRow(e.key, e.value)),
                  ],
                ),
              ),
            ),
            pw.SizedBox(width: 16),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(sigTechStart != null ? 'TECHNICIEN (DÉBUT)' : 'SIGNATURE INTERVENANT',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                  pw.SizedBox(height: 8),
                  pw.Container(
                    height: 90, width: double.infinity,
                    decoration: pw.BoxDecoration(border: pw.Border.all(color: _divider)),
                    child: (sigTechStart ?? sigTech) != null
                        ? pw.Center(child: pw.Image(sigTechStart ?? sigTech!, height: 80, fit: pw.BoxFit.contain))
                        : pw.SizedBox(),
                  ),
                  if (sigTech != null && sigTechStart != null) ...[
                    pw.SizedBox(height: 8),
                    pw.Text('TECHNICIEN (FIN)',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    pw.SizedBox(height: 8),
                    pw.Container(
                      height: 90, width: double.infinity,
                      decoration: pw.BoxDecoration(border: pw.Border.all(color: _divider)),
                      child: pw.Center(child: pw.Image(sigTech, height: 80, fit: pw.BoxFit.contain)),
                    ),
                  ],
                  pw.SizedBox(height: 16),
                  pw.Text(sigClientStart != null ? 'CLIENT (DÉBUT)' : 'SIGNATURE CLIENT',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                  pw.SizedBox(height: 8),
                  pw.Container(
                    height: 90, width: double.infinity,
                    decoration: pw.BoxDecoration(border: pw.Border.all(color: _divider)),
                    child: (sigClientStart ?? sigClient) != null
                        ? pw.Center(child: pw.Image(sigClientStart ?? sigClient!, height: 80, fit: pw.BoxFit.contain))
                        : pw.SizedBox(),
                  ),
                  if (sigClient != null && sigClientStart != null) ...[
                    pw.SizedBox(height: 8),
                    pw.Text('CLIENT (FIN)',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    pw.SizedBox(height: 8),
                    pw.Container(
                      height: 90, width: double.infinity,
                      decoration: pw.BoxDecoration(border: pw.Border.all(color: _divider)),
                      child: pw.Center(child: pw.Image(sigClient, height: 80, fit: pw.BoxFit.contain)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 16),
        // ── MOTIFS ──────────────────────────────────────────────────────────
        pw.Text('MOTIFS',
            style:
                pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
        pw.SizedBox(height: 6),
        pw.Text(
          report.description.isEmpty ? '—' : report.description,
          style: const pw.TextStyle(fontSize: 9, lineSpacing: 2),
        ),
        if (f(report.observations)) ...[
          pw.SizedBox(height: 12),
          pw.Text('OBSERVATIONS',
              style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold, fontSize: 11)),
          pw.SizedBox(height: 6),
          pw.Text(report.observations,
              style: const pw.TextStyle(fontSize: 9, lineSpacing: 2)),
        ],
        if (_hasBilling(report)) ...[
          pw.SizedBox(height: 16),
          _buildBillingSection(
              report,
              const pw.TextStyle(fontSize: 9),
              pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
        ],
        if (photoImages.isNotEmpty) ...[
          pw.SizedBox(height: 20),
          pw.Text('PHOTO(S)',
              style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold, fontSize: 11)),
          pw.SizedBox(height: 8),
          ..._profPhotosGrid(photoImages),
        ],
      ],
    ));

    return doc.save();
  }

  pw.Widget _profRow(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.RichText(
          text: pw.TextSpan(
            children: [
              pw.TextSpan(
                  text: '$label : ',
                  style: const pw.TextStyle(fontSize: 9, color: _grey)),
              pw.TextSpan(text: value, style: const pw.TextStyle(fontSize: 9)),
            ],
          ),
        ),
      );

  List<pw.Widget> _profPhotosGrid(List<pw.MemoryImage> images) {
    final rows = <pw.Widget>[];
    for (int i = 0; i < images.length; i += 2) {
      rows.add(pw.Row(children: [
        pw.Expanded(
          child: pw.Container(
            height: 160,
            margin: const pw.EdgeInsets.only(right: 4, bottom: 8),
            child: pw.Image(images[i], fit: pw.BoxFit.cover),
          ),
        ),
        pw.Expanded(
          child: i + 1 < images.length
              ? pw.Container(
                  height: 160,
                  margin: const pw.EdgeInsets.only(left: 4, bottom: 8),
                  child: pw.Image(images[i + 1], fit: pw.BoxFit.cover),
                )
              : pw.SizedBox(),
        ),
      ]));
    }
    return rows;
  }

  // ─── Header ─────────────────────────────────────────────────────────────────

  pw.Widget _buildHeader(
    ReportModel report,
    String? companyName,
    String? technicianName,
    String dateStr,
    String reportNumber, {
    pw.MemoryImage? logo,
    String? companyAddress,
    String? companyPhone,
    String? companyEmail,
    String? companySiret,
    String? companyTva,
  }) {
    bool filled(String? v) => v != null && v.trim().isNotEmpty;

    return pw.Container(
      decoration: const pw.BoxDecoration(
        color: _blue,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Row(
            children: [
              if (logo != null) ...[
                pw.Container(
                  width: 48,
                  height: 48,
                  alignment: pw.Alignment.center,
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.white,
                    borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  padding: const pw.EdgeInsets.all(3),
                  child: pw.Image(logo, fit: pw.BoxFit.contain),
                ),
                pw.SizedBox(width: 12),
              ],
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'RAPPORT D\'INTERVENTION',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  if (filled(companyName))
                    pw.Text(companyName!,
                        style: const pw.TextStyle(color: _white70, fontSize: 10)),
                  if (filled(companyAddress))
                    pw.Text(companyAddress!,
                        style: const pw.TextStyle(color: _white70, fontSize: 8)),
                  if (filled(companyPhone) || filled(companyEmail))
                    pw.Text(
                      [
                        if (filled(companyPhone)) companyPhone!,
                        if (filled(companyEmail)) companyEmail!,
                      ].join('  ·  '),
                      style: const pw.TextStyle(color: _white70, fontSize: 8),
                    ),
                  if (filled(companySiret))
                    pw.Text('SIRET : ${companySiret!}',
                        style: const pw.TextStyle(color: _white70, fontSize: 8)),
                  if (filled(companyTva))
                    pw.Text('N° TVA : ${companyTva!}',
                        style: const pw.TextStyle(color: _white70, fontSize: 8)),
                  if (filled(technicianName))
                    pw.Text('Tech. : ${technicianName!}',
                        style: const pw.TextStyle(color: _white70, fontSize: 9)),
                ],
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'N° $reportNumber',
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(dateStr,
                  style: const pw.TextStyle(color: _white70, fontSize: 10)),
              pw.Text(_sectorLabel(report.sector),
                  style: const pw.TextStyle(color: _white70, fontSize: 9)),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Footer ─────────────────────────────────────────────────────────────────

  pw.Widget _buildFooter(pw.Context ctx) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 8),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Compte Rendu Technique IA',
                style: const pw.TextStyle(
                    color: _grey, fontSize: 8)),
            pw.Text(
                'Page ${ctx.pageNumber} / ${ctx.pagesCount}',
                style: const pw.TextStyle(
                    color: _grey, fontSize: 8)),
          ],
        ),
      );

  // ─── Sections ────────────────────────────────────────────────────────────────

  pw.Widget _buildClientSection(
      ReportModel report,
      pw.TextStyle baseStyle,
      pw.TextStyle boldStyle) =>
      _section(
        title: 'CLIENT',
        child: pw.Table(
          children: [
            _tableRow('Nom', report.clientName, baseStyle, boldStyle),
            if (report.clientAddress.isNotEmpty)
              _tableRow('Adresse', report.clientAddress, baseStyle,
                  boldStyle),
            if (report.clientPhone.isNotEmpty)
              _tableRow('Téléphone', report.clientPhone, baseStyle,
                  boldStyle),
            if (report.clientContact.isNotEmpty)
              _tableRow('Contact', report.clientContact, baseStyle,
                  boldStyle),
            if (report.contractNumber.isNotEmpty)
              _tableRow('N° contrat', report.contractNumber, baseStyle,
                  boldStyle),
            _tableRow('Sous contrat', report.sousContrat ? 'Oui' : 'Non',
                baseStyle, boldStyle),
            // (#4b) Champs personnalisés saisis par l'utilisateur.
            ...report.customFields.entries.map(
                (e) => _tableRow(e.key, e.value, baseStyle, boldStyle)),
          ],
        ),
      );

  pw.Widget _buildInterventionSection(
      ReportModel report,
      String dateStr,
      pw.TextStyle baseStyle,
      pw.TextStyle boldStyle) =>
      _section(
        title: 'INTERVENTION',
        child: pw.Table(
          children: [
            if (report.interventionType.isNotEmpty)
              _tableRow('Type', report.interventionType, baseStyle,
                  boldStyle),
            _tableRow('Date', dateStr, baseStyle, boldStyle),
            if (report.startTime != null)
              _tableRow(
                'Horaire',
                '${_timeStr(report.startTime!)} – '
                    '${report.endTime != null ? _timeStr(report.endTime!) : "—"}',
                baseStyle,
                boldStyle,
              ),
          ],
        ),
      );

  pw.Widget _buildEquipmentSection(
      ReportModel report,
      pw.TextStyle baseStyle,
      pw.TextStyle boldStyle) =>
      _section(
        title: 'ÉQUIPEMENT',
        child: pw.Table(
          children: [
            if (report.equipmentType.isNotEmpty)
              _tableRow('Type', report.equipmentType, baseStyle,
                  boldStyle),
            if (report.equipmentBrand.isNotEmpty)
              _tableRow('Marque', report.equipmentBrand, baseStyle,
                  boldStyle),
            if (report.equipmentModel.isNotEmpty)
              _tableRow('Modèle', report.equipmentModel, baseStyle,
                  boldStyle),
            if (report.equipmentSerial.isNotEmpty)
              _tableRow('N° série', report.equipmentSerial, baseStyle,
                  boldStyle),
          ],
        ),
      );

  pw.Widget _buildSectorFieldsSection(
      ReportModel report,
      pw.TextStyle baseStyle,
      pw.TextStyle boldStyle) {
    final entries = report.sectorFields.entries
        .where((e) => e.value != null && e.value.toString().isNotEmpty)
        .toList();
    return _section(
      title: report.sector.label.toUpperCase(),
      child: pw.Table(
        children: entries
            .map((e) => _tableRow(
                  _formatKey(e.key),
                  e.value.toString(),
                  baseStyle,
                  boldStyle,
                ))
            .toList(),
      ),
    );
  }

  pw.Widget _buildWorkSection(
      ReportModel report, pw.TextStyle baseStyle) =>
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _section(
            title: 'TRAVAUX RÉALISÉS',
            child: pw.Text(
              report.description.isEmpty ? '—' : report.description,
              style: baseStyle.copyWith(lineSpacing: 2),
            ),
          ),
          if (report.observations.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            _section(
              title: 'OBSERVATIONS / RECOMMANDATIONS',
              child: pw.Text(
                report.observations,
                style: baseStyle.copyWith(lineSpacing: 2),
              ),
            ),
          ],
        ],
      );

  pw.Widget _buildBillingSection(
      ReportModel report,
      pw.TextStyle baseStyle,
      pw.TextStyle boldStyle) {
    final labor = (report.laborHours ?? 0) * (report.laborRate ?? 0);
    final matsTotal = report.materials
        .fold<double>(0, (a, m) => a + m.total);
    final total = labor + matsTotal;

    final rows = <pw.TableRow>[];

    if (report.laborHours != null && report.laborHours! > 0) {
      rows.add(_tableRow(
        'Main-d\'œuvre',
        '${report.laborHours!.toStringAsFixed(1)} h × '
            '${(report.laborRate ?? 0).toStringAsFixed(2)} €/h = '
            '${labor.toStringAsFixed(2)} €',
        baseStyle,
        boldStyle,
      ));
    }

    for (final m in report.materials) {
      rows.add(_tableRow(
        m.label,
        '${m.quantity} × ${m.unitPrice.toStringAsFixed(2)} € = '
            '${m.total.toStringAsFixed(2)} €',
        baseStyle,
        boldStyle,
      ));
    }

    return _section(
      title: 'FACTURATION',
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Table(children: rows),
          pw.Divider(color: _divider),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Text('TOTAL HT : ',
                  style: boldStyle.copyWith(
                      color: _blue, fontSize: 10)),
              pw.Text('${total.toStringAsFixed(2)} €',
                  style: boldStyle.copyWith(
                      color: _blue, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPhotosSection(
      List<pw.MemoryImage> images) {
    final rows = <pw.Widget>[];
    for (int i = 0; i < images.length; i += 2) {
      rows.add(
        pw.Row(
          children: [
            pw.Expanded(
              child: pw.Container(
                height: 140,
                margin: const pw.EdgeInsets.only(right: 4, bottom: 8),
                child:
                    pw.Image(images[i], fit: pw.BoxFit.cover),
              ),
            ),
            pw.Expanded(
              child: i + 1 < images.length
                  ? pw.Container(
                      height: 140,
                      margin: const pw.EdgeInsets.only(
                          left: 4, bottom: 8),
                      child: pw.Image(images[i + 1],
                          fit: pw.BoxFit.cover),
                    )
                  : pw.SizedBox(),
            ),
          ],
        ),
      );
    }
    return _section(
      title: 'PHOTOS',
      child: pw.Column(children: rows),
    );
  }

  pw.Widget _buildSignaturesSection({
    pw.MemoryImage? sigClientStart,
    pw.MemoryImage? sigTechStart,
    pw.MemoryImage? sigClient,
    pw.MemoryImage? sigTech,
    required String date,
    String? technicianName,
    required pw.TextStyle baseStyle,
    required pw.TextStyle boldStyle,
  }) {
    final hasStart = sigClientStart != null || sigTechStart != null;
    final hasEnd = sigClient != null || sigTech != null;

    pw.Widget sigRow(String clientLabel, pw.MemoryImage? c, String techLabel, pw.MemoryImage? t) =>
        pw.Row(children: [
          pw.Expanded(child: _signatureBox(clientLabel, null, c, date, boldStyle)),
          pw.SizedBox(width: 16),
          pw.Expanded(child: _signatureBox(techLabel, technicianName, t, date, boldStyle)),
        ]);

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _divider),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      padding: const pw.EdgeInsets.all(14),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (hasStart) ...[
            pw.Text('Début d\'intervention',
                style: boldStyle.copyWith(fontSize: 8, color: _grey)),
            pw.SizedBox(height: 6),
            sigRow('Signature client (début)', sigClientStart,
                'Signature technicien (début)', sigTechStart),
            if (hasEnd) pw.SizedBox(height: 12),
          ],
          if (hasEnd) ...[
            if (hasStart)
              pw.Text('Fin d\'intervention',
                  style: boldStyle.copyWith(fontSize: 8, color: _grey)),
            if (hasStart) pw.SizedBox(height: 6),
            sigRow('Signature client${hasStart ? ' (fin)' : ''}', sigClient,
                'Signature technicien${hasStart ? ' (fin)' : ''}', sigTech),
          ],
          if (!hasStart && !hasEnd)
            sigRow('Signature client', null, 'Signature technicien', null),
        ],
      ),
    );
  }

  pw.Widget _signatureBox(
    String label,
    String? name,
    pw.MemoryImage? sig,
    String date,
    pw.TextStyle boldStyle,
  ) =>
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(label,
              style: boldStyle.copyWith(
                  fontSize: 9, color: _grey)),
          if (name != null && name.isNotEmpty)
            pw.Text(name,
                style: const pw.TextStyle(
                    fontSize: 8, color: _grey)),
          pw.SizedBox(height: 6),
          pw.Container(
            height: 80,
            width: double.infinity,
            decoration: const pw.BoxDecoration(
              color: PdfColors.grey50,
              border: pw.Border(
                  bottom: pw.BorderSide(color: _grey)),
            ),
            child: sig != null
                ? pw.Center(
                    child: pw.Image(sig,
                        height: 70, fit: pw.BoxFit.contain))
                : pw.SizedBox(),
          ),
          pw.SizedBox(height: 4),
          pw.Text(date,
              style: const pw.TextStyle(
                  fontSize: 8, color: _grey)),
        ],
      );

  // ─── Report number resolver ───────────────────────────────────────────────────

  static String resolveReportNumber(
    int num,
    String pattern, {
    String? clientName,
    DateTime? date,
    String? technicianName,
    String? companyName,
  }) {
    final d = date ?? DateTime.now();
    final clientSlug = (clientName ?? '')
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final companySlug = (companyName ?? '')
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final tech = (technicianName ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase())
        .join('');
    return pattern
        .replaceAll('{num}', num.toString().padLeft(3, '0'))
        .replaceAll('{client}', clientSlug.isEmpty ? 'CLI' : clientSlug)
        .replaceAll('{company}', companySlug.isEmpty ? 'ENT' : companySlug)
        .replaceAll('{year}', d.year.toString())
        .replaceAll('{month}', d.month.toString().padLeft(2, '0'))
        .replaceAll('{day}', d.day.toString().padLeft(2, '0'))
        .replaceAll('{tech}', tech);
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────────

  pw.Widget _section(
          {required String title, required pw.Widget child}) =>
      pw.Container(
        decoration: const pw.BoxDecoration(
          color: _blueLight,
          borderRadius:
              pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        padding: const pw.EdgeInsets.all(12),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                color: _blue,
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
            pw.SizedBox(height: 6),
            child,
          ],
        ),
      );

  pw.TableRow _tableRow(String label, String value,
      pw.TextStyle baseStyle, pw.TextStyle boldStyle) =>
      pw.TableRow(
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Text(label,
                style: baseStyle.copyWith(color: _grey)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Text(value, style: boldStyle),
          ),
        ],
      );

  bool _hasEquipment(ReportModel r) =>
      r.equipmentType.isNotEmpty ||
      r.equipmentBrand.isNotEmpty ||
      r.equipmentModel.isNotEmpty ||
      r.equipmentSerial.isNotEmpty;

  bool _hasBilling(ReportModel r) =>
      (r.laborHours != null && r.laborHours! > 0) ||
      r.materials.isNotEmpty;

  String _timeStr(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  String _sectorLabel(SectorTemplate s) => s.label;

  String _formatKey(String k) =>
      k.replaceAll('_', ' ').split(' ').map((w) {
        if (w.isEmpty) return w;
        return w[0].toUpperCase() + w.substring(1);
      }).join(' ');

  // ── Invoice PDF ─────────────────────────────────────────────────────────────

  Future<Uint8List> generateInvoice(
    ReportModel report, {
    String? companyName,
    String? companyAddress,
    String? companyPhone,
    String? companyEmail,
    String? companySiret,
    Uint8List? logoBytes,
  }) async {
    final logo = logoBytes != null ? pw.MemoryImage(logoBytes) : null;
    final fmt = DateFormat('dd/MM/yyyy', 'fr_FR');
    final today = fmt.format(DateTime.now());
    final invoiceNum =
        'FAC-${report.reportNumber.toString().padLeft(3, '0')}-${DateTime.now().year}';

    final laborTotal = (report.laborHours ?? 0) * (report.laborRate ?? 0);
    final matsTotal =
        report.materials.fold<double>(0, (a, m) => a + m.total);
    final subtotal = laborTotal + matsTotal;
    final tva = subtotal * 0.20;
    final total = subtotal + tva;

    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Header
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (logo != null)
                    pw.Image(logo, width: 80, height: 50, fit: pw.BoxFit.contain),
                  if (companyName != null)
                    pw.Text(companyName,
                        style: pw.TextStyle(
                            fontSize: 16, fontWeight: pw.FontWeight.bold)),
                  if (companyAddress != null)
                    pw.Text(companyAddress,
                        style: const pw.TextStyle(fontSize: 10)),
                  if (companyPhone != null)
                    pw.Text(companyPhone,
                        style: const pw.TextStyle(fontSize: 10)),
                  if (companyEmail != null)
                    pw.Text(companyEmail,
                        style: const pw.TextStyle(fontSize: 10)),
                  if (companySiret != null)
                    pw.Text('SIRET : $companySiret',
                        style: const pw.TextStyle(fontSize: 9,
                            color: PdfColor(0.4, 0.4, 0.4))),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: pw.BoxDecoration(
                      color: _blue,
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Text('FACTURE',
                        style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text('N° $invoiceNum',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold,
                          fontSize: 11)),
                  pw.Text('Date : $today',
                      style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 28),
          // Client block
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: _blueLight,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Facturé à :',
                    style: pw.TextStyle(fontSize: 10, color: _grey)),
                pw.SizedBox(height: 4),
                pw.Text(report.clientName,
                    style: pw.TextStyle(
                        fontSize: 13, fontWeight: pw.FontWeight.bold)),
                if (report.clientAddress.isNotEmpty)
                  pw.Text(report.clientAddress,
                      style: const pw.TextStyle(fontSize: 10)),
                if (report.clientContact.isNotEmpty)
                  pw.Text(report.clientContact,
                      style: const pw.TextStyle(fontSize: 10)),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          // Ref rapport
          pw.Text(
              'Réf. rapport : #${report.reportNumber.toString().padLeft(3, '0')} '
              '— ${fmt.format(report.date)} — ${report.interventionType}',
              style: const pw.TextStyle(fontSize: 10,
                  color: PdfColor(0.4, 0.4, 0.4))),
          pw.SizedBox(height: 16),
          // Table header
          pw.Container(
            color: _blue,
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: pw.Row(
              children: [
                pw.Expanded(flex: 5,
                    child: pw.Text('Désignation',
                        style: pw.TextStyle(color: PdfColors.white,
                            fontWeight: pw.FontWeight.bold, fontSize: 10))),
                pw.SizedBox(
                    width: 60,
                    child: pw.Text('Qté',
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(color: PdfColors.white,
                            fontWeight: pw.FontWeight.bold, fontSize: 10))),
                pw.SizedBox(
                    width: 70,
                    child: pw.Text('P.U. HT',
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(color: PdfColors.white,
                            fontWeight: pw.FontWeight.bold, fontSize: 10))),
                pw.SizedBox(
                    width: 75,
                    child: pw.Text('Total HT',
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(color: PdfColors.white,
                            fontWeight: pw.FontWeight.bold, fontSize: 10))),
              ],
            ),
          ),
          // Rows
          if (report.laborHours != null && report.laborHours! > 0)
            _invoiceRow(
              'Main-d\'œuvre — ${report.technicianName ?? ''}',
              '${report.laborHours!.toStringAsFixed(1)} h',
              report.laborRate ?? 0,
              laborTotal,
              even: false,
            ),
          ...report.materials.asMap().entries.map((e) => _invoiceRow(
                '${e.value.label}${e.value.reference.isNotEmpty ? ' (réf. ${e.value.reference})' : ''}',
                '${e.value.quantity}',
                e.value.unitPrice,
                e.value.total,
                even: e.key.isEven,
              )),
          pw.SizedBox(height: 16),
          // Totals
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.SizedBox(
              width: 200,
              child: pw.Column(
                children: [
                  _totalRow('Sous-total HT', subtotal),
                  _totalRow('TVA (20 %)', tva),
                  pw.Divider(color: _divider),
                  _totalRow('Total TTC', total, bold: true),
                ],
              ),
            ),
          ),
          pw.Spacer(),
          pw.Divider(color: _divider),
          pw.Text(
              'Merci pour votre confiance. Paiement à réception de facture.',
              style: const pw.TextStyle(fontSize: 9,
                  color: PdfColor(0.5, 0.5, 0.5))),
        ],
      ),
    ));
    return doc.save();
  }

  pw.Widget _invoiceRow(String label, String qty, double pu, double total,
      {required bool even}) {
    return pw.Container(
      color: even ? const PdfColor(0.97, 0.97, 0.97) : PdfColors.white,
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: pw.Row(
        children: [
          pw.Expanded(flex: 5,
              child: pw.Text(label, style: const pw.TextStyle(fontSize: 10))),
          pw.SizedBox(
              width: 60,
              child: pw.Text(qty,
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 10))),
          pw.SizedBox(
              width: 70,
              child: pw.Text('${pu.toStringAsFixed(2)} €',
                  textAlign: pw.TextAlign.right,
                  style: const pw.TextStyle(fontSize: 10))),
          pw.SizedBox(
              width: 75,
              child: pw.Text('${total.toStringAsFixed(2)} €',
                  textAlign: pw.TextAlign.right,
                  style: const pw.TextStyle(fontSize: 10))),
        ],
      ),
    );
  }

  pw.Widget _totalRow(String label, double amount, {bool bold = false}) {
    final style = bold
        ? pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)
        : const pw.TextStyle(fontSize: 10);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: style),
          pw.Text('${amount.toStringAsFixed(2)} €', style: style),
        ],
      ),
    );
  }
}
