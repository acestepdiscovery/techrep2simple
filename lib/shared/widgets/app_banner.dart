import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_build.dart';

/// (2026-10-23) Bandeau « message du développeur » en haut de la liste des rapports,
/// version 2 — demandes du user après le 1er essai (bandeau « mise à jour à venir ») :
///  - plus VISIBLE : fond plein coloré, texte blanc, grande icône ;
///  - « J'ai lu » au lieu d'une petite croix (l'utilisateur confirme avoir lu) ;
///  - EN DIRECT : l'app écoute `config/app_control` → le bandeau apparaît / change dès
///    qu'on le règle dans Firestore, sans fermer ni rouvrir l'app (avant : lu une seule
///    fois au démarrage par l'écran d'accueil).
/// Champs (document `config/app_control`, mêmes noms qu'avant + 2 facultatifs) :
///   banner_id             (texte) identifiant NON VIDE ; le changer = le bandeau revient
///   banner_message        (texte) message (toutes langues)
///   banner_message_LANGUE (texte) message dans cette langue, prioritaire (_fr, _en…)
///   banner_style          (texte) « info » (bleu, défaut) ou « alert » (rouge)
///   banner_max_build      (nombre) facultatif : seulement les versions ≤ ce build
/// Les anciennes versions (1.0.x) gardent leur bandeau (pâle, croix, au démarrage).
class AppBannerData {
  final String id;
  final String text;
  final bool alert;
  const AppBannerData({required this.id, required this.text, this.alert = false});
}

/// Lecture du document (format Firestore « map ») — testée (test/app_banner_test.dart).
AppBannerData? bannerFromMap(Map<String, dynamic>? d,
    {String lang = 'fr', int currentBuild = 0}) {
  if (d == null) return null;
  String? s(String k) {
    final v = d[k];
    return (v is String && v.trim().isNotEmpty) ? v.trim() : null;
  }

  final id = s('banner_id');
  final text = s('banner_message_$lang') ?? s('banner_message');
  if (id == null || text == null) return null;
  final maxBuild = d['banner_max_build'];
  if (maxBuild is num && currentBuild > 0 && currentBuild > maxBuild) return null;
  return AppBannerData(id: id, text: text, alert: s('banner_style') == 'alert');
}

class AppBanner extends StatefulWidget {
  const AppBanner({super.key, this.source});

  /// Source du document `config/app_control` (remplaçable dans les tests).
  @visibleForTesting
  final Stream<Map<String, dynamic>?>? source;

  static const prefPrefix = 'dismissed_banner_'; // même clé que l'ancien bandeau

  @override
  State<AppBanner> createState() => _AppBannerState();
}

class _AppBannerState extends State<AppBanner> {
  StreamSubscription<Map<String, dynamic>?>? _sub;
  AppBannerData? _data;
  Set<String> _dismissed = {};

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _dismissed = prefs
          .getKeys()
          .where((k) => k.startsWith(AppBanner.prefPrefix) && prefs.getBool(k) == true)
          .map((k) => k.substring(AppBanner.prefPrefix.length))
          .toSet();
    } catch (_) {}
    if (!mounted) return;
    final stream = widget.source ??
        FirebaseFirestore.instance
            .collection('config')
            .doc('app_control')
            .snapshots()
            .map((s) => s.data());
    _sub = stream.listen((d) {
      final lang = (Intl.defaultLocale ?? 'fr').split(RegExp('[_-]')).first;
      final b = bannerFromMap(d, lang: lang, currentBuild: kAppBuildNumber);
      if (mounted) setState(() => _data = b);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _read() async {
    final id = _data?.id;
    if (id == null) return;
    setState(() => _dismissed = {..._dismissed, id});
    try {
      (await SharedPreferences.getInstance()).setBool('${AppBanner.prefPrefix}$id', true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final b = _data;
    if (b == null || _dismissed.contains(b.id)) return const SizedBox.shrink();
    final bg = b.alert ? Colors.red.shade700 : const Color(0xFF1565C0);
    return Container(
      key: const ValueKey('app_banner'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(b.alert ? Icons.warning_amber_rounded : Icons.campaign,
                  color: Colors.white, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(b.text,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600, height: 1.35)),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const ValueKey('app_banner_read'),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              onPressed: _read,
              icon: const Icon(Icons.check, size: 18),
              label: Text('banner_read'.tr(),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
