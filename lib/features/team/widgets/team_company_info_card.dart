import 'package:easy_localization/easy_localization.dart';
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
      messenger.showSnackBar(SnackBar(
        content: Text('tc_saved'.tr()),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('common_error'.tr(args: [e.toString().replaceFirst('Exception: ', '')])),
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
            ? () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('tc_field_locked'.tr())))
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
        title: Text('tc_company_info_title'.tr(),
            style: TextStyle(fontSize: 14)),
        subtitle: Text(
          'tc_member_subtitle'.tr(),
          style: const TextStyle(fontSize: 11),
        ),
        children: [
          _readOnlyRow('rd_name'.tr(), team?.companyName ?? ''),
          _readOnlyRow('field_address'.tr(), team?.companyAddress ?? ''),
          _readOnlyRow('cr_phone'.tr(), team?.companyPhone ?? ''),
          _readOnlyRow('auth_field_email'.tr(), team?.companyEmail ?? ''),
          _readOnlyRow('settings_siret'.tr(), team?.companySiret ?? ''),
          _readOnlyRow('settings_vat'.tr(), team?.companyTva ?? ''),
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
      title: Text('tc_company_info_title'.tr(),
          style: TextStyle(fontSize: 14)),
      subtitle: Text(
        'tc_admin_subtitle'.tr(),
        style: const TextStyle(fontSize: 11),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'tc_admin_warning'.tr(),
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ),
        _field(_name, 'tc_company_name'.tr()),
        _field(_address, 'field_address'.tr()),
        _field(_phone, 'cr_phone'.tr(), keyboard: TextInputType.phone),
        _field(_email, 'auth_field_email'.tr(), keyboard: TextInputType.emailAddress),
        _field(_siret, 'settings_siret'.tr()),
        _field(_tva, 'settings_vat'.tr()),
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
            label: Text('common_save'.tr()),
          ),
        ),
      ],
    );
  }
}
