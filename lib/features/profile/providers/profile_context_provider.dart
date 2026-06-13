import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../auth/providers/auth_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../../subscription/subscription_provider.dart';

/// (Chantier solo↔équipe — Phase 1) Contexte de PROFIL actif de l'utilisateur.
///
/// Décisions verrouillées (2026-06-02) :
///  • Un utilisateur peut avoir 2 profils : **perso** et **équipe**.
///  • Le profil **perso** est TOUJOURS disponible (#10/D5, 2026-06-09) : sans abo
///    solo, les exports perso passent par les 5 gratuits/mois (device) — on
///    AVERTIT au basculement, on ne bloque plus.
///  • Le profil **équipe** est disponible dès qu'on appartient à une équipe.
///  • Le **switcher** n'apparaît que si les DEUX profils sont disponibles.
///  • Le nom d'entreprise sur les PDF suit le profil actif (perso → nom perso ;
///    équipe → nom d'équipe verrouillé).

enum ProfileMode { perso, equipe }

/// Abonnement SOLO (personnel) actif ?
final hasSoloSubProvider = Provider<bool>((ref) {
  return ref.watch(subscriptionProvider).valueOrNull.isActive;
});

/// Le profil ÉQUIPE est dispo dès qu'on est dans une équipe.
final canUseEquipeProfileProvider = Provider<bool>((ref) {
  return ref.watch(teamStateProvider).valueOrNull?.hasTeam ?? false;
});

/// (#10/D5) Le profil PERSO est TOUJOURS disponible. Sans abonnement solo, les
/// rapports perso retombent sur les 5 exports gratuits/mois (par device) — on
/// avertit au basculement plutôt que de bloquer. Permet à tout membre d'équipe de
/// faire des rapports perso (sous SON identité perso, jamais le nom de l'équipe).
final canUsePersoProfileProvider = Provider<bool>((ref) {
  return true;
});

/// Le switcher n'a de sens que si les DEUX profils sont disponibles.
final canSwitchProfileProvider = Provider<bool>((ref) {
  return ref.watch(canUseEquipeProfileProvider) &&
      ref.watch(canUsePersoProfileProvider);
});

/// Profil actif (persisté + borné à la disponibilité).
final activeProfileProvider =
    AsyncNotifierProvider<ActiveProfileNotifier, ProfileMode>(
        ActiveProfileNotifier.new);

class ActiveProfileNotifier extends AsyncNotifier<ProfileMode> {
  static const _key = 'active_profile_mode';

  @override
  Future<ProfileMode> build() async {
    final canEquipe = ref.watch(canUseEquipeProfileProvider);
    final canPerso = ref.watch(canUsePersoProfileProvider);

    // (#10 cas E) Défaut INTELLIGENT : en équipe, on ouvre normalement sur le
    // profil ÉQUIPE — SAUF si l'utilisateur a un abo SOLO mais PAS de couverture
    // équipe (siège). Dans ce cas on ouvre sur PERSO (le profil réellement
    // couvert), pour ne pas le bloquer d'emblée « siège non actif » alors qu'il
    // paie en solo. (Ne s'applique qu'au PREMIER choix ; un choix mémorisé prime.)
    final hasSolo = ref.watch(hasSoloSubProvider);
    final companySub = ref.watch(companySubscriptionProvider).valueOrNull;
    final lifetimeSeats =
        ref.watch(companyLifetimeSeatsProvider).valueOrNull ?? 0;
    final teamActive = companySub.isActive || lifetimeSeats > 0;
    final defaultMode = !canEquipe
        ? ProfileMode.perso
        : (hasSolo && !teamActive ? ProfileMode.perso : ProfileMode.equipe);

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_key);
    var mode = stored == 'perso'
        ? ProfileMode.perso
        : stored == 'equipe'
            ? ProfileMode.equipe
            : defaultMode;

    // Borne à la disponibilité (ex. on perd l'abo solo → retombe sur équipe).
    if (mode == ProfileMode.equipe && !canEquipe) mode = ProfileMode.perso;
    if (mode == ProfileMode.perso && !canPerso) mode = ProfileMode.equipe;
    return mode;
  }

  Future<void> setMode(ProfileMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
    state = AsyncData(mode);
  }
}

/// Accès SYNCHRONE pratique au profil actif (défaut le temps du chargement).
final activeProfileModeProvider = Provider<ProfileMode>((ref) {
  return ref.watch(activeProfileProvider).valueOrNull ??
      (ref.watch(canUseEquipeProfileProvider)
          ? ProfileMode.equipe
          : ProfileMode.perso);
});

/// Nom d'entreprise EFFECTIF à utiliser (PDF, en-têtes) selon le profil actif :
///  • équipe → nom de l'équipe (verrouillé),
///  • perso  → nom d'entreprise personnel (réglages locaux).
final activeCompanyNameProvider = Provider<String>((ref) {
  final mode = ref.watch(activeProfileModeProvider);
  if (mode == ProfileMode.equipe) {
    return (ref.watch(teamStateProvider).valueOrNull?.companyName ?? '').trim();
  }
  final settings = ref.watch(settingsProvider).valueOrNull ?? {};
  return (settings['company_name'] ?? '').toString().trim();
});

/// Réglages d'identité d'entreprise COMPLETS selon le profil actif (pour
/// l'aperçu PDF des NOUVEAUX rapports, où companyId n'est pas encore connu) :
///  • perso  → réglages locaux (nom + siret + adresse + logo…),
///  • équipe → infos de l'ÉQUIPE (ou BLANC), JAMAIS les infos perso.
final activeCompanySettingsProvider = Provider<Map<String, String>>((ref) {
  final base = Map<String, String>.from(
      ref.watch(settingsProvider).valueOrNull ?? <String, String>{});
  if (ref.watch(activeProfileModeProvider) == ProfileMode.equipe) {
    final t = ref.watch(teamStateProvider).valueOrNull;
    base['company_name'] = t?.companyName ?? '';
    base['company_address'] = t?.companyAddress ?? '';
    base['company_phone'] = t?.companyPhone ?? '';
    base['company_email'] = t?.companyEmail ?? '';
    base['company_siret'] = t?.companySiret ?? '';
    base['company_tva'] = t?.companyTva ?? '';
    // (#6) En profil ÉQUIPE, le NOM technicien et le LOGO sont les champs PROPRES
    // au coéquipier (`team_*`), distincts du solo. Repli sur le solo s'ils sont
    // vides (pas de régression pour qui n'a rempli que ses infos solo).
    final teamTech = (base['team_technician_name'] ?? '').trim();
    if (teamTech.isNotEmpty) base['technician_name'] = teamTech;
    final teamLogo = (base['team_logo_path'] ?? '').trim();
    base['logo_path'] = teamLogo.isNotEmpty ? teamLogo : (base['logo_path'] ?? '');
  }
  return base;
});
