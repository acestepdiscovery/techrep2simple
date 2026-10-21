import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// (2026-10-21) Mini-guide « 1re connexion » à Google Drive / OneDrive / Dropbox,
/// demandé par le user après le test sur émulateur : la 1re fois, le navigateur
/// s'ouvre (connexion + « Accepter »), puis les envois sont directs. Cas piège vu
/// au test : un compte Microsoft dont le OneDrive n'a jamais été ouvert.
Future<void> showCloudGuide(BuildContext context) {
  Widget section(IconData icon, Color color, String key) {
    final lines = key.tr().split('\n');
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(lines.first, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(lines.skip(1).join('\n'), style: const TextStyle(fontSize: 13, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  return showDialog<void>(
    context: context,
    builder: (dlg) => AlertDialog(
      title: Text('cloud_guide_title'.tr()),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            section(Icons.add_to_drive, Colors.blue, 'cloud_guide_gdrive'),
            section(Icons.cloud_outlined, const Color(0xFF0078D4), 'cloud_guide_onedrive'),
            section(Icons.inbox_outlined, const Color(0xFF0061FF), 'cloud_guide_dropbox'),
            Text('cloud_guide_after'.tr(),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.35)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dlg), child: Text('common_close'.tr())),
      ],
    ),
  );
}

/// Lien « 1re connexion : comment ça marche ? » qui ouvre le guide.
class CloudGuideLink extends StatelessWidget {
  const CloudGuideLink({super.key});

  @override
  Widget build(BuildContext context) => TextButton.icon(
        key: const ValueKey('cloud_guide_link'),
        style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
        onPressed: () => showCloudGuide(context),
        icon: const Icon(Icons.help_outline, size: 18),
        label: Text('cloud_guide_link'.tr()),
      );
}
