import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_build.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/utils/error_text.dart';
import '../../auth/providers/auth_provider.dart';
import '../../subscription/subscription_provider.dart';
import '../custom_report_request.dart';

/// (2026-10-21) « Votre rapport sur mesure » — voir custom_report_request.dart.
class CustomReportRequestScreen extends ConsumerStatefulWidget {
  const CustomReportRequestScreen({super.key});

  @override
  ConsumerState<CustomReportRequestScreen> createState() => _CustomReportRequestScreenState();
}

class _CustomReportRequestScreenState extends ConsumerState<CustomReportRequestScreen> {
  final List<PlatformFile> _files = [];
  final _msgCtrl = TextEditingController();
  bool _sending = false;
  bool _sent = false;

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _pick() async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: templateAllowedExtensions,
    );
    if (res == null || !mounted) return;
    for (final f in res.files) {
      if (_files.length >= kTemplateMaxFiles) break;
      final err = templateFileError(f.name, f.size);
      if (err == 'type') {
        _snack('crr_err_type'.tr(args: [f.name]));
      } else if (err == 'size') {
        _snack('crr_err_size'.tr(args: [f.name]));
      } else if (f.path != null) {
        _files.add(f);
      }
    }
    setState(() {});
  }

  Future<void> _send() async {
    final user = ref.read(firebaseUserProvider).valueOrNull;
    if (user == null || _files.isEmpty) return;
    setState(() => _sending = true);
    try {
      final now = DateTime.now();
      final email = user.email ?? '';
      final lang = (Intl.defaultLocale ?? 'fr').split(RegExp('[_-]')).first;
      final paths = <String>[];
      for (var i = 0; i < _files.length; i++) {
        final f = _files[i];
        final path = templateRequestPath(user.uid, now, i + 1, f.name);
        await FirebaseStorage.instance.ref(path).putFile(
              File(f.path!),
              SettableMetadata(
                contentType: templateContentType(f.name),
                customMetadata: {'email': email, 'lang': lang, 'app_build': '$kAppBuildNumber'},
              ),
            );
        paths.add(path);
      }
      // Trace dans les avis (même collection que « Envoyer un avis ») = notification
      // pour le développeur, avec l'e-mail pour répondre.
      final note = _msgCtrl.text.trim();
      await FirebaseFirestore.instance.collection('feedback_raptech1').add({
        'message': '[Modèle de rapport] ${_files.length} fichier(s) : '
            '${_files.map((f) => f.name).join(', ')}${note.isEmpty ? '' : '\n$note'}',
        'contact_email': email,
        'uid': user.uid,
        'is_anonymous': user.isAnonymous,
        'kind': 'template_request',
        'files': paths,
        'created_at': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      setState(() {
        _sent = true;
        _files.clear();
        _msgCtrl.clear();
      });
    } catch (e) {
      if (mounted) _snack('crr_err_send'.tr(args: [errorText(e)]));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _emailBlock() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('crr_email_intro'.tr(), style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SelectableText(kContactEmail,
              key: const ValueKey('crr_email'),
              style: const TextStyle(fontSize: 16, color: AppColors.primary)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(const ClipboardData(text: kContactEmail));
                _snack('crr_copied'.tr());
              },
              icon: const Icon(Icons.copy, size: 16),
              label: Text('crr_copy'.tr()),
            ),
            OutlinedButton.icon(
              onPressed: () => launchUrl(Uri(
                  scheme: 'mailto',
                  path: kContactEmail,
                  query: 'subject=${Uri.encodeComponent('crr_mail_subject'.tr())}')),
              icon: const Icon(Icons.mail_outline, size: 16),
              label: Text('crr_open_mail'.tr()),
            ),
          ]),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final isPro = ref.watch(effectiveSubscriptionProvider);
    final signedIn = ref.watch(firebaseUserProvider).valueOrNull != null;
    final canUpload = isPro && signedIn;
    return Scaffold(
      appBar: AppBar(title: Text('crr_title'.tr())),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.design_services_outlined, size: 44, color: AppColors.primary),
          const SizedBox(height: 12),
          Text('crr_intro'.tr(), style: const TextStyle(fontSize: 15, height: 1.4)),
          const SizedBox(height: 20),
          if (_sent)
            Container(
              key: const ValueKey('crr_sent'),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Icon(Icons.check_circle, color: Colors.green.shade700),
                const SizedBox(width: 10),
                Expanded(child: Text('crr_sent'.tr())),
              ]),
            )
          else if (canUpload) ...[
            OutlinedButton.icon(
              key: const ValueKey('crr_pick'),
              onPressed: _sending || _files.length >= kTemplateMaxFiles ? null : _pick,
              icon: const Icon(Icons.attach_file),
              label: Text('crr_pick'.tr()),
            ),
            const SizedBox(height: 6),
            Text('crr_files_hint'.tr(), style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            for (var i = 0; i < _files.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(_files[i].name.toLowerCase().endsWith('.pdf')
                    ? Icons.picture_as_pdf_outlined
                    : Icons.image_outlined),
                title: Text(_files[i].name, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: _sending ? null : () => setState(() => _files.removeAt(i)),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _msgCtrl,
              maxLines: 3,
              maxLength: 1000,
              decoration: InputDecoration(
                labelText: 'crr_message_label'.tr(),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const ValueKey('crr_send'),
              onPressed: _sending || _files.isEmpty ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
              label: Text('crr_send'.tr()),
            ),
            const SizedBox(height: 28),
            const Divider(),
            const SizedBox(height: 12),
            _emailBlock(),
          ] else ...[
            _emailBlock(),
            const SizedBox(height: 16),
            Text('crr_email_pro_hint'.tr(),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          ],
        ],
      ),
    );
  }
}
