import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/services/team_service.dart';
import '../../../shared/services/identity_audit_service.dart';
import '../../auth/providers/auth_provider.dart';

// ─── Team company info (identité d'équipe sur les PDF) ────────────────────────
// Form admin : adresse / SIRET / tél / email / TVA de l'ÉQUIPE. Optionnel,
// rempli au fil du temps. Utilisé sur les PDF des rapports d'équipe (jamais les
// infos perso). Vide tant que non rempli.
//
// Widget PARTAGÉ : utilisé à la fois dans Équipe → tableau de bord ET dans
// Réglages → Mon entreprise. Admin = éditable (avec verrou adresse+SIRET après
// 10 rapports) ; membre = lecture seule.
class TeamCompanyInfoCard extends ConsumerStatefulWidget {
  final String companyId;
  final bool isAdmin;
  final bool initiallyExpanded; // (J) ouvre la tuile directement
  const TeamCompanyInfoCard(
      {super.key,
      required this.companyId,
      required this.isAdmin,
      this.initiallyExpanded = false});

  @override
  ConsumerState<TeamCompanyInfoCard> createState() =>
      _TeamCompanyInfoCardState();
}

class _TeamCompanyInfoCardState extends ConsumerState<TeamCompanyInfoCard> {
  // (#6) Le NOM de l'équipe est désormais DANS ce formulaire (plus de tuile
  // « Renommer » séparée) → une seule section d'identité, comme en solo.
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _siret = TextEditingController();
  final _tva = TextEditingController();
  // (#13Q) Permet de REPLIER la tuile après « Enregistrer » → confirmation
  // visuelle claire que c'est bien sauvegardé (avant : on restait dans le champ,
  // ça donnait l'impression que rien n'avait été pris en compte).
  final _tileController = ExpansibleController();
  bool _saving = false;
  bool _loaded = false;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    _email.dispose();
    _siret.dispose();
    _tva.dispose();
    super.dispose();
  }

  void _prefill(TeamState? t) {
    if (_loaded || t == null) return;
    _name.text = t.companyName ?? '';
    _address.text = t.companyAddress ?? '';
    _phone.text = t.companyPhone ?? '';
    _email.text = t.companyEmail ?? '';
    _siret.text = t.companySiret ?? '';
    _tva.text = t.companyTva ?? '';
    _loaded = true;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    // (S1 anti-fraude) on capture l'ancienne identité légale avant écriture.
    final prev = ref.read(teamStateProvider).valueOrNull;
    final oldName = prev?.companyName ?? '';
    final oldAddress = prev?.companyAddress ?? '';
    final oldSiret = prev?.companySiret ?? '';
    try {
      // (#6) Le NOM passe par updateCompanyName (notifier) + journal dédié ;
      // les autres champs par updateCompanyInfo.
      final newName = _name.text.trim();
      if (newName.isNotEmpty && newName != oldName.trim()) {
        await ref
            .read(teamStateProvider.notifier)
            .updateCompanyName(widget.companyId, newName);
        IdentityAuditService.logField(
            scope: 'team',
            companyId: widget.companyId,
            field: 'name',
            oldValue: oldName,
            newValue: newName);
      }
      await TeamService().updateCompanyInfo(widget.companyId, {
        'company_address': _address.text,
        'company_phone': _phone.text,
        'company_email': _email.text,
        'company_siret': _siret.text,
        'company_tva': _tva.text,
      });
      // Journalise seulement les champs d'identité LÉGALE modifiés.
      final changes = <Map<String, String>>[];
      if (oldAddress.trim() != _address.text.trim()) {
        changes.add({
          'field': 'company_address',
          'old': oldAddress,
          'new': _address.text,
        });
      }
      if (oldSiret.trim() != _siret.text.trim()) {
        changes.add({
          'field': 'company_siret',
          'old': oldSiret,
          'new': _siret.text,
        });
      }
      if (changes.isNotEmpty) {
        IdentityAuditService.log(
            scope: 'team', companyId: widget.companyId, changes: changes);
      }
      // (fix Q) le widget peut avoir été disposé pendant l'await (le doc équipe
      // se met à jour → rebuild). On garde ref/UI derrière `mounted`.
      if (mounted) {
        ref.invalidate(teamStateProvider);
        // (#13Q) Replie la tuile + ferme le clavier → « c'est enregistré ».
        FocusScope.of(context).unfocus();
        _tileController.collapse();
      }
      messenger.showSnackBar(const SnackBar(
        content: Text('Infos entreprise de l\'équipe enregistrées ✓'),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Erreur : ${e.toString().replaceFirst('Exception: ', '')}'),
        backgroundColor: Colors.red,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(TextEditingController c, String label,
      {TextInputType? keyboard, bool locked = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: c,
        keyboardType: keyboard,
        readOnly: locked,
        onTap: locked
            ? () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text(
                    'Champ verrouillé (identité légale figée après 10 rapports). '
                    'Contactez le support pour corriger.')))
            : null,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
          filled: locked,
          fillColor: locked ? Colors.grey.shade100 : null,
          suffixIcon: locked
              ? Icon(Icons.lock_outline, size: 16, color: Colors.grey.shade500)
              : null,
        ),
      ),
    );
  }

  /// Ligne lecture seule (vue membre).
  Widget _readOnlyRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ),
          Expanded(
            child: Text(value.isEmpty ? '—' : value,
                style: const TextStyle(fontSize: 13)),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final team = ref.watch(teamStateProvider).valueOrNull;
    _prefill(team);

    // ── Vue MEMBRE : lecture seule ────────────────────────────────────────
    if (!widget.isAdmin) {
      return ExpansionTile(
        initiallyExpanded: widget.initiallyExpanded,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        leading: const Icon(Icons.business_outlined, size: 20),
        title: const Text('Infos entreprise de l\'équipe',
            style: TextStyle(fontSize: 14)),
        subtitle: const Text(
          'Gérées par l\'administrateur · lecture seule.',
          style: TextStyle(fontSize: 11),
        ),
        children: [
          _readOnlyRow('Nom', team?.companyName ?? ''),
          _readOnlyRow('Adresse', team?.companyAddress ?? ''),
          _readOnlyRow('Téléphone', team?.companyPhone ?? ''),
          _readOnlyRow('Email', team?.companyEmail ?? ''),
          _readOnlyRow('SIRET', team?.companySiret ?? ''),
          _readOnlyRow('N° TVA', team?.companyTva ?? ''),
        ],
      );
    }

    // ── Vue ADMIN : éditable (S1 : PLUS de verrou — on fait confiance) ──────
    return ExpansionTile(
      controller: _tileController, // (#13Q) repli après enregistrement
      initiallyExpanded: widget.initiallyExpanded,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      leading: const Icon(Icons.business_outlined, size: 20),
      title: const Text('Infos entreprise de l\'équipe',
          style: TextStyle(fontSize: 14)),
      subtitle: const Text(
        'Adresse, SIRET… affichés sur les PDF de l\'équipe (optionnel).',
        style: TextStyle(fontSize: 11),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Ces infos s\'impriment sur les PDF de l\'équipe et sont '
            'SYNCHRONISÉES automatiquement avec tous vos techniciens. '
            'Des modifications trop fréquentes sont interdites : ces données '
            'identifient votre entreprise. Les changer régulièrement (par ex. '
            'pour faire tourner le compte entre plusieurs sociétés) est '
            'considéré comme une fraude et peut entraîner la suspension du compte.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ),
        _field(_name, 'Nom de l\'entreprise (équipe)'),
        _field(_address, 'Adresse'),
        _field(_phone, 'Téléphone', keyboard: TextInputType.phone),
        _field(_email, 'Email', keyboard: TextInputType.emailAddress),
        _field(_siret, 'SIRET'),
        _field(_tva, 'N° TVA'),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_outlined, size: 18),
            label: const Text('Enregistrer'),
          ),
        ),
      ],
    );
  }
}
