import 'dart:math' show max;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../../features/reports/models/report_model.dart';
import '../../features/clients/models/client_model.dart';

class LocalDbService {
  static final LocalDbService _instance = LocalDbService._internal();
  factory LocalDbService() => _instance;
  LocalDbService._internal();

  Database? _db;

  // In-memory fallback for web (data not persisted across reloads — for UI testing only)
  final List<Map<String, dynamic>> _webReports = [];
  final List<Map<String, dynamic>> _webClients = [];
  final Map<String, String> _webSettings = {};
  final List<Map<String, dynamic>> _webPresets = [];

  Future<Database> get db async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), 'techreport.db');
    return openDatabase(path, version: 9, onCreate: _onCreate, onUpgrade: _onUpgrade);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE reports ADD COLUMN report_number INTEGER DEFAULT 0');
    }
    if (oldVersion < 3) {
      try { await db.execute('ALTER TABLE reports ADD COLUMN pdf_template TEXT'); } catch (_) {}
    }
    if (oldVersion < 4) {
      try { await db.execute('ALTER TABLE reports ADD COLUMN report_number_format TEXT'); } catch (_) {}
    }
    if (oldVersion < 5) {
      for (final col in [
        'ALTER TABLE reports ADD COLUMN end_date TEXT',
        'ALTER TABLE reports ADD COLUMN client_id TEXT',
        'ALTER TABLE reports ADD COLUMN signature_client_start_data TEXT',
        'ALTER TABLE reports ADD COLUMN signature_tech_start_data TEXT',
      ]) {
        try { await db.execute(col); } catch (_) {}
      }
      await db.execute('''
        CREATE TABLE IF NOT EXISTS report_presets (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          created_at TEXT NOT NULL,
          data TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 6) {
      try {
        await db.execute('ALTER TABLE report_presets ADD COLUMN is_archived INTEGER DEFAULT 0');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE reports ADD COLUMN rejection_comment TEXT');
      } catch (_) {}
    }
    if (oldVersion < 7) {
      try {
        await db.execute('ALTER TABLE reports ADD COLUMN signed_remotely INTEGER DEFAULT 0');
      } catch (_) {}
    }
    if (oldVersion < 8) {
      try {
        await db.execute('ALTER TABLE reports ADD COLUMN ai_enhanced INTEGER DEFAULT 0');
      } catch (_) {}
    }
    if (oldVersion < 9) {
      // (#4b) Toggle « sous contrat » + champs libres (label→valeur, JSON).
      try {
        await db.execute('ALTER TABLE reports ADD COLUMN sous_contrat INTEGER DEFAULT 0');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE reports ADD COLUMN custom_fields TEXT');
      } catch (_) {}
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE reports (
        id TEXT PRIMARY KEY,
        report_number INTEGER DEFAULT 0,
        client_id TEXT,
        client_name TEXT NOT NULL,
        client_address TEXT,
        client_phone TEXT,
        client_contact TEXT,
        contract_number TEXT,
        intervention_type TEXT,
        sector TEXT DEFAULT 'generic',
        date TEXT NOT NULL,
        end_date TEXT,
        start_time TEXT,
        end_time TEXT,
        description TEXT,
        observations TEXT,
        equipment_type TEXT,
        equipment_brand TEXT,
        equipment_model TEXT,
        equipment_serial TEXT,
        sector_fields TEXT DEFAULT '{}',
        status TEXT DEFAULT 'draft',
        photos TEXT DEFAULT '[]',
        signature_client_start_data TEXT,
        signature_tech_start_data TEXT,
        signature_client_data TEXT,
        signature_tech_data TEXT,
        pdf_local_path TEXT,
        cloud_url TEXT,
        technician_id TEXT,
        technician_name TEXT,
        company_id TEXT,
        labor_hours REAL,
        labor_rate REAL,
        materials TEXT DEFAULT '[]',
        pdf_template TEXT,
        report_number_format TEXT,
        rejection_comment TEXT,
        signed_remotely INTEGER DEFAULT 0,
        ai_enhanced INTEGER DEFAULT 0,
        sous_contrat INTEGER DEFAULT 0,
        custom_fields TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE clients (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        address TEXT,
        phone TEXT,
        email TEXT,
        contact_person TEXT,
        contract_number TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)');
    await db.execute('''
      CREATE TABLE report_presets (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        data TEXT NOT NULL,
        is_archived INTEGER DEFAULT 0
      )
    ''');
  }

  Future<int> getMaxReportNumber() async {
    if (kIsWeb) return _webReports.length;
    final database = await db;
    final result = await database.rawQuery('SELECT COALESCE(MAX(report_number), 0) as max_num FROM reports');
    return (result.first['max_num'] as int?) ?? 0;
  }

  Future<int> getNextReportNumber() async {
    if (kIsWeb) return _webReports.length + 1;
    final database = await db;
    final result = await database.rawQuery('SELECT COALESCE(MAX(report_number), 0) as max_num FROM reports');
    final maxExisting = (result.first['max_num'] as int?) ?? 0;
    final startStr = await getSetting('report_number_start');
    final start = int.tryParse(startStr ?? '1') ?? 1;
    return max(start, maxExisting + 1);
  }

  // ─── Reports ───────────────────────────────────────────────────────────────

  Future<void> insertReport(ReportModel report) async {
    if (kIsWeb) {
      _webReports.removeWhere((r) => r['id'] == report.id);
      _webReports.add(report.toMap());
      return;
    }
    final database = await db;
    await database.insert('reports', report.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateReport(ReportModel report) async {
    if (kIsWeb) {
      final i = _webReports.indexWhere((r) => r['id'] == report.id);
      if (i >= 0) _webReports[i] = report.toMap();
      return;
    }
    final database = await db;
    await database.update('reports', report.toMap(), where: 'id = ?', whereArgs: [report.id]);
  }

  Future<void> deleteReport(String id) async {
    if (kIsWeb) { _webReports.removeWhere((r) => r['id'] == id); return; }
    final database = await db;
    await database.delete('reports', where: 'id = ?', whereArgs: [id]);
  }

  Future<ReportModel?> getReport(String id) async {
    if (kIsWeb) {
      final map = _webReports.where((r) => r['id'] == id).firstOrNull;
      return map != null ? ReportModel.fromMap(map) : null;
    }
    final database = await db;
    final maps = await database.query('reports', where: 'id = ?', whereArgs: [id]);
    return maps.isEmpty ? null : ReportModel.fromMap(maps.first);
  }

  Future<List<ReportModel>> getAllReports({String? statusFilter}) async {
    if (kIsWeb) {
      final list = statusFilter != null
          ? _webReports.where((r) => r['status'] == statusFilter).toList()
          : List<Map<String, dynamic>>.from(_webReports);
      list.sort((a, b) => (b['updated_at'] as String).compareTo(a['updated_at'] as String));
      return list.map(ReportModel.fromMap).toList();
    }
    final database = await db;
    final maps = statusFilter != null
        ? await database.query('reports', where: 'status = ?', whereArgs: [statusFilter], orderBy: 'updated_at DESC')
        : await database.query('reports', orderBy: 'updated_at DESC');
    return maps.map(ReportModel.fromMap).toList();
  }

  Future<List<ReportModel>> getReportsByClient(String clientId) async {
    if (kIsWeb) {
      return _webReports
          .where((r) => r['client_id'] == clientId)
          .map(ReportModel.fromMap)
          .toList();
    }
    final database = await db;
    final maps = await database.query('reports',
        where: 'client_id = ?', whereArgs: [clientId], orderBy: 'updated_at DESC');
    return maps.map(ReportModel.fromMap).toList();
  }

  // ─── Clients ───────────────────────────────────────────────────────────────

  Future<void> insertClient(ClientModel client) async {
    if (kIsWeb) {
      _webClients.removeWhere((c) => c['id'] == client.id);
      _webClients.add(client.toMap());
      return;
    }
    final database = await db;
    await database.insert('clients', client.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateClient(ClientModel client) async {
    if (kIsWeb) {
      final i = _webClients.indexWhere((c) => c['id'] == client.id);
      if (i >= 0) _webClients[i] = client.toMap();
      return;
    }
    final database = await db;
    await database.update('clients', client.toMap(), where: 'id = ?', whereArgs: [client.id]);
  }

  Future<void> deleteClient(String id) async {
    if (kIsWeb) { _webClients.removeWhere((c) => c['id'] == id); return; }
    final database = await db;
    await database.delete('clients', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<ClientModel>> getAllClients() async {
    if (kIsWeb) {
      final list = List<Map<String, dynamic>>.from(_webClients);
      list.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
      return list.map(ClientModel.fromMap).toList();
    }
    final database = await db;
    final maps = await database.query('clients', orderBy: 'name ASC');
    return maps.map(ClientModel.fromMap).toList();
  }

  // ─── Settings ──────────────────────────────────────────────────────────────

  Future<String?> getSetting(String key) async {
    if (kIsWeb) return _webSettings[key];
    final database = await db;
    final maps = await database.query('settings', where: 'key = ?', whereArgs: [key]);
    return maps.isEmpty ? null : maps.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    if (kIsWeb) { _webSettings[key] = value; return; }
    final database = await db;
    await database.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ─── Report Presets ────────────────────────────────────────────────────────

  Future<void> savePreset(ReportPreset preset) async {
    if (kIsWeb) {
      _webPresets.removeWhere((p) => p['id'] == preset.id);
      _webPresets.add(preset.toMap());
      return;
    }
    final database = await db;
    await database.insert('report_presets', preset.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<ReportPreset>> getAllPresets() async {
    if (kIsWeb) {
      return _webPresets.map(ReportPreset.fromMap).where((p) => !p.isArchived).toList();
    }
    final database = await db;
    final maps = await database.query('report_presets',
        where: 'is_archived = 0', orderBy: 'created_at DESC');
    return maps.map(ReportPreset.fromMap).toList();
  }

  Future<List<ReportPreset>> getArchivedPresets() async {
    if (kIsWeb) {
      return _webPresets.map(ReportPreset.fromMap).where((p) => p.isArchived).toList();
    }
    final database = await db;
    final maps = await database.query('report_presets',
        where: 'is_archived = 1', orderBy: 'created_at DESC');
    return maps.map(ReportPreset.fromMap).toList();
  }

  Future<void> archivePreset(String id, {bool archive = true}) async {
    if (kIsWeb) {
      final i = _webPresets.indexWhere((p) => p['id'] == id);
      if (i >= 0) _webPresets[i] = {..._webPresets[i], 'is_archived': archive ? 1 : 0};
      return;
    }
    final database = await db;
    await database.update('report_presets', {'is_archived': archive ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deletePreset(String id) async {
    if (kIsWeb) { _webPresets.removeWhere((p) => p['id'] == id); return; }
    final database = await db;
    await database.delete('report_presets', where: 'id = ?', whereArgs: [id]);
  }

  /// Wipes all user-specific local data (reports, clients, settings).
  /// Called when a different account signs in on the same device.
  /// [keepReports] = true : on conserve les rapports (et clients) locaux au
  /// changement de compte. L'utilisateur accepte la « contamination » des
  /// documents sur un appareil de confiance (cf. 2.1) ; on n'efface que
  /// l'identité (settings) — le nom d'entreprise reste donc nettoyé. La
  /// suppression de compte, elle, efface tout (keepReports=false).
  Future<void> clearUserData({bool keepReports = false}) async {
    if (kIsWeb) {
      if (!keepReports) {
        _webReports.clear();
        _webClients.clear();
      }
      _webSettings.clear();
      _webPresets.clear();
      return;
    }
    final database = await db;
    if (!keepReports) {
      await database.delete('reports');
      await database.delete('clients');
    }
    await database.delete('settings');
    await database.delete('report_presets');
  }
}
