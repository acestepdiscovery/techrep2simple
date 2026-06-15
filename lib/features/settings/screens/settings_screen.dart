import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/config/app_build.dart';
import '../../../shared/services/local_db_service.dart';
import '../../../shared/services/pdf_service.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/services/google_drive_service.dart';
import '../../../shared/services/dropbox_service.dart';
import '../../../shared/services/onedrive_service.dart';
import '../../referral/providers/referral_provider.dart';
import '../../../shared/services/subscription_service.dart';
import '../../../shared/services/identity_audit_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../reports/providers/debug_nav_providers.dart';
import '../../subscription/subscription_provider.dart';
import '../../subscription/paywall_bottom_sheet.dart';
import '../providers/settings_provider.dart';

// (K) Demande de déroulé de la tuile « Mon entreprise » des Réglages (depuis le
// toggle d'identité d'un rapport). Le nonce force le déroulé même si l'écran
// Réglages est déjà construit (onglet gardé vivant).
final settingsExpandCompanyProvider = StateProvider<int?>((ref) => null);

// Ouvre une page légale (Confidentialité / CGU). Si l'URL n'est pas encore
// renseignée (kPrivacyPolicyUrl / kTermsUrl vides dans app_build), on affiche un
// message plutôt qu'un lien mort.
Future<void> _openLegal(BuildContext context, String url) async {
  if (url.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Page bientôt disponible.')),
    );
    return;
  }
  final ok = await launchUrl(Uri.parse(url),
      mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Impossible d'ouvrir le lien.")),
    );
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: settings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (s) => ListView(
          children: [
            const _AccountCard(),
            const _CompanySection(),
            // (#12) Pointeur « Réglages de l'équipe » retiré d'ici : la mention
            // « Votre équipe … se gère dans l'onglet Équipe » est déjà présente
            // dans la section Compte ci-dessous (tuile « Mon profil »).
            // (Q) Pointeur vers les réglages d'ÉQUIPE (si on est en équipe).
            // const _TeamSettingsPointer(),

            // (B) Remontés juste sous « Mon entreprise » : Compte, Abonnement, Parrainage.
            _SectionTitle('Compte'),
            const _TeamSection(),

            // (D-opt1) L'abonnement pro PERSONNEL est désormais dans « Mon compte ».
            _SectionTitle('Abonnement (solo)'),
            ListTile(
              leading: const Icon(Icons.workspace_premium_outlined,
                  color: AppColors.primary),
              title: const Text('Abonnement pro personnel'),
              subtitle: const Text(
                  'Se gère dans « Mon compte ». Appuyez pour voir les offres.',
                  style: TextStyle(fontSize: 12)),
              trailing:
                  const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
              // (I) Ouvre le paywall ; en le fermant on se retrouve sur Mon compte.
              onTap: () {
                context.go('/profile');
                PaywallBottomSheet.show(context);
              },
            ),

            if (kParrainageEnabled) ...[
              _SectionTitle('Parrainage'),
              const _ParrainageSection(),
            ],

            // (B) Sections techniques REPLIÉES derrière une seule tuile chacune.
            _CollapsibleSettingsTile(
              icon: Icons.picture_as_pdf_outlined,
              title: 'RAPPORTS PDF',
              subtitle: 'Gabarit, numérotation',
              children: [
                _TemplateTile(
                  current: s['pdf_template'] ?? 'professionnel',
                  onSave: (v) =>
                      ref.read(settingsProvider.notifier).set('pdf_template', v),
                ),
                _NumberFormatTile(
                  current: s['report_number_format'] ?? '{num}',
                  onSave: (v) => ref
                      .read(settingsProvider.notifier)
                      .set('report_number_format', v),
                ),
                _NumberStartTile(
                  current: s['report_number_start'] ?? '1',
                  onSave: (v) => ref
                      .read(settingsProvider.notifier)
                      .set('report_number_start', v),
                ),
              ],
            ),
            _CollapsibleSettingsTile(
              icon: Icons.cloud_upload_outlined,
              title: 'INTÉGRATION CLOUD',
              subtitle: 'Envoi auto, dossier de destination',
              children: [
                const _CloudIntegrationsEntry(),
                _FolderPatternTile(
                  current: s['drive_folder_pattern'] ?? '',
                  onSave: (v) => ref
                      .read(settingsProvider.notifier)
                      .set('drive_folder_pattern', v),
                ),
              ],
            ),

            _SectionTitle('Feedback & support'),
            const _FeedbackSection(),

            _SectionTitle('À propos'),
            const _VersionTile(),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Politique de confidentialité'),
              trailing: const Icon(Icons.open_in_new,
                  size: 16, color: Colors.grey),
              onTap: () => _openLegal(context, kPrivacyPolicyUrl),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text("Conditions d'utilisation (CGU/CGV)"),
              trailing: const Icon(Icons.open_in_new,
                  size: 16, color: Colors.grey),
              onTap: () => _openLegal(context, kTermsUrl),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Suppression des données'),
              trailing: const Icon(Icons.open_in_new,
                  size: 16, color: Colors.grey),
              onTap: () => _openLegal(context, kDataDeletionUrl),
            ),
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('Aide & support'),
              trailing: const Icon(Icons.open_in_new,
                  size: 16, color: Colors.grey),
              onTap: () => _openLegal(context, kSupportUrl),
            ),

            // (B) Faire connaître l'appli — tout en bas.
            const _ShareAppTile(),

            if (kDebugMode && kEnableDebugSection) ...[
              _SectionTitle('🔧 Debug (build debug uniquement)'),
              const _DevSection(),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ─── (B) Section repliable générique (Rapports PDF, Cloud…) ───────────────────
class _CollapsibleSettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final List<Widget> children;
  const _CollapsibleSettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ExpansionTile(
              leading: Icon(icon, color: AppColors.primary),
              title: Text(title,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                      letterSpacing: 1)),
              subtitle: subtitle != null
                  ? Text(subtitle!, style: const TextStyle(fontSize: 11))
                  : null,
              shape: const Border(),
              collapsedShape: const Border(),
              childrenPadding: const EdgeInsets.only(bottom: 8),
              children: children,
            ),
          ),
        ),
      );
}

// ─── (Q) Pointeur vers les réglages d'ÉQUIPE (si en équipe) ───────────────────
// (#12) Conservé (non supprimé) mais plus utilisé : la mention équipe vit
// désormais dans la section Compte. `ignore` pour éviter le warning unused.
// ignore: unused_element
class _TeamSettingsPointer extends ConsumerWidget {
  const _TeamSettingsPointer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasTeam = ref.watch(teamStateProvider).valueOrNull?.hasTeam ?? false;
    if (!hasTeam) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
      child: Material(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.go('/team-tab'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Icon(Icons.groups_outlined, color: AppColors.primary, size: 22),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Réglages de l\'équipe',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary)),
                    SizedBox(height: 2),
                    Text(
                      'Le nom et les infos de l\'ÉQUIPE (affichés sur les rapports '
                      'd\'équipe et synchronisés avec tous vos techniciens) se '
                      'modifient là-bas. Les réglages ci-dessous sont vos infos SOLO.',
                      style: TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─── (B) Faire connaître l'appli ──────────────────────────────────────────────
class _ShareAppTile extends StatelessWidget {
  const _ShareAppTile();
  static const _shareText =
      'J\'utilise "Rapport Technique IA" pour mes bons d\'intervention — '
      'rapide, professionnel, PDF en un clic. Disponible sur iOS et Android. '
      'À tester absolument !';

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
        child: Material(
          color: AppColors.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Share.share(_shareText),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Icon(Icons.favorite_outline, color: AppColors.primary, size: 22),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Faire connaître l\'appli',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      SizedBox(height: 2),
                      Text('À vos collègues, votre chef, d\'autres entreprises…',
                          style: TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
                const Icon(Icons.share_outlined, size: 18, color: Colors.grey),
              ]),
            ),
          ),
        ),
      );
}

// ─── Editable setting tile ───────────────────────────────────────────────────

class _EditableTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String hint;
  final Future<void> Function(String) onSave;

  const _EditableTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.hint,
    required this.onSave,
  });

  void _edit(BuildContext context) {
    final ctrl = TextEditingController(text: value);
    showDialog(
      context: context,
      builder: (dlg) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(hintText: hint),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dlg),
              child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () async {
              await onSave(ctrl.text.trim());
              if (dlg.mounted) Navigator.pop(dlg);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(label),
        subtitle: Text(
          value.isEmpty ? 'Appuyer pour définir' : value,
          style: TextStyle(
            color: value.isEmpty ? Colors.grey : Colors.black87,
            fontStyle:
                value.isEmpty ? FontStyle.italic : FontStyle.normal,
          ),
        ),
        trailing: const Icon(Icons.edit_outlined, size: 18, color: Colors.grey),
        onTap: () => _edit(context),
      );
}

// ─── Entrée compacte cloud → ouvre les 3 services dans un dialogue ────────────

class _CloudIntegrationsEntry extends StatelessWidget {
  const _CloudIntegrationsEntry();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.cloud_upload_outlined, color: AppColors.primary),
      title: const Text('Envoi automatique vers le cloud'),
      subtitle: Row(children: [
        const Icon(Icons.add_to_drive, size: 16, color: Color(0xFF1FA463)),   // Google Drive vert
        const SizedBox(width: 5),
        const Icon(Icons.cloud, size: 16, color: Color(0xFF0078D4)),          // OneDrive bleu
        const SizedBox(width: 5),
        const Icon(Icons.folder, size: 16, color: Color(0xFF0061FF)),         // Dropbox bleu
        const SizedBox(width: 6),
        Expanded(
          child: Text('Google Drive · OneDrive · Dropbox',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ),
      ]),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => showDialog(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('Intégrations cloud'),
          contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
          content: const SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _GoogleDriveTile(),
                _OneDriveTile(),
                _DropboxTile(),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Fermer')),
          ],
        ),
      ),
    );
  }
}

// ─── Google Drive tile (OAuth — no API key needed) ───────────────────────────

class _GoogleDriveTile extends StatefulWidget {
  const _GoogleDriveTile();

  @override
  State<_GoogleDriveTile> createState() => _GoogleDriveTileState();
}

class _GoogleDriveTileState extends State<_GoogleDriveTile> {
  String? _email;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final email = await GoogleDriveService.currentEmail;
    if (mounted) setState(() { _email = email; _loading = false; });
  }

  Future<void> _disconnect() async {
    await GoogleDriveService.signOut();
    if (mounted) setState(() { _email = null; });
  }

  void _showDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Row(children: [
          Icon(Icons.add_to_drive, color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          const Text('Google Drive'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_email != null) ...[
              const Text('Compte connecté :', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(_email!, style: const TextStyle(color: Colors.green)),
              const SizedBox(height: 12),
              const Text(
                'Les PDF sont envoyés dans le dossier "Rapport Technique" de ce compte Drive.',
                style: TextStyle(fontSize: 12),
              ),
            ] else ...[
              const Text(
                'La connexion à Google Drive se fait automatiquement lors du premier envoi.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              const Text(
                'Un sélecteur de compte Google s\'ouvrira et demandera l\'autorisation d\'accès au Drive.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ],
        ),
        actions: [
          if (_email != null)
            TextButton(
              onPressed: () async {
                await _disconnect();
                if (dialogCtx.mounted) Navigator.pop(dialogCtx);
              },
              child: const Text('Se déconnecter', style: TextStyle(color: Colors.red)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ListTile(
        leading: Icon(Icons.add_to_drive),
        title: Text('Google Drive'),
        trailing: SizedBox(
          width: 16, height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final connected = _email != null;
    return ListTile(
      leading: Icon(Icons.add_to_drive,
          color: connected ? Colors.green : AppColors.primary),
      title: const Text('Google Drive'),
      subtitle: Text(
        connected ? 'Connecté : $_email' : 'Connexion auto au premier envoi',
        style: TextStyle(
          color: connected ? Colors.green : Colors.grey,
          fontSize: 12,
        ),
      ),
      trailing: Icon(
        connected ? Icons.check_circle : Icons.info_outline,
        color: connected ? Colors.green : Colors.grey,
        size: 20,
      ),
      onTap: () => _showDialog(context),
    );
  }
}

// ─── Dropbox tile (OAuth — app key hardcoded in service) ─────────────────────

class _DropboxTile extends StatefulWidget {
  const _DropboxTile();

  @override
  State<_DropboxTile> createState() => _DropboxTileState();
}

class _DropboxTileState extends State<_DropboxTile> {
  String? _name;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var name = await DropboxService.displayName;
    if (name == null && await DropboxService.isConnected) {
      name = 'Compte Dropbox';
    }
    if (mounted) setState(() { _name = name; _loading = false; });
  }

  Future<void> _disconnect() async {
    await DropboxService.signOut();
    if (mounted) setState(() { _name = null; });
  }

  void _showDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Row(children: [
          Icon(Icons.folder_outlined, color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          const Text('Dropbox'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_name != null) ...[
              const Text('Compte connecté :', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(_name!, style: const TextStyle(color: Colors.green)),
              const SizedBox(height: 12),
              const Text(
                'Les PDF sont envoyés dans le dossier "Rapport Technique" de ce compte Dropbox.',
                style: TextStyle(fontSize: 12),
              ),
            ] else ...[
              const Text(
                'La connexion à Dropbox se fait automatiquement lors du premier envoi.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              const Text(
                'Le navigateur s\'ouvrira pour vous connecter à votre compte Dropbox.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ],
        ),
        actions: [
          if (_name != null)
            TextButton(
              onPressed: () async {
                await _disconnect();
                if (dialogCtx.mounted) Navigator.pop(dialogCtx);
              },
              child: const Text('Se déconnecter', style: TextStyle(color: Colors.red)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ListTile(
        leading: Icon(Icons.folder_outlined),
        title: Text('Dropbox'),
        trailing: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final connected = _name != null;
    return ListTile(
      leading: Icon(Icons.folder_outlined,
          color: connected ? Colors.green : AppColors.primary),
      title: const Text('Dropbox'),
      subtitle: Text(
        connected ? 'Connecté : $_name' : 'Connexion auto au premier envoi',
        style: TextStyle(color: connected ? Colors.green : Colors.grey, fontSize: 12),
      ),
      trailing: Icon(
        connected ? Icons.check_circle : Icons.info_outline,
        color: connected ? Colors.green : Colors.grey,
        size: 20,
      ),
      onTap: () => _showDialog(context),
    );
  }
}

// ─── OneDrive tile (OAuth — client ID hardcoded in service) ──────────────────

class _OneDriveTile extends StatefulWidget {
  const _OneDriveTile();

  @override
  State<_OneDriveTile> createState() => _OneDriveTileState();
}

class _OneDriveTileState extends State<_OneDriveTile> {
  String? _name;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var name = await OneDriveService.displayName;
    if (name == null && await OneDriveService.isConnected) {
      name = 'Compte Microsoft';
    }
    if (mounted) setState(() { _name = name; _loading = false; });
  }

  Future<void> _disconnect() async {
    await OneDriveService.signOut();
    if (mounted) setState(() { _name = null; });
  }

  void _showDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Row(children: [
          Icon(Icons.cloud_outlined, color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          const Text('OneDrive'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_name != null) ...[
              const Text('Compte connecté :', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(_name!, style: const TextStyle(color: Colors.green)),
              const SizedBox(height: 12),
              const Text(
                'Les PDF sont envoyés dans le dossier "Rapport Technique" de ce compte OneDrive.',
                style: TextStyle(fontSize: 12),
              ),
            ] else ...[
              const Text(
                'La connexion à OneDrive se fait automatiquement lors du premier envoi.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              const Text(
                'Le navigateur s\'ouvrira pour vous connecter à votre compte Microsoft.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ],
        ),
        actions: [
          if (_name != null)
            TextButton(
              onPressed: () async {
                await _disconnect();
                if (dialogCtx.mounted) Navigator.pop(dialogCtx);
              },
              child: const Text('Se déconnecter', style: TextStyle(color: Colors.red)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ListTile(
        leading: Icon(Icons.cloud_outlined),
        title: Text('OneDrive (Microsoft)'),
        trailing: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final connected = _name != null;
    return ListTile(
      leading: Icon(Icons.cloud_outlined,
          color: connected ? Colors.green : AppColors.primary),
      title: const Text('OneDrive (Microsoft)'),
      subtitle: Text(
        connected ? 'Connecté : $_name' : 'Connexion auto au premier envoi',
        style: TextStyle(color: connected ? Colors.green : Colors.grey, fontSize: 12),
      ),
      trailing: Icon(
        connected ? Icons.check_circle : Icons.info_outline,
        color: connected ? Colors.green : Colors.grey,
        size: 20,
      ),
      onTap: () => _showDialog(context),
    );
  }
}

// ─── Number format tile ──────────────────────────────────────────────────────

class _NumberFormatTile extends StatefulWidget {
  final String current;
  final Future<void> Function(String) onSave;
  const _NumberFormatTile({required this.current, required this.onSave});

  @override
  State<_NumberFormatTile> createState() => _NumberFormatTileState();
}

class _NumberFormatTileState extends State<_NumberFormatTile> {
  static const _presets = [
    ('{num}', 'Simple', '001'),
    ('{year}-{num}', 'Annuel', '2026-001'),
    ('{year}/{num}', 'Année/Numéro', '2026/001'),
    ('{company}/{year}/{month}/{day}/{num}', 'Société/Date', 'AMARIS/2026/04/23/001'),
    ('{client}-{num}', 'Client-Numéro', 'DUPONT-001'),
    ('{client}/{year}/{month}/{day}/{num}', 'Client/Date', 'DUPONT/2026/05/18/001'),
  ];

  void _showDialog(BuildContext context) {
    String selected = widget.current;
    final isCustom = !_presets.any((p) => p.$1 == widget.current);
    final customCtrl = TextEditingController(text: isCustom ? widget.current : '');
    bool showCustom = isCustom;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Format du numéro de rapport'),
          content: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ..._presets.map((p) {
                      final (value, label, example) = p;
                      return ChoiceChip(
                        label: Text(label, style: const TextStyle(fontSize: 12)),
                        selected: !showCustom && selected == value,
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Ex : $example',
                        onSelected: (_) => setS(() { selected = value; showCustom = false; }),
                      );
                    }),
                    ChoiceChip(
                      label: const Text('Personnalisé', style: TextStyle(fontSize: 12)),
                      selected: showCustom,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setS(() => showCustom = true),
                    ),
                  ],
                ),
                if (!showCustom) ...[
                  const SizedBox(height: 6),
                  Text('Ex : ${PdfService.resolveReportNumber(1, selected, clientName: 'Dupont', date: DateTime.now(), technicianName: 'Jean Dupont', companyName: 'MonEntreprise')}',
                      style: const TextStyle(fontSize: 11, color: Colors.blue)),
                ],
                if (showCustom) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: customCtrl,
                    decoration: const InputDecoration(
                      hintText: '{client}/{year}/{month}/{day}/{num}',
                      isDense: true,
                    ),
                    onChanged: (_) => setS(() {}),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final (token, label, isSep) in [
                        ('{num}', 'Numéro', false),
                        ('{client}', 'Client', false),
                        ('{company}', 'Société', false),
                        ('{year}', 'Année', false),
                        ('{month}', 'Mois', false),
                        ('{day}', 'Jour', false),
                        ('{tech}', 'Tech.', false),
                        ('/', '/', true),
                        ('-', '-', true),
                        ('_', '_', true),
                        (' ', '·espace', true),
                      ])
                        ActionChip(
                          label: Text(label,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: isSep ? Colors.grey.shade700 : null)),
                          avatar: Icon(
                              isSep ? Icons.add : Icons.add,
                              size: 14,
                              color: isSep ? Colors.grey : null),
                          backgroundColor: isSep ? Colors.grey.shade100 : null,
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            final sel = customCtrl.selection;
                            final text = customCtrl.text;
                            final pos = sel.isValid ? sel.baseOffset : text.length;
                            customCtrl.value = TextEditingValue(
                              text: text.substring(0, pos) + token + text.substring(pos),
                              selection: TextSelection.collapsed(offset: pos + token.length),
                            );
                            setS(() {});
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Aperçu : ${PdfService.resolveReportNumber(1, customCtrl.text.isEmpty ? '{num}' : customCtrl.text, clientName: 'Dupont', date: DateTime(2026, 5, 18), technicianName: 'Jean Dupont', companyName: 'MonEntreprise')}',
                    style: const TextStyle(fontSize: 11, color: Colors.blue),
                  ),
                ],
              ],
            ),
          ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () async {
                final value = showCustom
                    ? (customCtrl.text.trim().isEmpty ? '{num}' : customCtrl.text.trim())
                    : selected;
                await widget.onSave(value);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  String get _preview => PdfService.resolveReportNumber(
        1,
        widget.current,
        clientName: 'Dupont',
        date: DateTime.now(),
        technicianName: 'Jean Dupont',
        companyName: 'MonEntreprise',
      );

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.tag, color: AppColors.primary),
      title: const Text('Format du numéro de rapport'),
      subtitle: Text('Ex : $_preview',
          style: const TextStyle(fontSize: 12, color: Colors.black87)),
      trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
      onTap: () => _showDialog(context),
    );
  }
}

// ─── Number start tile ───────────────────────────────────────────────────────

class _NumberStartTile extends StatefulWidget {
  final String current;
  final Future<void> Function(String) onSave;
  const _NumberStartTile({required this.current, required this.onSave});

  @override
  State<_NumberStartTile> createState() => _NumberStartTileState();
}

class _NumberStartTileState extends State<_NumberStartTile> {
  int _currentMax = 0;

  @override
  void initState() {
    super.initState();
    LocalDbService().getMaxReportNumber().then((v) {
      if (mounted) setState(() => _currentMax = v);
    });
  }

  void _showDialog(BuildContext context) {
    final ctrl = TextEditingController(
        text: widget.current == '1' ? '' : widget.current);
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Numéro de départ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_currentMax > 0)
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Dernier rapport existant : $_currentMax\nProchain numéro : ${_currentMax + 1}',
                  style: TextStyle(fontSize: 12, color: Colors.blue.shade800),
                ),
              ),
            const Text(
              'Forcer le numéro minimum pour les nouveaux rapports.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'N° de départ minimum',
                hintText: '1',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ex : 8 si vous avez déjà 7 rapports papier à part.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () async {
              final v = int.tryParse(ctrl.text.trim()) ?? 1;
              await widget.onSave(v.toString());
              if (dialogCtx.mounted) Navigator.pop(dialogCtx);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final start = int.tryParse(widget.current) ?? 1;
    final next = _currentMax > 0
        ? 'Prochain : ${_currentMax + 1} (dernier existant : $_currentMax)'
        : start == 1
            ? 'Commence à 1 (par défaut)'
            : 'Minimum : $start';
    return ListTile(
      leading: const Icon(Icons.looks_one_outlined, color: AppColors.primary),
      title: const Text('Numéro de départ'),
      subtitle: Text(next,
          style: const TextStyle(fontSize: 12, color: Colors.black87)),
      trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
      onTap: () => _showDialog(context),
    );
  }
}

// ─── Folder pattern tile ─────────────────────────────────────────────────────

class _FolderPatternTile extends StatelessWidget {
  final String current;
  final Future<void> Function(String) onSave;
  const _FolderPatternTile({required this.current, required this.onSave});

  static const _tokens = [
    ('{société}', 'Société'),
    ('{technicien}', 'Technicien'),
    ('{année}', 'Année'),
    ('{mois}', 'Mois'),
    // (1.5) Séparateur de sous-dossier. Toujours « / » (chemin logique cloud,
    // pas d'antislash « \ » → aucun souci selon les versions de téléphone).
    ('/', '/ (sous-dossier)'),
  ];

  static const _presets = [
    ('Rapports techniques/{société}', 'Par société'),
    ('Rapports techniques/{année}/{mois}', 'Par date'),
    ('Rapports techniques/{société}/{année}', 'Société + année'),
    ('{société}/Rapports/{technicien}', 'Société → technicien'),
  ];

  void _insert(TextEditingController ctrl, String token, void Function(void Function()) setS) {
    final sel = ctrl.selection;
    final text = ctrl.text;
    final pos = sel.isValid ? sel.baseOffset : text.length;
    ctrl.value = TextEditingValue(
      text: text.substring(0, pos) + token + text.substring(pos),
      selection: TextSelection.collapsed(offset: pos + token.length),
    );
    setS(() {});
  }

  void _showDialog(BuildContext context) {
    final ctrl = TextEditingController(text: current);
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Dossier de destination des PDF'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Chemin du dossier dans votre cloud. Utilisez "/" pour créer des sous-dossiers.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: ctrl,
                  decoration: const InputDecoration(
                    hintText: 'Rapports techniques/{société}',
                    isDense: true,
                  ),
                  onChanged: (_) => setS(() {}),
                ),
                const SizedBox(height: 8),
                const Text('Variables :', style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final (token, label) in _tokens)
                      ActionChip(
                        label: Text(label, style: const TextStyle(fontSize: 11)),
                        avatar: const Icon(Icons.add, size: 14),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _insert(ctrl, token, setS),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text('Modèles :', style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 4),
                ...[ for (final (pattern, label) in _presets)
                  InkWell(
                    onTap: () {
                      ctrl.text = pattern;
                      ctrl.selection = TextSelection.collapsed(offset: pattern.length);
                      setS(() {});
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        const Icon(Icons.folder_outlined, size: 14, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Expanded(child: Text(pattern, style: const TextStyle(fontSize: 12, fontFamily: 'monospace'))),
                        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ]),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                const Text(
                  'Laissez vide pour "Rapport Technique" par défaut.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () async {
                await onSave(ctrl.text.trim());
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.folder_special_outlined, color: AppColors.primary),
      title: const Text('Dossier de destination des PDF'),
      subtitle: Text(
        current.isEmpty
            ? 'Chemin dans le cloud : Rapport Technique (par défaut)'
            : 'Chemin dans le cloud : $current',
        style: const TextStyle(fontSize: 12, color: Colors.black87),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
      onTap: () => _showDialog(context),
    );
  }
}

// ─── Template tile ───────────────────────────────────────────────────────────

class _TemplateTile extends StatelessWidget {
  final String current;
  final Future<void> Function(String) onSave;

  const _TemplateTile({required this.current, required this.onSave});

  static const _options = [
    ('professionnel', 'Professionnel', '2 colonnes — infos + signatures côte à côte'),
    ('simple', 'Simple', 'Sections empilées, fond bleu — rapide et épuré'),
  ];

  void _showDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dlg) => AlertDialog(
        title: const Text('Style de rapport PDF'),
        content: RadioGroup<String>(
          groupValue: current,
          onChanged: (v) async {
            if (v != null) await onSave(v);
            if (dlg.mounted) Navigator.pop(dlg);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _options.map((o) {
              final (value, label, desc) = o;
              return RadioListTile<String>(
                value: value,
                title: Text(label),
                subtitle: Text(desc, style: const TextStyle(fontSize: 12)),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlg),
            child: const Text('Annuler'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = current == 'professionnel' ? 'Professionnel' : 'Simple';
    return ListTile(
      leading: const Icon(Icons.description_outlined, color: AppColors.primary),
      title: const Text('Style de rapport PDF'),
      subtitle: Text(label,
          style: const TextStyle(fontSize: 12, color: Colors.black87)),
      trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
      onTap: () => _showDialog(context),
    );
  }
}

// ─── Logo tile ───────────────────────────────────────────────────────────────

class _LogoTile extends StatefulWidget {
  final String currentPath;
  final Future<void> Function(String) onSave;

  const _LogoTile({required this.currentPath, required this.onSave});

  @override
  State<_LogoTile> createState() => _LogoTileState();
}

class _LogoTileState extends State<_LogoTile> {
  bool _isPicking = false;

  Future<void> _pick() async {
    if (_isPicking) return;
    setState(() => _isPicking = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
        maxWidth: 512,
        maxHeight: 512,
      );
      if (picked == null) return;
      await widget.onSave(picked.path);
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Supprimer le logo ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('Supprimer',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) await widget.onSave('');
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.currentPath;
    final hasLogo = path.isNotEmpty &&
        !path.startsWith('http') &&
        File(path).existsSync();

    return ListTile(
      leading: hasLogo
          ? ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.file(File(path),
                  width: 40, height: 40, fit: BoxFit.contain),
            )
          : const Icon(Icons.add_photo_alternate_outlined,
              color: AppColors.primary),
      title: const Text('Logo entreprise'),
      subtitle: Text(
        hasLogo ? 'Affiché dans l\'en-tête du PDF' : 'Aucun logo — appuyer pour choisir',
        style: TextStyle(
          fontSize: 12,
          color: hasLogo ? Colors.green : Colors.grey,
        ),
      ),
      trailing: hasLogo
          ? IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: Colors.red, size: 20),
              tooltip: 'Supprimer le logo',
              onPressed: _isPicking ? null : _remove,
            )
          : const Icon(Icons.edit_outlined, size: 18, color: Colors.grey),
      onTap: _isPicking ? null : _pick,
    );
  }
}

// ─── Team section ─────────────────────────────────────────────────────────────

class _TeamSection extends ConsumerWidget {
  const _TeamSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // (simplification) Réglages = compte uniquement. L'équipe (membres,
    // identité, abonnement, invitation, quitter) se gère dans l'onglet « Équipe ».
    final user = ref.watch(firebaseUserProvider).valueOrNull;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (user != null)
          ListTile(
            leading: const Icon(Icons.manage_accounts_outlined,
                color: AppColors.primary),
            title: const Text('Mon profil'),
            subtitle: const Text(
                'Email, mot de passe, déconnexion, suppression',
                style: TextStyle(fontSize: 12)),
            trailing:
                const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
            onTap: () => context.push('/profile-account'),
          )
        else
          ListTile(
            leading: const Icon(Icons.login, color: AppColors.primary),
            title: const Text('Se connecter / créer un compte'),
            trailing:
                const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
            onTap: () => context.push('/auth'),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Text(
            'Votre équipe (membres, identité, abonnement) se gère dans '
            'l\'onglet « Équipe » (barre du bas).',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ),
      ],
    );
  }
}


// ─── Dev / test helpers (kDebugMode only) ────────────────────────────────────

class _DevSection extends ConsumerStatefulWidget {
  const _DevSection();

  @override
  ConsumerState<_DevSection> createState() => _DevSectionState();
}

class _DevSectionState extends ConsumerState<_DevSection> {
  bool _seeding = false;

  Future<void> _resetPdfCounter() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final key = 'pdf_export_count_${now.year}_${now.month.toString().padLeft(2, '0')}';
    await prefs.remove(key);
  }

  Future<void> _seedAppControl() async {
    setState(() => _seeding = true);
    try {
      await FirebaseFirestore.instance.collection('config').doc('app_control').set({
        'status': 'ACTIVE',
        'message': 'Application temporairement indisponible. Veuillez réessayer plus tard.',
        'min_build': 0,
        'latest_build': 0,
        'update_message': 'Une nouvelle version est disponible avec des améliorations.',
        'update_url_android': 'https://play.google.com/store/apps/details?id=com.tec.reportnew1cld',
        'update_url_ios': '',
        'broadcast_id': '',
        'broadcast_message': '',
        'broadcast_max_build': 0,
        'banner_id': '',
        'banner_message': '',
        'milestone_5_message': '',
        'milestone_10_message': '',
        'milestone_25_message': '',
        'milestone_50_message': '',
        'milestone_100_message': '',
        'ai_quota_monthly': 10,
        'blocked_tokens': [],
        'blocked_token_message': '',
      }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ config/app_control initialisé dans Firestore'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final override = ref.watch(debugSubOverrideProvider);
    final label = override == true
        ? 'Simulé : Pro actif'
        : override == false
            ? 'Simulé : Gratuit'
            : 'Réel (Firestore)';
    final multiHighlight = ref.watch(debugNavMultiHighlightProvider);
    final extraPad = ref.watch(debugNavExtraBottomPadProvider);

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.workspace_premium, color: Colors.orange),
          title: const Text('Simuler abonnement Pro'),
          subtitle: Text('État actuel : $label', style: const TextStyle(fontSize: 11)),
          onTap: () async {
            ref.read(debugSubOverrideProvider.notifier).state = true;
            final messenger = ScaffoldMessenger.of(context);
            await _resetPdfCounter();
            messenger.showSnackBar(
              const SnackBar(content: Text('✓ Mode Pro simulé (local uniquement)'), backgroundColor: Colors.green),
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.money_off, color: Colors.orange),
          title: const Text('Simuler mode Gratuit'),
          subtitle: const Text('Permet de retester l\'achat sans changer de compte', style: TextStyle(fontSize: 11)),
          onTap: () async {
            ref.read(debugSubOverrideProvider.notifier).state = false;
            final messenger = ScaffoldMessenger.of(context);
            await _resetPdfCounter();
            messenger.showSnackBar(
              const SnackBar(content: Text('✓ Mode gratuit simulé + compteur PDF remis à 0'), backgroundColor: Colors.orange),
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.cloud_sync, color: Colors.grey),
          title: const Text('Utiliser données réelles (Firestore)'),
          onTap: () {
            ref.read(debugSubOverrideProvider.notifier).state = null;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('✓ Override retiré — données Firestore actives')),
            );
          },
        ),
        const Divider(),
        ListTile(
          leading: _seeding
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.cloud_upload_outlined, color: Colors.teal),
          title: const Text('Seed config/app_control Firestore'),
          subtitle: const Text('Initialise tous les champs — à lancer une fois. Supprimer ensuite.', style: TextStyle(fontSize: 11)),
          onTap: _seeding ? null : _seedAppControl,
        ),
        const Divider(),
        SwitchListTile(
          secondary: const Icon(Icons.highlight_alt, color: Colors.deepPurple),
          title: const Text('Pills : multi-highlight'),
          subtitle: const Text('Allume toutes les pills dont le titre est visible à l\'écran', style: TextStyle(fontSize: 11)),
          value: multiHighlight,
          onChanged: (v) =>
              ref.read(debugNavMultiHighlightProvider.notifier).state = v,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.expand_more, color: Colors.deepPurple),
          title: const Text('Pills : padding bas (+400 px)'),
          subtitle: const Text('Permet aux dernières sections de remonter jusqu\'au seuil', style: TextStyle(fontSize: 11)),
          value: extraPad,
          onChanged: (v) =>
              ref.read(debugNavExtraBottomPadProvider.notifier).state = v,
        ),
      ],
    );
  }
}

// ─── Account card (top of Settings) ──────────────────────────────────────────

class _AccountCard extends ConsumerWidget {
  const _AccountCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(firebaseUserProvider).valueOrNull;

    if (user == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
        child: Card(
          elevation: 0,
          color: AppColors.primary.withValues(alpha: 0.06),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: AppColors.primary.withValues(alpha: 0.2)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.account_circle_outlined,
                    size: 36, color: AppColors.primary.withValues(alpha: 0.5)),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Non connecté',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      SizedBox(height: 2),
                      Text('Connectez-vous pour synchroniser vos données.',
                          style: TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: () => context.push('/auth'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  child: const Text('Se connecter'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final displayName = user.displayName?.isNotEmpty == true
        ? user.displayName!
        : user.email ?? '';
    final email = user.email ?? '';
    final initials = displayName.isNotEmpty
        ? displayName.trim().split(' ').map((w) => w[0]).take(2).join().toUpperCase()
        : '?';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
      child: Card(
        elevation: 0,
        color: AppColors.primary.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.primary.withValues(alpha: 0.2)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.push('/profile-account'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.primary,
                  backgroundImage:
                      user.photoURL != null ? NetworkImage(user.photoURL!) : null,
                  child: user.photoURL == null
                      ? Text(initials,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14))
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(displayName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      if (email.isNotEmpty && email != displayName)
                        Text(email,
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Mon entreprise (collapsible, starts closed) ─────────────────────────────

class _CompanySection extends ConsumerStatefulWidget {
  const _CompanySection();

  @override
  ConsumerState<_CompanySection> createState() => _CompanySectionState();
}

class _CompanySectionState extends ConsumerState<_CompanySection> {
  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider).valueOrNull ?? {};
    final team = ref.watch(teamStateProvider).valueOrNull;

    final teamCompanyName = team?.companyName ?? '';
    final soloCompanyName = (s['company_name'] ?? '').toString();

    // (simplification) Réglages = SOLO uniquement. L'identité d'ÉQUIPE est
    // gérée dans l'onglet « Équipe » (plus de toggle ni de dédoublement ici).

    // (S1 simplification) PLUS de verrou d'identité après X rapports : on fait
    // confiance à l'utilisateur. On affiche juste un avertissement discret quand
    // l'identité est renseignée (les changements suivent un PDF déjà envoyé).
    final anyIdentityFilled = soloCompanyName.isNotEmpty ||
        (s['company_siret'] ?? '').toString().isNotEmpty ||
        (s['company_address'] ?? '').toString().isNotEmpty;

    // (prefill) Le « Nom du technicien » est désormais pré-rempli avec le nom du
    // compte → on ne le compte PLUS comme « identité renseignée », sinon le cue
    // « à compléter » disparaîtrait alors que les infos ENTREPRISE sont vides.
    final isFilled = soloCompanyName.isNotEmpty ||
        teamCompanyName.isNotEmpty;
    final borderColor =
        isFilled ? Colors.grey.shade300 : AppColors.primary;

    // ── Champs PERSO (réglages locaux) ────────────────────────────────────
    List<Widget> persoFields() => [
          _EditableTile(
            icon: Icons.business,
            label: 'Nom de l\'entreprise',
            value: soloCompanyName,
            hint: 'Ex : Dupont Plomberie',
            onSave: (v) async {
              await ref.read(settingsProvider.notifier).set('company_name', v);
              IdentityAuditService.logField(
                  scope: 'solo',
                  field: 'company_name',
                  oldValue: soloCompanyName,
                  newValue: v);
            },
          ),
          _EditableTile(
            icon: Icons.person_outline,
            label: 'Nom du technicien',
            value: s['technician_name'] ?? '',
            hint: 'Ex : Jean Dupont',
            onSave: (v) =>
                ref.read(settingsProvider.notifier).set('technician_name', v),
          ),
          _EditableTile(
            icon: Icons.location_on_outlined,
            label: 'Adresse entreprise',
            value: s['company_address'] ?? '',
            hint: 'Ex : 15 rue de la Paix, 75001 Paris',
            onSave: (v) async {
              final old = (s['company_address'] ?? '').toString();
              await ref
                  .read(settingsProvider.notifier)
                  .set('company_address', v);
              IdentityAuditService.logField(
                  scope: 'solo',
                  field: 'company_address',
                  oldValue: old,
                  newValue: v);
            },
          ),
          _EditableTile(
            icon: Icons.phone_outlined,
            label: 'Téléphone entreprise',
            value: s['company_phone'] ?? '',
            hint: 'Ex : 06 12 34 56 78',
            onSave: (v) =>
                ref.read(settingsProvider.notifier).set('company_phone', v),
          ),
          _EditableTile(
            icon: Icons.email_outlined,
            label: 'Email entreprise',
            value: s['company_email'] ?? '',
            hint: 'Ex : contact@monentreprise.fr',
            onSave: (v) =>
                ref.read(settingsProvider.notifier).set('company_email', v),
          ),
          _EditableTile(
            icon: Icons.badge_outlined,
            label: 'SIRET',
            value: s['company_siret'] ?? '',
            hint: 'Ex : 123 456 789 00012',
            onSave: (v) async {
              final old = (s['company_siret'] ?? '').toString();
              await ref
                  .read(settingsProvider.notifier)
                  .set('company_siret', v);
              IdentityAuditService.logField(
                  scope: 'solo',
                  field: 'company_siret',
                  oldValue: old,
                  newValue: v);
            },
          ),
          _EditableTile(
            icon: Icons.receipt_long_outlined,
            label: 'N° TVA',
            value: s['company_tva'] ?? '',
            hint: 'Ex : FR12345678900',
            onSave: (v) =>
                ref.read(settingsProvider.notifier).set('company_tva', v),
          ),
          _LogoTile(
            currentPath: s['logo_path'] ?? '',
            onSave: (v) =>
                ref.read(settingsProvider.notifier).set('logo_path', v),
          ),
        ];

    // ── Champs ÉQUIPE (mêmes données que l'écran Équipe) ──────────────────
    // (#10) Membre d'une équipe : on explique pourquoi ses PDF d'équipe NE
    // prennent PAS ces champs (ils prennent l'identité de l'équipe), et que ces
    // champs ne servent QUE s'il prend EN PLUS un abonnement perso (solo).
    final children = <Widget>[
      if (team?.hasTeam ?? false)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.groups_outlined,
                      size: 16, color: AppColors.primary),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text('Vous faites partie d\'une équipe',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary)),
                  ),
                ]),
                const SizedBox(height: 4),
                Text(
                  'Vos rapports d\'équipe utilisent l\'identité de l\'ÉQUIPE '
                  '(gérée par le responsable), pas ces champs. Ceux-ci ne '
                  'servent que si vous prenez EN PLUS un abonnement perso (solo), '
                  'pour faire des rapports à votre propre nom.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => context.go('/team-tab'),
                    icon: const Icon(Icons.groups_outlined, size: 16),
                    label: const Text('Voir l\'identité de l\'équipe'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ...persoFields(),
    ];

    // (K) Déroulé à la demande (depuis le toggle d'un rapport).
    final expandReq = ref.watch(settingsExpandCompanyProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: borderColor, width: isFilled ? 1 : 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ExpansionTile(
            key: ValueKey(expandReq ?? 0),
            initiallyExpanded: expandReq != null,
            leading: Icon(
              Icons.business_outlined,
              color: isFilled ? Colors.grey : AppColors.primary,
            ),
            title: const Text(
              'MON ENTREPRISE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
                letterSpacing: 1,
              ),
            ),
            subtitle: anyIdentityFilled
                ? Text(
                    'Apparaît sur vos PDF. Évitez de la changer après envoi de '
                    'rapports (cohérence des documents déjà transmis).',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  )
                : const Text(
                    'À compléter pour vos PDF',
                    style: TextStyle(fontSize: 11, color: AppColors.primary),
                  ),
            shape: const Border(),
            collapsedShape: const Border(),
            children: children,
          ),
        ),
      ),
    );
  }
}

// ─── Feedback section ─────────────────────────────────────────────────────────

class _FeedbackSection extends ConsumerStatefulWidget {
  const _FeedbackSection();
  @override
  ConsumerState<_FeedbackSection> createState() => _FeedbackSectionState();
}

class _FeedbackSectionState extends ConsumerState<_FeedbackSection> {
  bool _expanded = false;
  final _msgCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  bool _sending = false;
  bool _sent = false;
  bool _consent = false;

  static const _prefKey = 'feedback_last_sent';

  @override
  void initState() {
    super.initState();
    _loadEmail();
    _checkAlreadySent();
  }

  Future<void> _loadEmail() async {
    final user = ref.read(firebaseUserProvider).valueOrNull;
    if (user?.email != null) {
      _emailCtrl.text = user!.email!;
    }
  }

  Future<void> _checkAlreadySent() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString(_prefKey);
    if (last != null) setState(() => _sent = true);
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final msg = _msgCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    if (msg.isEmpty || email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message et email requis.')),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      // (1.6) Feedback ouvert aux non-connectés : on se connecte en anonyme à la
      // volée. L'uid anonyme satisfait isAuthed_raptech1() côté règles (pas
      // d'ouverture aux requêtes vraiment non-authentifiées) et persiste sur
      // l'appareil → corrélable, et liable au compte réel plus tard.
      var user = ref.read(firebaseUserProvider).valueOrNull;
      if (user == null) {
        final cred = await FirebaseAuth.instance.signInAnonymously();
        user = cred.user;
      }
      final team = ref.read(teamStateProvider).valueOrNull;
      await FirebaseFirestore.instance
          .collection('feedback_raptech1')
          .add({
        'message': msg,
        'contact_email': email,
        'uid': user?.uid,
        'is_anonymous': user?.isAnonymous ?? false,
        'consent_marketing': _consent,
        'company_id': team?.companyId,
        'created_at': FieldValue.serverTimestamp(),
      });
      // Mémorise le consentement marketing sur le doc user (réutilisable).
      // Best-effort : ne bloque pas l'envoi du feedback en cas d'échec.
      if (user != null) {
        try {
          await FirebaseFirestore.instance
              .collection('users_raptech1')
              .doc(user.uid)
              .set({
            'marketing_consent': _consent,
            'marketing_consent_at':
                _consent ? FieldValue.serverTimestamp() : null,
          }, SetOptions(merge: true));
        } catch (_) {}
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _prefKey, DateTime.now().toIso8601String());
      if (!mounted) return;
      setState(() { _sent = true; _expanded = false; _consent = false; });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Message envoyé — merci !'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_sent && !_expanded) {
      return ListTile(
        leading: const Icon(Icons.check_circle_outline, color: Colors.green),
        title: const Text('Feedback envoyé'),
        subtitle: const Text('Vous pouvez en envoyer un autre si besoin',
            style: TextStyle(fontSize: 11)),
        trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
        onTap: () => setState(() { _expanded = true; _sent = false; _msgCtrl.clear(); }),
      );
    }

    if (!_expanded) {
      return ListTile(
        leading: const Icon(Icons.feedback_outlined, color: AppColors.primary),
        title: const Text('Envoyer un feedback / signaler un problème'),
        subtitle: const Text('Votre message ira directement au développeur',
            style: TextStyle(fontSize: 11)),
        trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
        onTap: () => setState(() => _expanded = true),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _msgCtrl,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Votre message',
              hintText: 'Décrivez le problème ou partagez une suggestion…',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Votre email (pour vous répondre)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.mail_outline),
            ),
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: () => setState(() => _consent = !_consent),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: _consent,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (v) => setState(() => _consent = v ?? false),
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Text(
                        'J\'accepte d\'être recontacté(e) par email pour des offres, '
                        'nouveautés ou bons plans (facultatif).',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_outlined, size: 16),
                  label: const Text('Envoyer'),
                ),
              ),
              const SizedBox(width: 10),
              TextButton(
                onPressed: () => setState(() => _expanded = false),
                child: const Text('Annuler'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Section title ─────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
            letterSpacing: 1,
          ),
        ),
      );
}

// ─── Parrainage section v8 ────────────────────────────────────────────────────
// Tuile compacte → ouvre la page dédiée /referral (ReferralScreen).

class _ParrainageSection extends ConsumerWidget {
  const _ParrainageSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(firebaseUserProvider).valueOrNull?.uid;
    final isPro = ref.watch(effectiveSubscriptionProvider);
    final activeCount = ref.watch(activeActivationsCountProvider);
    final nextPrice = ref.watch(nextPricePreviewProvider);

    final String subtitle;
    if (uid == null) {
      subtitle = 'Connectez-vous pour accéder au parrainage';
    } else if (isPro && activeCount > 0) {
      subtitle = 'Prochain paiement : '
          '${nextPrice.toStringAsFixed(2).replaceAll('.', ',')} €/mois · '
          '$activeCount parrainage${activeCount > 1 ? 's' : ''} actif${activeCount > 1 ? 's' : ''}';
    } else if (isPro) {
      subtitle = 'Invitez des proches → votre prix baisse jusqu\'à −50%';
    } else {
      subtitle = 'Invitez des proches et payez moins — ouvrez pour entrer un code';
    }

    return ListTile(
      leading: const Icon(Icons.card_giftcard_outlined, color: AppColors.primary),
      title: const Text('Parrainage'),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        if (uid == null) {
          context.push('/auth');
        } else {
          context.push('/referral');
        }
      },
    );
  }
}

// ─── Version tile + manip cachée "Code spécial" (2 étages) ────────────────────
// Étage 1 : taper 7× sur le numéro de version → fenêtre intermédiaire.
// Étage 2 : dans cette fenêtre, taper 7× sur l'icône → dialogue de saisie de code.
// But : cacher l'entrée des codes promo/cadeau pour ne pas la confondre avec le parrainage.

class _VersionTile extends StatefulWidget {
  const _VersionTile();
  @override
  State<_VersionTile> createState() => _VersionTileState();
}

class _VersionTileState extends State<_VersionTile> {
  int _taps = 0;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  void _onTap() {
    final now = DateTime.now();
    // reset si trop lent (>1.2s entre deux taps)
    if (now.difference(_last) > const Duration(milliseconds: 1200)) _taps = 0;
    _last = now;
    _taps++;
    if (_taps >= 7) {
      _taps = 0;
      _showStage2();
    }
  }

  void _showStage2() {
    showDialog<void>(
      context: context,
      builder: (_) => const _Stage2Dialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.info_outline),
      title: const Text('Version'),
      trailing: const Text('1.0.0', style: TextStyle(color: Colors.grey)),
      onTap: _onTap,
    );
  }
}

class _Stage2Dialog extends StatefulWidget {
  const _Stage2Dialog();
  @override
  State<_Stage2Dialog> createState() => _Stage2DialogState();
}

class _Stage2DialogState extends State<_Stage2Dialog> {
  int _taps = 0;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  void _onTap() {
    final now = DateTime.now();
    if (now.difference(_last) > const Duration(milliseconds: 1200)) _taps = 0;
    _last = now;
    _taps++;
    if (_taps >= 7) {
      _taps = 0;
      Navigator.pop(context);
      showDialog<void>(context: context, builder: (_) => const _SpecialCodeDialog());
    }
  }

  @override
  Widget build(BuildContext context) {
    // Fenêtre volontairement anodine — rien n'indique la 2e manip.
    return AlertDialog(
      title: const Text('Informations système'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: _onTap,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Icon(Icons.memory, size: 48, color: Colors.grey),
            ),
          ),
          const Text('Build 1.0.0 · raptech1',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer')),
      ],
    );
  }
}

class _SpecialCodeDialog extends StatefulWidget {
  const _SpecialCodeDialog();
  @override
  State<_SpecialCodeDialog> createState() => _SpecialCodeDialogState();
}

class _SpecialCodeDialogState extends State<_SpecialCodeDialog> {
  final _ctrl = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(children: [
        Icon(Icons.vpn_key_outlined, color: AppColors.primary),
        SizedBox(width: 8),
        Text('Code spécial'),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text(
          'Entrez un code spécial (cadeau ou réduction).',
          style: TextStyle(fontSize: 13, color: Colors.black54),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: 'Code',
            border: const OutlineInputBorder(),
            isDense: true,
            errorText: _error,
          ),
          onChanged: (_) { if (_error != null) setState(() => _error = null); },
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: _loading ? null : _apply,
          child: _loading
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Valider'),
        ),
      ],
    );
  }

  Future<void> _apply() async {
    final code = _ctrl.text.trim().toUpperCase();
    if (code.isEmpty) return;
    setState(() => _loading = true);
    try {
      final (_, message) = await SubscriptionService.redeemCode(code);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 5),
        ));
      }
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }
}
