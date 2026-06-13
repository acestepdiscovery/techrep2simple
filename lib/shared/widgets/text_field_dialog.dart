import 'package:flutter/material.dart';

/// Boîte de dialogue à un seul champ texte, **sûre côté cycle de vie**.
///
/// Pourquoi ce helper existe : si on crée un `TextEditingController` localement
/// puis qu'on appelle `controller.dispose()` juste après `await showDialog(...)`,
/// le contrôleur est libéré AVANT la fin de l'animation de fermeture du dialog.
/// Le `TextField` se reconstruit alors avec un contrôleur disposé →
/// « A TextEditingController was used after being disposed » + écran rouge.
///
/// Ici le contrôleur est possédé par le State du dialog et disposé dans
/// `dispose()` (donc seulement quand le widget quitte vraiment l'arbre, après
/// l'animation). Plus jamais ce bug. À réutiliser partout où on a besoin d'un
/// petit dialog « saisir une valeur ».
///
/// Retourne le texte **trimé** si l'utilisateur valide, `null` s'il annule.
Future<String?> showSingleFieldDialog({
  required BuildContext context,
  required String title,
  String? initialValue,
  String? label,
  String? hint,
  String confirmLabel = 'Enregistrer',
  String cancelLabel = 'Annuler',
  String? helperText,
  int maxLines = 1,
  bool autofocus = true,
  TextCapitalization textCapitalization = TextCapitalization.none,
  TextInputType? keyboardType,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _SingleFieldDialog(
      title: title,
      initialValue: initialValue,
      label: label,
      hint: hint,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      helperText: helperText,
      maxLines: maxLines,
      autofocus: autofocus,
      textCapitalization: textCapitalization,
      keyboardType: keyboardType,
    ),
  );
}

class _SingleFieldDialog extends StatefulWidget {
  final String title;
  final String? initialValue;
  final String? label;
  final String? hint;
  final String confirmLabel;
  final String cancelLabel;
  final String? helperText;
  final int maxLines;
  final bool autofocus;
  final TextCapitalization textCapitalization;
  final TextInputType? keyboardType;

  const _SingleFieldDialog({
    required this.title,
    this.initialValue,
    this.label,
    this.hint,
    required this.confirmLabel,
    required this.cancelLabel,
    this.helperText,
    required this.maxLines,
    required this.autofocus,
    required this.textCapitalization,
    this.keyboardType,
  });

  @override
  State<_SingleFieldDialog> createState() => _SingleFieldDialogState();
}

class _SingleFieldDialogState extends State<_SingleFieldDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _ctrl,
            autofocus: widget.autofocus,
            maxLines: widget.maxLines,
            textCapitalization: widget.textCapitalization,
            keyboardType: widget.keyboardType,
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: widget.hint,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => Navigator.pop(context, _ctrl.text.trim()),
          ),
          if (widget.helperText != null) ...[
            const SizedBox(height: 8),
            Text(
              widget.helperText!,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
