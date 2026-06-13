import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/providers/auth_provider.dart';
import 'team_dashboard_screen.dart';

/// Onglet « Équipe » dédié (nav tab).
///  • Si l'utilisateur A une équipe → on affiche le tableau de bord d'équipe
///    (identité, membres, invitation, abonnement équipe…).
///  • Sinon → un état vide explicatif (pourquoi une équipe, NON obligatoire) +
///    un bouton pour créer ou rejoindre une équipe.
/// → vide la page Réglages de tout ce qui concerne l'équipe ; Réglages = solo.
class TeamTabScreen extends ConsumerWidget {
  const TeamTabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teamAsync = ref.watch(teamStateProvider);
    return teamAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Équipe')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Équipe')),
        body: Center(child: Text('Erreur : $e')),
      ),
      data: (team) {
        if (team.hasTeam) return const TeamDashboardScreen();
        return _EmptyTeamState();
      },
    );
  }
}

/// État vide « grisé » + explication + bouton créer/rejoindre.
class _EmptyTeamState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Équipe')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.groups_2_outlined,
                  size: 72, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              Text(
                'Vous travaillez à plusieurs ?',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700),
              ),
              const SizedBox(height: 12),
              Text(
                'Une équipe permet à plusieurs techniciens d\'une même entreprise '
                'd\'utiliser l\'app ensemble : identité d\'entreprise commune sur '
                'les PDF, validation des rapports, et un abonnement mutualisé où '
                'le parrainage de chacun fait baisser la facture commune.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 8),
              Text(
                'Ce n\'est pas obligatoire — si vous travaillez seul, tout se '
                'passe dans Réglages.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey.shade500),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => context.push('/team-setup'),
                icon: const Icon(Icons.group_add_outlined),
                label: const Text('Créer ou rejoindre une équipe'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
