import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/profile_context_provider.dart';

/// (Phase 2) Switcher de PROFIL dédié (perso ↔ équipe).
/// TOUJOURS visible : l'option non disponible (pas d'équipe, ou pas d'abo solo
/// en équipe) est GRISÉE et explique comment l'activer au tap.
/// Carte segmentée adaptée à un fond clair (Mon compte).
class ProfileSwitcherCard extends ConsumerWidget {
  const ProfileSwitcherCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(activeProfileModeProvider);
    final canPerso = ref.watch(canUsePersoProfileProvider);
    final canEquipe = ref.watch(canUseEquipeProfileProvider);
    final teamName =
        (ref.watch(teamStateProvider).valueOrNull?.companyName ?? 'Mon équipe')
            .trim();

    void explain(ProfileMode m) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m == ProfileMode.equipe
            ? 'Rejoignez ou créez une équipe pour générer des rapports au nom '
                'd\'une équipe.'
            : 'Un abonnement solo est nécessaire pour créer des rapports perso '
                'lorsque vous êtes en équipe.'),
      ));
    }

    Widget seg(ProfileMode m, IconData icon, String label, bool available) {
      final selected = mode == m && available;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: !available
              ? () => explain(m)
              : (mode == m
                  ? null
                  : () => ref.read(activeProfileProvider.notifier).setMode(m)),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(available ? icon : Icons.lock_outline,
                    size: 16,
                    color: selected
                        ? Colors.white
                        : (available
                            ? Colors.grey.shade600
                            : Colors.grey.shade400)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.1,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? Colors.white
                          : (available
                              ? Colors.grey.shade700
                              : Colors.grey.shade400),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.assignment_outlined, size: 17, color: AppColors.primary),
            const SizedBox(width: 6),
            const Expanded(
              child: Text('Quel type de rapport voulez-vous créer ?',
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary)),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            'Vous avez deux casquettes. Choisissez sous quelle identité créer '
            'vos prochains rapports — l\'app chargera automatiquement le bon '
            'nom d\'entreprise et les bonnes coordonnées sur le PDF.',
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            padding: const EdgeInsets.all(4),
            child: Row(children: [
              seg(ProfileMode.perso, Icons.person_outline, 'Mes rapports\nperso',
                  canPerso),
              const SizedBox(width: 4),
              seg(ProfileMode.equipe, Icons.business_outlined,
                  teamName.isEmpty ? 'Mon équipe' : teamName, canEquipe),
            ]),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  mode == ProfileMode.perso
                      ? Icons.person_outline
                      : Icons.business_outlined,
                  size: 15,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    mode == ProfileMode.perso
                        ? 'Actif : PERSO. Vos nouveaux rapports portent VOTRE '
                            'société (nom + SIRET perso) et apparaissent dans '
                            'Rapports › Perso.'
                        : 'Actif : ÉQUIPE. Vos nouveaux rapports portent '
                            'l\'identité de l\'équipe (nom verrouillé) et '
                            'apparaissent dans Rapports › Équipe.',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
