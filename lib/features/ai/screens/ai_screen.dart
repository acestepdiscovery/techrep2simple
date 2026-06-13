import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/services/ai_service.dart';
import '../../../shared/services/local_db_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../reports/models/report_model.dart';
import '../../reports/providers/reports_provider.dart';
import '../../subscription/paywall_bottom_sheet.dart';
import '../../subscription/subscription_provider.dart';

class AiScreen extends ConsumerStatefulWidget {
  const AiScreen({super.key});

  @override
  ConsumerState<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends ConsumerState<AiScreen> {
  int _usedThisMonth = 0;
  int _quota = 10;

  void _updateUsage(AiActionResult result) {
    if (result.isSuccess) {
      setState(() {
        _usedThisMonth = result.used;
        _quota = result.quota;
      });
    }
  }

  String? get _companyId =>
      ref.read(teamStateProvider).valueOrNull?.companyId;

  void _showPaywall() {
    PaywallBottomSheet.show(context);
  }

  Future<void> _openVoiceSheet() async {
    final result = await showModalBottomSheet<AiActionResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _VoiceSheet(companyId: _companyId),
    );
    if (result == null) return;
    if (!mounted) return;
    if (result.needsSubscription) { _showPaywall(); return; }
    if (!result.isSuccess) {
      _showError(result.errorMessage);
      return;
    }
    _updateUsage(result);
    _showFieldsPreview(result.fields);
  }

  Future<void> _openImageSheet() async {
    final result = await showModalBottomSheet<AiActionResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _ImageSheet(companyId: _companyId),
    );
    if (result == null) return;
    if (!mounted) return;
    if (result.needsSubscription) { _showPaywall(); return; }
    if (!result.isSuccess) {
      _showError(result.errorMessage);
      return;
    }
    _updateUsage(result);
    _showFieldsPreview(result.fields);
  }

  Future<void> _openImproveSheet() async {
    final result = await showModalBottomSheet<_ImproveOutcome>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _ImproveSheet(companyId: _companyId),
    );
    if (result == null) return;
    if (!mounted) return;
    if (result.error != null) {
      final fake = AiActionResult(error: result.error);
      if (fake.needsSubscription) { _showPaywall(); return; }
      _showError(fake.errorMessage);
      return;
    }
    _updateUsage(result.aiResult!);
    ref.invalidate(reportsProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('✨ Rapport amélioré créé'),
        action: SnackBarAction(
          label: 'Voir',
          onPressed: () => context.push('/report/${result.newReportId}'),
        ),
      ),
    );
  }

  Future<void> _openDocumentSheet() async {
    final result = await showModalBottomSheet<AiActionResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _DocumentSheet(companyId: _companyId),
    );
    if (result == null) return;
    if (!mounted) return;
    if (result.needsSubscription) { _showPaywall(); return; }
    if (!result.isSuccess) {
      _showError(result.errorMessage);
      return;
    }
    _updateUsage(result);
    _showFieldsPreview(result.fields);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  void _showFieldsPreview(Map<String, String> fields) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _FieldsPreviewSheet(
        fields: fields,
        onCreateReport: () {
          Navigator.pop(ctx);
          _createReportFromFields(fields);
        },
      ),
    );
  }

  void _createReportFromFields(Map<String, String> fields) {
    // Parse date string DD/MM/YYYY → ISO if provided
    String? parsedDate;
    final dateStr = fields['date'] ?? '';
    if (dateStr.isNotEmpty) {
      try {
        final p = dateStr.split('/');
        if (p.length == 3) {
          parsedDate = DateTime(
            int.parse(p[2]), int.parse(p[1]), int.parse(p[0]),
          ).toIso8601String();
        }
      } catch (_) {}
    }

    // Parse labor_hours string → num
    double? laborHours;
    final lh = fields['labor_hours'] ?? '';
    if (lh.isNotEmpty) laborHours = double.tryParse(lh.replaceAll(',', '.'));

    final preset = ReportPreset(
      id: const Uuid().v4(),
      name: 'IA',
      createdAt: DateTime.now(),
      data: {
        'client_name': fields['client_name'] ?? '',
        'client_address': fields['client_address'] ?? '',
        'client_phone': fields['client_phone'] ?? '',
        'client_contact': fields['client_contact'] ?? '',
        'contract_number': fields['contract_number'] ?? '',
        if (parsedDate != null) 'date': parsedDate,
        'intervention_type': fields['intervention_type'] ?? '',
        'description': fields['description'] ?? '',
        'observations': fields['observations'] ?? '',
        'equipment_type': fields['equipment_type'] ?? '',
        'equipment_brand': fields['equipment_brand'] ?? '',
        'equipment_model': fields['equipment_model'] ?? '',
        'equipment_serial': fields['equipment_serial'] ?? '',
        if (laborHours != null) 'labor_hours': laborHours,
        'ai_enhanced': 1,
      },
    );
    context.push('/create-report', extra: preset);
  }

  @override
  Widget build(BuildContext context) {
    final isSubscribed = ref.watch(effectiveSubscriptionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Assistant IA'),
        actions: [
          if (_usedThisMonth > 0)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '$_usedThisMonth/$_quota',
                  style: const TextStyle(
                      fontSize: 13, color: Colors.white70),
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primaryLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, color: Colors.white, size: 28),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Intelligence Artificielle',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                      const SizedBox(height: 3),
                      Text(
                        isSubscribed
                            ? 'Fonctionnalité en bêta · $_usedThisMonth/$_quota utilisations ce mois'
                            : 'Réservé aux abonnés',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Text(
              'Fonctionnalité en bêta · Offerte aux abonnés · Non garantie au-delà de la période bêta',
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                  fontStyle: FontStyle.italic),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          // Feature 1 — Vocal
          _FeatureTile(
            icon: Icons.mic_outlined,
            title: 'Rapport vocal',
            description:
                'Dictez votre intervention à voix haute. L\'IA remplit automatiquement le formulaire.',
            onTap: _openVoiceSheet,
            locked: !isSubscribed,
            onLocked: _showPaywall,
          ),
          const SizedBox(height: 12),
          // Feature 2 — Photo
          _FeatureTile(
            icon: Icons.camera_alt_outlined,
            title: 'Rapport depuis photo',
            description:
                'Photographiez un rapport papier ou un écran — l\'IA extrait toutes les informations.',
            onTap: _openImageSheet,
            locked: !isSubscribed,
            onLocked: _showPaywall,
          ),
          const SizedBox(height: 12),
          // Feature 3 — Improve
          _FeatureTile(
            icon: Icons.auto_fix_high_outlined,
            title: 'Améliorer un rapport',
            description:
                'Sélectionnez un rapport existant — l\'IA crée un duplicata corrigé et professionnel.',
            onTap: _openImproveSheet,
            locked: !isSubscribed,
            onLocked: _showPaywall,
          ),
          const SizedBox(height: 12),
          // Feature 4 — Document
          _FeatureTile(
            icon: Icons.description_outlined,
            title: 'Rapport depuis document',
            description:
                'Importez un fichier TXT ou PDF — l\'IA extrait les informations du document.',
            onTap: _openDocumentSheet,
            locked: !isSubscribed,
            onLocked: _showPaywall,
          ),
        ],
      ),
    );
  }
}

// ─── Feature tile ─────────────────────────────────────────────────────────────

class _FeatureTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;
  final bool locked;
  final VoidCallback onLocked;

  const _FeatureTile({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    required this.locked,
    required this.onLocked,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: locked ? onLocked : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  locked ? Icons.lock_outline : icon,
                  color: locked
                      ? Colors.grey.shade400
                      : AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: locked
                                ? Colors.grey.shade400
                                : null)),
                    const SizedBox(height: 4),
                    Text(description,
                        style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                            height: 1.4)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: locked
                      ? Colors.grey.shade300
                      : Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Voice sheet ──────────────────────────────────────────────────────────────

class _VoiceSheet extends StatefulWidget {
  final String? companyId;
  const _VoiceSheet({this.companyId});
  @override
  State<_VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends State<_VoiceSheet> {
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  final _noteController = TextEditingController();
  bool _recording = false;
  bool _loading = false;
  bool _playing = false;
  String? _recordedPath;
  Duration _elapsed = Duration.zero;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playing = state == PlayerState.playing);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    _player.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_recordedPath == null) return;
    if (_playing) {
      await _player.stop();
    } else {
      await _player.play(DeviceFileSource(_recordedPath!));
    }
  }

  Future<void> _toggleRecord() async {
    if (_recording) {
      _timer?.cancel();
      final path = await _recorder.stop();
      setState(() { _recording = false; _recordedPath = path; });
    } else {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permission microphone refusée')),
          );
        }
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/ai_record_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
      setState(() {
        _recording = true;
        _elapsed = Duration.zero;
        _recordedPath = null;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
      });
    }
  }

  Future<void> _analyse() async {
    if (_recordedPath == null || _loading) return;
    setState(() => _loading = true);
    try {
      final bytes = await File(_recordedPath!).readAsBytes();
      final b64 = base64Encode(bytes);
      final result = await AiService().audioToReport(
        audioB64: b64,
        audioMime: 'audio/aac',
        companyId: widget.companyId,
        note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
      );
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted) Navigator.pop(context, AiActionResult(error: 'network_error: $e'));
    }
  }

  String _fmt(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 20, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _SheetHandle(),
            const SizedBox(height: 16),
            const Text('Rapport vocal',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 8),
            Text(
              'Appuyez sur le micro et décrivez votre intervention : client, équipement, travaux réalisés.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 28),
            GestureDetector(
              onTap: _loading ? null : _toggleRecord,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _recording ? Colors.red.shade400 : AppColors.primary,
                  boxShadow: _recording
                      ? [BoxShadow(color: Colors.red.shade200, blurRadius: 20, spreadRadius: 4)]
                      : [],
                ),
                child: Icon(
                  _recording ? Icons.stop : Icons.mic,
                  color: Colors.white,
                  size: 36,
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_recording)
              Text(_fmt(_elapsed),
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade400))
            else if (_recordedPath != null)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Enregistrement prêt · ${_fmt(_elapsed)}',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _loading ? null : _togglePlay,
                    child: Icon(
                      _playing ? Icons.stop_circle_outlined : Icons.play_circle_outline,
                      size: 26,
                      color: _loading ? Colors.grey.shade300 : AppColors.primary,
                    ),
                  ),
                ],
              )
            else
              Text('Appuyez pour enregistrer',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
            const SizedBox(height: 20),
            TextField(
              controller: _noteController,
              enabled: !_loading,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Note complémentaire (optionnelle) — ex : "le client s\'appelle Dupont"',
                hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            if (_recordedPath != null && !_recording)
              FilledButton.icon(
                onPressed: _loading ? null : _analyse,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.auto_awesome, size: 18),
                label: Text(_loading ? 'Analyse en cours…' : 'Analyser l\'enregistrement'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Image sheet ──────────────────────────────────────────────────────────────

class _ImageSheet extends StatefulWidget {
  final String? companyId;
  const _ImageSheet({this.companyId});
  @override
  State<_ImageSheet> createState() => _ImageSheetState();
}

class _ImageSheetState extends State<_ImageSheet> {
  XFile? _image;
  bool _loading = false;
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
        source: source, imageQuality: 85, maxWidth: 1600);
    if (picked != null && mounted) setState(() => _image = picked);
  }

  Future<void> _analyse() async {
    if (_image == null || _loading) return;
    setState(() => _loading = true);
    try {
      final bytes = await _image!.readAsBytes();
      final b64 = base64Encode(bytes);
      final mime = _image!.name.toLowerCase().endsWith('.png')
          ? 'image/png'
          : 'image/jpeg';
      final result = await AiService().imageToReport(
        imageB64: b64,
        imageMime: mime,
        companyId: widget.companyId,
        note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
      );
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted) Navigator.pop(context, AiActionResult(error: 'network_error: $e'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 20, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _SheetHandle(),
          const SizedBox(height: 16),
          const Text('Rapport depuis photo',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 8),
          Text(
            'Photographiez un rapport papier ou un formulaire manuscrit — l\'IA extrait les informations.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
          const SizedBox(height: 24),
          if (_image != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                File(_image!.path),
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            )
          else
            Container(
              height: 120,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_photo_alternate_outlined,
                        size: 36, color: Colors.grey.shade400),
                    const SizedBox(height: 6),
                    Text('Aucune image sélectionnée',
                        style: TextStyle(
                            color: Colors.grey.shade400, fontSize: 12)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_outlined, size: 18),
                  label: const Text('Appareil photo'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('Galerie'),
                ),
              ),
            ],
          ),
          if (_image != null) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              enabled: !_loading,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Note complémentaire (optionnelle) — ex : "le n° de série est illisible, c\'est 12345"',
                hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loading ? null : _analyse,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_awesome, size: 18),
              label: Text(_loading ? 'Analyse en cours…' : 'Analyser l\'image'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Improve sheet ────────────────────────────────────────────────────────────

class _ImproveOutcome {
  final AiActionResult? aiResult;
  final String? newReportId;
  final String? error;
  const _ImproveOutcome({this.aiResult, this.newReportId, this.error});
}

class _ImproveSheet extends StatefulWidget {
  final String? companyId;
  const _ImproveSheet({this.companyId});
  @override
  State<_ImproveSheet> createState() => _ImproveSheetState();
}

class _ImproveSheetState extends State<_ImproveSheet> {
  List<ReportModel>? _reports;
  ReportModel? _selected;
  bool _loading = false;
  final _noteController = TextEditingController();
  // Audio note
  final _audioRecorder = AudioRecorder();
  bool _recordingNote = false;
  String? _noteAudioPath;
  Duration _noteElapsed = Duration.zero;
  Timer? _noteTimer;

  @override
  void initState() {
    super.initState();
    LocalDbService().getAllReports().then((r) {
      if (mounted) setState(() => _reports = r);
    });
  }

  @override
  void dispose() {
    _noteController.dispose();
    _noteTimer?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<void> _toggleNoteAudio() async {
    if (_recordingNote) {
      _noteTimer?.cancel();
      final path = await _audioRecorder.stop();
      setState(() { _recordingNote = false; _noteAudioPath = path; });
    } else {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) return;
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/ai_note_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _audioRecorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
      setState(() { _recordingNote = true; _noteElapsed = Duration.zero; _noteAudioPath = null; });
      _noteTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _noteElapsed += const Duration(seconds: 1));
      });
    }
  }

  String _fmt(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';


  Future<void> _improve() async {
    if (_selected == null || _loading) return;
    setState(() => _loading = true);

    final fields = <String, String>{
      'client_name': _selected!.clientName,
      'client_address': _selected!.clientAddress,
      'client_phone': _selected!.clientPhone,
      'client_contact': _selected!.clientContact,
      'contract_number': _selected!.contractNumber,
      'intervention_type': _selected!.interventionType,
      'date': _selected!.date.day.toString().padLeft(2,'0') +
          '/' + _selected!.date.month.toString().padLeft(2,'0') +
          '/' + _selected!.date.year.toString(),
      'description': _selected!.description,
      'observations': _selected!.observations,
      'equipment_type': _selected!.equipmentType,
      'equipment_brand': _selected!.equipmentBrand,
      'equipment_model': _selected!.equipmentModel,
      'equipment_serial': _selected!.equipmentSerial,
      'start_time': _selected!.startTime != null
          ? '${_selected!.startTime!.hour.toString().padLeft(2,'0')}:${_selected!.startTime!.minute.toString().padLeft(2,'0')}'
          : '',
      'end_time': _selected!.endTime != null
          ? '${_selected!.endTime!.hour.toString().padLeft(2,'0')}:${_selected!.endTime!.minute.toString().padLeft(2,'0')}'
          : '',
      'labor_hours': _selected!.laborHours?.toString() ?? '',
    };

    String? noteAudioB64;
    if (_noteAudioPath != null) {
      try {
        final bytes = await File(_noteAudioPath!).readAsBytes();
        noteAudioB64 = base64Encode(bytes);
      } catch (_) {}
    }

    final result = await AiService().improveReport(
      fields: fields,
      companyId: widget.companyId,
      note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
      noteAudioB64: noteAudioB64,
      noteAudioMime: noteAudioB64 != null ? 'audio/aac' : null,
    );

    if (result.needsSubscription || !result.isSuccess) {
      if (mounted) Navigator.pop(context, _ImproveOutcome(error: result.error));
      return;
    }

    // Create a duplicate with AI improvements applied
    final f = result.fields;
    final now = DateTime.now().toIso8601String();
    final map = _selected!.toMap();
    map['id'] = const Uuid().v4();
    map['created_at'] = now;
    map['updated_at'] = now;
    map['status'] = 'draft';
    map['report_number'] = 0;
    map['cloud_url'] = null;
    map['pdf_local_path'] = null;
    map['signature_client_data'] = null;
    map['signature_tech_data'] = null;
    map['signature_client_start_data'] = null;
    map['signature_tech_start_data'] = null;
    map['ai_enhanced'] = 1;
    if (f['client_name']?.isNotEmpty == true) map['client_name'] = f['client_name'];
    if (f['client_address']?.isNotEmpty == true) map['client_address'] = f['client_address'];
    if (f['client_phone']?.isNotEmpty == true) map['client_phone'] = f['client_phone'];
    if (f['intervention_type']?.isNotEmpty == true) map['intervention_type'] = f['intervention_type'];
    if (f['description']?.isNotEmpty == true) map['description'] = f['description'];
    if (f['observations']?.isNotEmpty == true) map['observations'] = f['observations'];
    if (f['equipment_type']?.isNotEmpty == true) map['equipment_type'] = f['equipment_type'];
    if (f['equipment_brand']?.isNotEmpty == true) map['equipment_brand'] = f['equipment_brand'];
    if (f['equipment_model']?.isNotEmpty == true) map['equipment_model'] = f['equipment_model'];
    if (f['equipment_serial']?.isNotEmpty == true) map['equipment_serial'] = f['equipment_serial'];
    final newReport = ReportModel.fromMap(map);

    await LocalDbService().insertReport(newReport);
    if (mounted) {
      Navigator.pop(
          context, _ImproveOutcome(aiResult: result, newReportId: newReport.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 20, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _SheetHandle(),
          const SizedBox(height: 16),
          const Text('Améliorer un rapport',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 8),
          Text(
            'Choisissez un rapport. L\'IA crée un duplicata avec le texte corrigé et professionnel.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
          const SizedBox(height: 20),
          if (_reports == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: CircularProgressIndicator(),
            )
          else if (_reports!.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text('Aucun rapport disponible.',
                  style: TextStyle(color: Colors.grey.shade500)),
            )
          else ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _reports!.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final r = _reports![i];
                  final isSelected = _selected?.id == r.id;
                  return ListTile(
                    leading: Icon(
                      isSelected
                          ? Icons.check_circle
                          : Icons.assignment_outlined,
                      color: isSelected ? AppColors.primary : Colors.grey,
                    ),
                    title: Text(
                      r.clientName.isEmpty ? 'Client non renseigné' : r.clientName,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal),
                    ),
                    subtitle: Text(
                      r.interventionType.isNotEmpty
                          ? r.interventionType
                          : 'Sans type',
                      style: const TextStyle(fontSize: 12),
                    ),
                    onTap: () => setState(() => _selected = r),
                    selected: isSelected,
                    selectedTileColor:
                        AppColors.primary.withValues(alpha: 0.06),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            // Text note
            TextField(
              controller: _noteController,
              enabled: !_loading,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Instruction prioritaire (optionnelle) — ex : "ne touche pas la description de la panne"',
                hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            // Audio note
            Row(
              children: [
                GestureDetector(
                  onTap: _loading ? null : _toggleNoteAudio,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _recordingNote
                          ? Colors.red.shade50
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _recordingNote
                            ? Colors.red.shade300
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _recordingNote ? Icons.stop : Icons.mic_outlined,
                          size: 16,
                          color: _recordingNote
                              ? Colors.red.shade600
                              : Colors.grey.shade600,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _recordingNote
                              ? _fmt(_noteElapsed)
                              : _noteAudioPath != null
                                  ? 'Note audio · ${_fmt(_noteElapsed)}'
                                  : 'Note audio',
                          style: TextStyle(
                              fontSize: 12,
                              color: _recordingNote
                                  ? Colors.red.shade600
                                  : Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_noteAudioPath != null && !_recordingNote) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(() => _noteAudioPath = null),
                    child: Icon(Icons.close, size: 16, color: Colors.grey.shade500),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: (_selected == null || _loading) ? null : _improve,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_fix_high, size: 18),
              label: Text(_loading
                  ? 'Amélioration en cours…'
                  : _selected == null
                      ? 'Sélectionnez un rapport'
                      : 'Améliorer ce rapport'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Fields preview sheet ─────────────────────────────────────────────────────

class _FieldsPreviewSheet extends StatelessWidget {
  final Map<String, String> fields;
  final VoidCallback onCreateReport;

  const _FieldsPreviewSheet(
      {required this.fields, required this.onCreateReport});

  static const _labels = {
    'client_name': 'Client',
    'client_address': 'Adresse',
    'client_phone': 'Téléphone',
    'client_contact': 'Contact sur place',
    'contract_number': 'N° de contrat / référence',
    'intervention_type': 'Type d\'intervention',
    'date': 'Date',
    'description': 'Description',
    'observations': 'Observations',
    'equipment_type': 'Type d\'équipement',
    'equipment_brand': 'Marque',
    'equipment_model': 'Modèle',
    'equipment_serial': 'N° de série',
    'start_time': 'Heure de début',
    'end_time': 'Heure de fin',
    'labor_hours': 'Heures travaillées',
  };

  @override
  Widget build(BuildContext context) {
    final filled = fields.entries
        .where((e) => e.value.trim().isNotEmpty)
        .toList();

    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 20, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SheetHandle(),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.auto_awesome, color: Colors.amber.shade600, size: 20),
              const SizedBox(width: 8),
              const Text('Informations extraites',
                  style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${filled.length} champ${filled.length > 1 ? 's' : ''} rempli${filled.length > 1 ? 's' : ''}',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: filled.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: Colors.grey.shade100),
              itemBuilder: (ctx, i) {
                final e = filled[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_labels[e.key] ?? e.key,
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                              fontWeight: FontWeight.w500)),
                      const SizedBox(height: 2),
                      Text(e.value,
                          style: const TextStyle(fontSize: 14)),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onCreateReport,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Créer ce rapport'),
            style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48)),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
        ],
      ),
    );
  }
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2)),
        ),
      );
}

// ─── Document import sheet ────────────────────────────────────────────────────

class _DocumentSheet extends StatefulWidget {
  final String? companyId;
  const _DocumentSheet({this.companyId});

  @override
  State<_DocumentSheet> createState() => _DocumentSheetState();
}

class _DocumentSheetState extends State<_DocumentSheet> {
  bool _loading = false;
  String? _fileName;
  String? _error;

  Future<void> _pickAndSend() async {
    if (_loading) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;

    setState(() { _loading = true; _fileName = file.name; _error = null; });

    try {
      AiActionResult aiResult;
      final ext = file.extension?.toLowerCase() ?? '';

      if (ext == 'txt') {
        final text = const Utf8Decoder(allowMalformed: true).convert(file.bytes!);
        aiResult = await AiService().documentToReport(
          content: text,
          contentType: 'text',
          companyId: widget.companyId,
        );
      } else if (ext == 'pdf') {
        final b64 = base64Encode(file.bytes!);
        aiResult = await AiService().documentToReport(
          content: b64,
          contentType: 'pdf_b64',
          companyId: widget.companyId,
        );
      } else {
        setState(() { _loading = false; _error = 'Format non supporté.'; });
        return;
      }

      if (!mounted) return;
      Navigator.pop(context, aiResult);
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = 'Erreur : $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          left: 20, right: 20, top: 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const _SheetHandle(),
        const SizedBox(height: 16),
        const Text('Rapport depuis document',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 8),
        const Text(
          'Importez un fichier TXT ou PDF décrivant l\'intervention. L\'IA ne doit pas inventer — seul le contenu du document est utilisé.',
          style: TextStyle(fontSize: 13, color: Colors.black54),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        if (_loading) ...[
          const CircularProgressIndicator(),
          const SizedBox(height: 10),
          Text('Analyse de "$_fileName" en cours…',
              style: const TextStyle(fontSize: 13, color: Colors.black54)),
        ] else ...[
          if (_fileName != null) ...[
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.description_outlined, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Flexible(child: Text(_fileName!, style: const TextStyle(fontSize: 13))),
            ]),
            const SizedBox(height: 10),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
            ),
          FilledButton.icon(
            onPressed: _pickAndSend,
            icon: const Icon(Icons.upload_file_outlined, size: 18),
            label: const Text('Sélectionner un fichier (TXT, PDF)'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
          const SizedBox(height: 8),
          const Text(
            'Formats supportés : .txt, .pdf\nFichier max recommandé : 10 pages / 50 Ko',
            style: TextStyle(fontSize: 11, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 8),
      ]),
    );
  }
}
