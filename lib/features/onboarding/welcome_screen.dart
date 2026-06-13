import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  Future<void> _goSolo(BuildContext context) async {
    if (context.mounted) context.push('/onboarding-intro');
  }

  Future<void> _goJoin(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_mode', 'team');
    await prefs.setString('team_intent', 'join');
    if (context.mounted) context.push('/auth');
  }

  Future<void> _goCreate(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_mode', 'team');
    await prefs.setString('team_intent', 'create');
    if (context.mounted) context.push('/auth');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Icon(Icons.assignment, size: 50, color: Colors.white),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                AppStrings.appName,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                AppStrings.appTagline,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
              ),
              const Spacer(),
              // "J'ai déjà un compte" — placé AU-DESSUS des 3 cartes
              OutlinedButton.icon(
                onPressed: () => context.push('/auth?mode=login'),
                icon: const Icon(Icons.login, size: 18, color: Colors.white),
                label: const Text(
                  'J\'ai déjà un compte — Se connecter',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white60, width: 1.5),
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              _ModeCard(
                icon: Icons.phone_android,
                title: 'Utiliser seul',
                subtitle: 'Rapports en local, sans compte. Idéal pour commencer.',
                onTap: () => _goSolo(context),
                isHighlighted: true,
              ),
              const SizedBox(height: 12),
              _ModeCard(
                icon: Icons.group_outlined,
                title: 'Rejoindre une équipe',
                subtitle: 'Mon chef a déjà un compte — j\'ai un code d\'invitation.',
                onTap: () => _goJoin(context),
                isHighlighted: false,
              ),
              const SizedBox(height: 12),
              _ModeCard(
                icon: Icons.business_center_outlined,
                title: 'Créer mon équipe',
                subtitle: 'Je suis responsable et je veux gérer mes techniciens.',
                onTap: () => _goCreate(context),
                isHighlighted: false,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isHighlighted;

  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isHighlighted ? Colors.white : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: isHighlighted ? null : Border.all(color: Colors.white.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isHighlighted
                    ? AppColors.primary.withValues(alpha: 0.1)
                    : Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: isHighlighted ? AppColors.primary : Colors.white, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: isHighlighted ? AppColors.primary : Colors.white,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: isHighlighted
                          ? Colors.black54
                          : Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: isHighlighted ? AppColors.primary : Colors.white70,
            ),
          ],
        ),
      ),
    );
  }
}
