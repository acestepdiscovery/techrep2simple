import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show Intl;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_build.dart';
import '../services/kill_switch_service.dart';

/// (2026-10-21) Message PAR PAGE (idée du user) : carte colorée en haut d'une page,
/// réglée dans Firestore `config/app_control`, INVISIBLE tant que rien n'est réglé.
/// Champs (ex. page « ai ») :
///   page_msg_ai_id        (texte)  identifiant ; le changer = le message réapparaît
///   page_msg_ai           (texte)  message pour toutes les langues
///   page_msg_ai_LANGUE    (texte)  message dans cette langue (prioritaire) : _fr, _en…
///   page_msg_ai_style     (texte)  « info » (bleu, défaut) ou « alert » (rouge)
///   page_msg_ai_max_build (nombre) facultatif : seulement les versions ≤ ce build
/// L'utilisateur peut la fermer (croix) : elle ne revient pas tant que l'id ne change pas.
/// Lecture : même document et même cache que le message à tous (KillSwitchService).
class PageMessageCard extends StatefulWidget {
  const PageMessageCard({super.key, required this.page});

  /// Nom court de la page dans les champs Firestore (« ai »…).
  final String page;

  @override
  State<PageMessageCard> createState() => _PageMessageCardState();
}

class _PageMessageCardState extends State<PageMessageCard> {
  PageMessage? _msg;

  String get _prefKey => 'page_msg_dismissed_${widget.page}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await KillSwitchService.check(currentBuild: kAppBuildNumber);
    final lang = (Intl.defaultLocale ?? 'fr').split(RegExp('[_-]')).first;
    final m = KillSwitchService.pageMessageFromFields(KillSwitchService.lastFields, widget.page,
        currentBuild: kAppBuildNumber, lang: lang);
    if (m == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_prefKey) == m.id) return; // déjà fermé
    } catch (_) {}
    if (mounted) setState(() => _msg = m);
  }

  Future<void> _dismiss() async {
    final id = _msg?.id;
    setState(() => _msg = null);
    if (id == null) return;
    try {
      (await SharedPreferences.getInstance()).setString(_prefKey, id);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final m = _msg;
    if (m == null) return const SizedBox.shrink();
    final color = m.alert ? Colors.red.shade700 : Colors.blue.shade700;
    return Container(
      key: ValueKey('page_msg_${widget.page}'),
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
      decoration: BoxDecoration(
        color: m.alert ? Colors.red.shade50 : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(m.alert ? Icons.warning_amber_rounded : Icons.campaign_outlined,
                color: color, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(m.text, style: TextStyle(color: color, fontSize: 13.5, height: 1.35)),
            ),
          ),
          IconButton(
            key: ValueKey('page_msg_close_${widget.page}'),
            icon: Icon(Icons.close, size: 18, color: color),
            visualDensity: VisualDensity.compact,
            onPressed: _dismiss,
          ),
        ],
      ),
    );
  }
}
