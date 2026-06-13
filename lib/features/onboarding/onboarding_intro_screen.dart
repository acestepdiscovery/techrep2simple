import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_colors.dart';

class OnboardingIntroScreen extends StatelessWidget {
  const OnboardingIntroScreen({super.key});

  Future<void> _start(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    await prefs.setString('app_mode', 'offline');
    if (context.mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: BackButton(color: AppColors.primary),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Comment ça marche ?',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'Tout ce dont vous avez besoin, en 3 étapes.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.black54),
              ),
              const SizedBox(height: 36),
              _FeatureRow(
                step: '1',
                icon: Icons.edit_note,
                title: 'Créez votre rapport',
                body:
                    'Remplissez le formulaire guidé : infos client, équipement, travaux. '
                    'Ajoutez des photos et la signature du client — sur place ou à distance.',
              ),
              const SizedBox(height: 24),
              _FeatureRow(
                step: '2',
                icon: Icons.picture_as_pdf_outlined,
                title: 'Exportez en PDF',
                body:
                    'Un PDF professionnel est généré automatiquement. '
                    'Partagez-le par WhatsApp, email ou enregistrez-le sur Drive / OneDrive / Dropbox.',
              ),
              const SizedBox(height: 24),
              _FeatureRow(
                step: '3',
                icon: Icons.auto_awesome,
                title: 'Laissez l\'IA vous aider',
                body:
                    'Dictez votre rapport à voix haute ou photographiez un formulaire papier. '
                    'L\'IA remplit les champs pour vous. (Fonctionnalité Pro)',
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => _start(context),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Commencer',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final String step;
  final IconData icon;
  final String title;
  final String body;

  const _FeatureRow({
    required this.step,
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: AppColors.primary, size: 26),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: const TextStyle(fontSize: 13, color: Colors.black54, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
