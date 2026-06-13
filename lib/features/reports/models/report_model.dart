import 'dart:convert';

enum ReportStatus { draft, submitted, pendingValidation, validated, rejected }

enum SectorTemplate {
  generic,
  plomberie,
  incendie,
  maintenance,
  it,
  nettoyage,
  btp,
  transport,
}

extension SectorTemplateLabel on SectorTemplate {
  String get label => switch (this) {
        SectorTemplate.generic => 'Générique',
        SectorTemplate.plomberie => 'Tuyauterie / Plomberie',
        SectorTemplate.incendie => 'Sécurité incendie',
        SectorTemplate.maintenance => 'Maintenance industrielle',
        SectorTemplate.it => 'Informatique / IT',
        SectorTemplate.nettoyage => 'Nettoyage industriel',
        SectorTemplate.btp => 'BTP / Travaux publics',
        SectorTemplate.transport => 'Transport',
      };
}

class MaterialItem {
  final String reference;
  final String label;
  final double quantity;
  final double unitPrice;

  const MaterialItem({
    required this.reference,
    required this.label,
    required this.quantity,
    required this.unitPrice,
  });

  double get total => quantity * unitPrice;

  Map<String, dynamic> toMap() => {
        'reference': reference,
        'label': label,
        'quantity': quantity,
        'unitPrice': unitPrice,
      };

  factory MaterialItem.fromMap(Map<String, dynamic> m) => MaterialItem(
        reference: m['reference'] ?? '',
        label: m['label'] ?? '',
        quantity: (m['quantity'] ?? 0).toDouble(),
        unitPrice: (m['unitPrice'] ?? 0).toDouble(),
      );
}

// ─── Report Preset ────────────────────────────────────────────────────────────

class ReportPreset {
  final String id;
  final String name;
  final DateTime createdAt;
  final Map<String, dynamic> data;
  final bool isArchived;

  const ReportPreset({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.data,
    this.isArchived = false,
  });

  ReportPreset copyWith({bool? isArchived}) => ReportPreset(
        id: id,
        name: name,
        createdAt: createdAt,
        data: data,
        isArchived: isArchived ?? this.isArchived,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'created_at': createdAt.toIso8601String(),
        'data': jsonEncode(data),
        'is_archived': isArchived ? 1 : 0,
      };

  factory ReportPreset.fromMap(Map<String, dynamic> m) => ReportPreset(
        id: m['id'],
        name: m['name'],
        createdAt: DateTime.parse(m['created_at']),
        data: jsonDecode(m['data']) as Map<String, dynamic>,
        isArchived: (m['is_archived'] as int? ?? 0) == 1,
      );
}

// ─── Report Model ─────────────────────────────────────────────────────────────

class ReportModel {
  final String id;
  final int reportNumber;
  final String? clientId;
  final String clientName;
  final String clientAddress;
  final String clientPhone;
  final String clientContact;
  final String contractNumber;
  final String interventionType;
  final SectorTemplate sector;
  // date = start date; endDate = for multi-day interventions
  final DateTime date;
  final DateTime? endDate;
  final DateTime? startTime;
  final DateTime? endTime;
  final String description;
  final String observations;
  // Equipment
  final String equipmentType;
  final String equipmentBrand;
  final String equipmentModel;
  final String equipmentSerial;
  // Sector-specific extras stored as JSON
  final Map<String, dynamic> sectorFields;
  // Status
  final ReportStatus status;
  // Media
  final List<String> photosPaths;
  // base64-encoded PNG signatures
  // Start-of-intervention signatures
  final String? signatureClientStartData;
  final String? signatureTechStartData;
  // End-of-intervention signatures (original fields kept for backwards compat)
  final String? signatureClientData;
  final String? signatureTechData;
  // Output
  final String? pdfLocalPath;
  final String? cloudUrl;
  // Per-report overrides (null = use global setting)
  final String? pdfTemplate;
  final String? reportNumberFormat;
  // Team
  final String? technicianId;
  final String? technicianName;
  final String? companyId;
  // Billing
  final double? laborHours;
  final double? laborRate;
  final List<MaterialItem> materials;
  // Rejection (set by admin when rejecting a team report)
  final String? rejectionComment;
  // Remote signature — true once client signed remotely (locks the report)
  final bool signedRemotely;
  // True when report was created or enhanced by AI (shows badge)
  final bool aiEnhanced;
  // (#4b) « Sous contrat ? » + champs libres (label → valeur), ajoutés par l'user.
  final bool sousContrat;
  final Map<String, String> customFields;
  // Meta
  final DateTime createdAt;
  final DateTime updatedAt;

  const ReportModel({
    required this.id,
    this.reportNumber = 0,
    this.clientId,
    required this.clientName,
    this.clientAddress = '',
    this.clientPhone = '',
    this.clientContact = '',
    this.contractNumber = '',
    this.interventionType = '',
    this.sector = SectorTemplate.generic,
    required this.date,
    this.endDate,
    this.startTime,
    this.endTime,
    this.description = '',
    this.observations = '',
    this.equipmentType = '',
    this.equipmentBrand = '',
    this.equipmentModel = '',
    this.equipmentSerial = '',
    this.sectorFields = const {},
    this.status = ReportStatus.draft,
    this.photosPaths = const [],
    this.signatureClientStartData,
    this.signatureTechStartData,
    this.signatureClientData,
    this.signatureTechData,
    this.pdfLocalPath,
    this.cloudUrl,
    this.pdfTemplate,
    this.reportNumberFormat,
    this.technicianId,
    this.technicianName,
    this.companyId,
    this.laborHours,
    this.laborRate,
    this.materials = const [],
    this.rejectionComment,
    this.signedRemotely = false,
    this.aiEnhanced = false,
    this.sousContrat = false,
    this.customFields = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  ReportModel copyWith({
    int? reportNumber,
    String? clientId,
    bool clearClientId = false,
    String? clientName,
    String? clientAddress,
    String? clientPhone,
    String? clientContact,
    String? contractNumber,
    String? interventionType,
    SectorTemplate? sector,
    DateTime? date,
    DateTime? endDate,
    bool clearEndDate = false,
    DateTime? startTime,
    DateTime? endTime,
    String? description,
    String? observations,
    String? equipmentType,
    String? equipmentBrand,
    String? equipmentModel,
    String? equipmentSerial,
    Map<String, dynamic>? sectorFields,
    ReportStatus? status,
    List<String>? photosPaths,
    String? signatureClientStartData,
    bool clearSignatureClientStart = false,
    String? signatureTechStartData,
    bool clearSignatureTechStart = false,
    String? signatureClientData,
    bool clearSignatureClient = false,
    String? signatureTechData,
    bool clearSignatureTech = false,
    String? pdfLocalPath,
    String? cloudUrl,
    String? pdfTemplate,
    bool clearPdfTemplate = false,
    String? reportNumberFormat,
    bool clearReportNumberFormat = false,
    String? technicianId,
    String? technicianName,
    String? companyId,
    double? laborHours,
    double? laborRate,
    List<MaterialItem>? materials,
    String? rejectionComment,
    bool clearRejectionComment = false,
    bool? signedRemotely,
    bool? aiEnhanced,
    bool? sousContrat,
    Map<String, String>? customFields,
  }) =>
      ReportModel(
        id: id,
        reportNumber: reportNumber ?? this.reportNumber,
        clientId: clearClientId ? null : (clientId ?? this.clientId),
        clientName: clientName ?? this.clientName,
        clientAddress: clientAddress ?? this.clientAddress,
        clientPhone: clientPhone ?? this.clientPhone,
        clientContact: clientContact ?? this.clientContact,
        contractNumber: contractNumber ?? this.contractNumber,
        interventionType: interventionType ?? this.interventionType,
        sector: sector ?? this.sector,
        date: date ?? this.date,
        endDate: clearEndDate ? null : (endDate ?? this.endDate),
        startTime: startTime ?? this.startTime,
        endTime: endTime ?? this.endTime,
        description: description ?? this.description,
        observations: observations ?? this.observations,
        equipmentType: equipmentType ?? this.equipmentType,
        equipmentBrand: equipmentBrand ?? this.equipmentBrand,
        equipmentModel: equipmentModel ?? this.equipmentModel,
        equipmentSerial: equipmentSerial ?? this.equipmentSerial,
        sectorFields: sectorFields ?? this.sectorFields,
        status: status ?? this.status,
        photosPaths: photosPaths ?? this.photosPaths,
        signatureClientStartData: clearSignatureClientStart ? null : (signatureClientStartData ?? this.signatureClientStartData),
        signatureTechStartData: clearSignatureTechStart ? null : (signatureTechStartData ?? this.signatureTechStartData),
        signatureClientData: clearSignatureClient ? null : (signatureClientData ?? this.signatureClientData),
        signatureTechData: clearSignatureTech ? null : (signatureTechData ?? this.signatureTechData),
        pdfLocalPath: pdfLocalPath ?? this.pdfLocalPath,
        cloudUrl: cloudUrl ?? this.cloudUrl,
        pdfTemplate: clearPdfTemplate ? null : (pdfTemplate ?? this.pdfTemplate),
        reportNumberFormat: clearReportNumberFormat ? null : (reportNumberFormat ?? this.reportNumberFormat),
        technicianId: technicianId ?? this.technicianId,
        technicianName: technicianName ?? this.technicianName,
        companyId: companyId ?? this.companyId,
        laborHours: laborHours ?? this.laborHours,
        laborRate: laborRate ?? this.laborRate,
        materials: materials ?? this.materials,
        rejectionComment: clearRejectionComment ? null : (rejectionComment ?? this.rejectionComment),
        signedRemotely: signedRemotely ?? this.signedRemotely,
        aiEnhanced: aiEnhanced ?? this.aiEnhanced,
        sousContrat: sousContrat ?? this.sousContrat,
        customFields: customFields ?? this.customFields,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'report_number': reportNumber,
        'client_id': clientId,
        'client_name': clientName,
        'client_address': clientAddress,
        'client_phone': clientPhone,
        'client_contact': clientContact,
        'contract_number': contractNumber,
        'intervention_type': interventionType,
        'sector': sector.name,
        'date': date.toIso8601String(),
        'end_date': endDate?.toIso8601String(),
        'start_time': startTime?.toIso8601String(),
        'end_time': endTime?.toIso8601String(),
        'description': description,
        'observations': observations,
        'equipment_type': equipmentType,
        'equipment_brand': equipmentBrand,
        'equipment_model': equipmentModel,
        'equipment_serial': equipmentSerial,
        'sector_fields': jsonEncode(sectorFields),
        'status': status.name,
        'photos': jsonEncode(photosPaths),
        'signature_client_start_data': signatureClientStartData,
        'signature_tech_start_data': signatureTechStartData,
        'signature_client_data': signatureClientData,
        'signature_tech_data': signatureTechData,
        'pdf_local_path': pdfLocalPath,
        'cloud_url': cloudUrl,
        'pdf_template': pdfTemplate,
        'report_number_format': reportNumberFormat,
        'technician_id': technicianId,
        'technician_name': technicianName,
        'company_id': companyId,
        'labor_hours': laborHours,
        'labor_rate': laborRate,
        'materials': jsonEncode(materials.map((m) => m.toMap()).toList()),
        'rejection_comment': rejectionComment,
        'signed_remotely': signedRemotely ? 1 : 0,
        'ai_enhanced': aiEnhanced ? 1 : 0,
        'sous_contrat': sousContrat ? 1 : 0,
        'custom_fields': jsonEncode(customFields),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory ReportModel.fromMap(Map<String, dynamic> m) => ReportModel(
        id: m['id'],
        reportNumber: (m['report_number'] as int?) ?? 0,
        clientId: m['client_id'],
        clientName: m['client_name'] ?? '',
        clientAddress: m['client_address'] ?? '',
        clientPhone: m['client_phone'] ?? '',
        clientContact: m['client_contact'] ?? '',
        contractNumber: m['contract_number'] ?? '',
        interventionType: m['intervention_type'] ?? '',
        sector: SectorTemplate.values.firstWhere(
          (s) => s.name == m['sector'],
          orElse: () => SectorTemplate.generic,
        ),
        date: DateTime.parse(m['date']),
        endDate: m['end_date'] != null ? DateTime.parse(m['end_date']) : null,
        startTime: m['start_time'] != null ? DateTime.parse(m['start_time']) : null,
        endTime: m['end_time'] != null ? DateTime.parse(m['end_time']) : null,
        description: m['description'] ?? '',
        observations: m['observations'] ?? '',
        equipmentType: m['equipment_type'] ?? '',
        equipmentBrand: m['equipment_brand'] ?? '',
        equipmentModel: m['equipment_model'] ?? '',
        equipmentSerial: m['equipment_serial'] ?? '',
        sectorFields: m['sector_fields'] != null
            ? Map<String, dynamic>.from(jsonDecode(m['sector_fields']))
            : {},
        status: ReportStatus.values.firstWhere(
          (s) => s.name == m['status'],
          orElse: () => ReportStatus.draft,
        ),
        photosPaths: m['photos'] != null ? List<String>.from(jsonDecode(m['photos'])) : [],
        signatureClientStartData: m['signature_client_start_data'],
        signatureTechStartData: m['signature_tech_start_data'],
        signatureClientData: m['signature_client_data'],
        signatureTechData: m['signature_tech_data'],
        pdfLocalPath: m['pdf_local_path'],
        cloudUrl: m['cloud_url'],
        pdfTemplate: m['pdf_template'],
        reportNumberFormat: m['report_number_format'],
        technicianId: m['technician_id'],
        technicianName: m['technician_name'],
        companyId: m['company_id'],
        laborHours: m['labor_hours']?.toDouble(),
        laborRate: m['labor_rate']?.toDouble(),
        materials: m['materials'] != null
            ? (jsonDecode(m['materials']) as List)
                .map((e) => MaterialItem.fromMap(Map<String, dynamic>.from(e)))
                .toList()
            : [],
        rejectionComment: m['rejection_comment'] as String?,
        signedRemotely: (m['signed_remotely'] as int? ?? 0) == 1,
        aiEnhanced: (m['ai_enhanced'] as int? ?? 0) == 1,
        sousContrat: (m['sous_contrat'] as int? ?? 0) == 1,
        customFields: m['custom_fields'] != null
            ? Map<String, String>.from(jsonDecode(m['custom_fields']))
            : {},
        createdAt: DateTime.parse(m['created_at']),
        updatedAt: DateTime.parse(m['updated_at']),
      );
}
