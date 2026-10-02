import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../reports/models/tax_options.dart';

/// Éditeur de taxe RÉUTILISABLE (Réglages = défaut global ; form de création =
/// override d'un rapport). Dropdown pays + préréglages de taux + mode
/// personnalisé (taux/intitulé libres) + mention légale éditable + bouton
/// « Réinitialiser » (→ défaut déduit de la région/langue).
///
/// Retourne le [TaxConfig] choisi, ou `null` si annulé.
Future<TaxConfig?> showTaxEditor(
  BuildContext context, {
  required TaxConfig initial,
  required TaxConfig localeDefault,
}) {
  return showDialog<TaxConfig>(
    context: context,
    builder: (_) => _TaxEditorDialog(initial: initial, localeDefault: localeDefault),
  );
}

String _flagEmoji(String code) {
  if (code.length != 2) return '';
  final up = code.toUpperCase();
  return String.fromCharCodes([
    0x1F1E6 + up.codeUnitAt(0) - 65,
    0x1F1E6 + up.codeUnitAt(1) - 65,
  ]);
}

class _TaxEditorDialog extends StatefulWidget {
  final TaxConfig initial;
  final TaxConfig localeDefault;
  const _TaxEditorDialog({required this.initial, required this.localeDefault});

  @override
  State<_TaxEditorDialog> createState() => _TaxEditorDialogState();
}

class _TaxEditorDialogState extends State<_TaxEditorDialog> {
  late String _countryCode;
  late bool _custom;
  late final TextEditingController _rateCtrl;
  late final TextEditingController _labelCtrl;
  late final TextEditingController _mentionCtrl;

  @override
  void initState() {
    super.initState();
    _rateCtrl = TextEditingController();
    _labelCtrl = TextEditingController();
    _mentionCtrl = TextEditingController();
    _loadFrom(widget.initial);
  }

  // Tente de retrouver un pays + préréglage correspondant à une config ; sinon
  // bascule en « Autre / personnalisé » avec les champs pré-remplis.
  void _loadFrom(TaxConfig cfg) {
    for (final c in kTaxCountries) {
      for (final p in c.presets) {
        if (p.label == cfg.label && p.rate == cfg.rate) {
          _countryCode = c.code;
          _custom = false;
          _rateCtrl.text = formatTaxRate(cfg.rate);
          _labelCtrl.text = cfg.label;
          _mentionCtrl.text = cfg.mention;
          return;
        }
      }
    }
    _countryCode = kTaxOtherCode;
    _custom = true;
    _rateCtrl.text = formatTaxRate(cfg.rate);
    _labelCtrl.text = cfg.label;
    _mentionCtrl.text = cfg.mention;
  }

  void _applyPreset(TaxPreset p) {
    setState(() {
      _custom = false;
      _rateCtrl.text = formatTaxRate(p.rate);
      _labelCtrl.text = p.label;
      _mentionCtrl.text = p.mention;
    });
  }

  void _onCountryChanged(String code) {
    setState(() {
      _countryCode = code;
      final c = taxCountryByCode(code);
      if (c != null && c.presets.isNotEmpty) {
        _custom = false;
        final p = c.presets.first;
        _rateCtrl.text = formatTaxRate(p.rate);
        _labelCtrl.text = p.label;
        _mentionCtrl.text = p.mention;
      } else {
        // « Autre » → saisie libre.
        _custom = true;
      }
    });
  }

  double get _currentRate =>
      double.tryParse(_rateCtrl.text.replaceAll(',', '.').trim()) ?? 0;

  @override
  void dispose() {
    _rateCtrl.dispose();
    _labelCtrl.dispose();
    _mentionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final country = taxCountryByCode(_countryCode);

    final countryItems = <DropdownMenuItem<String>>[
      ...kTaxCountries.map((c) => DropdownMenuItem(
            value: c.code,
            child: Text('${_flagEmoji(c.code)}  ${c.nameKey.tr()}',
                overflow: TextOverflow.ellipsis),
          )),
      DropdownMenuItem(
        value: kTaxOtherCode,
        child: Text('🌐  ${kTaxOtherNameKey.tr()}', overflow: TextOverflow.ellipsis),
      ),
    ];

    return AlertDialog(
      title: Text('tax_title'.tr()),
      content: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Pays
              Text('tax_country'.tr(),
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              DropdownButton<String>(
                value: _countryCode,
                isExpanded: true,
                items: countryItems,
                onChanged: (v) {
                  if (v != null) _onCountryChanged(v);
                },
              ),
              const SizedBox(height: 8),
              // Préréglages de taux du pays
              if (country != null && country.presets.isNotEmpty) ...[
                Text('tax_rate_label'.tr(),
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ...country.presets.map((p) {
                      final selected = !_custom &&
                          _labelCtrl.text == p.label &&
                          _currentRate == p.rate;
                      final pct = '${formatTaxRate(p.rate)} %';
                      return ChoiceChip(
                        label: Text(
                          p.mention.isNotEmpty
                              ? '${p.label} $pct ✓'
                              : '${p.label} $pct',
                          style: const TextStyle(fontSize: 12),
                        ),
                        selected: selected,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => _applyPreset(p),
                      );
                    }),
                    ChoiceChip(
                      label: Text('tax_custom'.tr(),
                          style: const TextStyle(fontSize: 12)),
                      selected: _custom,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(() => _custom = true),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              // Champs (toujours visibles en mode perso ou pays « Autre »)
              if (_custom) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: _rateCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'tax_rate_label'.tr(),
                          suffixText: '%',
                          isDense: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _labelCtrl,
                        decoration: InputDecoration(
                          labelText: 'tax_label_label'.tr(),
                          hintText: 'tax_label_hint'.tr(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              // Mention légale (toujours éditable)
              TextField(
                controller: _mentionCtrl,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'tax_mention_label'.tr(),
                  hintText: 'tax_mention_hint'.tr(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 6),
              // Aperçu de la ligne facture
              Text(
                'tax_preview'.tr(args: [
                  _labelCtrl.text.trim().isEmpty ? '—' : _labelCtrl.text.trim(),
                  formatTaxRate(_currentRate),
                ]),
                style: const TextStyle(fontSize: 11, color: AppColors.primary),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _loadFrom(widget.localeDefault),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text('tax_reset'.tr(), style: const TextStyle(fontSize: 12)),
                ),
              ),
              Text('tax_disclaimer'.tr(),
                  style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('common_cancel'.tr()),
        ),
        ElevatedButton(
          onPressed: () {
            final label = _labelCtrl.text.trim();
            Navigator.pop(
              context,
              TaxConfig(
                rate: _currentRate,
                label: label,
                mention: _mentionCtrl.text.trim(),
              ),
            );
          },
          child: Text('common_save'.tr()),
        ),
      ],
    );
  }
}
