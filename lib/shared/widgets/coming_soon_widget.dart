import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class ComingSoonButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isListTile;

  const ComingSoonButton({
    super.key,
    required this.label,
    required this.icon,
    this.isListTile = false,
  });

  void _showDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.rocket_launch, color: AppColors.accent),
            const SizedBox(width: 8),
            const Text('Bientôt disponible'),
          ],
        ),
        content: Text(
          '$label est en cours de développement.\nCette fonctionnalité arrivera prochainement !',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isListTile) {
      return ListTile(
        leading: Icon(icon, color: Colors.grey),
        title: Text(label, style: const TextStyle(color: Colors.grey)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'Bientôt',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        onTap: () => _showDialog(context),
      );
    }

    return OutlinedButton.icon(
      onPressed: () => _showDialog(context),
      icon: Icon(icon, size: 18),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'Bientôt',
              style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      style: OutlinedButton.styleFrom(foregroundColor: Colors.grey),
    );
  }
}
