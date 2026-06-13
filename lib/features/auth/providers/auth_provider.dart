import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../features/team/models/company_model.dart';
import '../../../shared/services/team_service.dart';

// ─── Firebase auth stream ──────────────────────────────────────────────────

final firebaseUserProvider = StreamProvider<User?>((ref) {
  try {
    // (fix G) Les utilisateurs ANONYMES (créés à la volée pour le feedback non
    // connecté) ne doivent PAS compter comme « connecté » → on les mappe à null,
    // sinon l'app croit l'utilisateur loggé (tuiles compte/abonnement, etc.).
    // L'écriture du feedback utilise FirebaseAuth.currentUser directement.
    return FirebaseAuth.instance
        .authStateChanges()
        .map((u) => (u != null && u.isAnonymous) ? null : u);
  } catch (_) {
    return const Stream.empty();
  }
});

// ─── Team state (persisted in SharedPreferences + Firestore backup) ───────
//
// Persistence strategy:
//   • SharedPreferences: fast cold-start read, no network needed.
//   • Firestore users_raptech1/{uid}.company_id: backup used when
//     SharedPreferences is empty (e.g. after sign-out on same device).
//     Written by saveTeam(), deleted by clearTeam(removeLink: true).
//
// On sign-out we call clearTeam() WITHOUT removeLink so the Firestore backup
// is preserved.  When the same user signs back in, build() finds the backup
// and restores their team membership automatically.
//
// On leave-team or delete-account we call clearTeam(removeLink: true) so
// the backup is also wiped.

class TeamState {
  final String? companyId;
  final String? companyName;
  final String? role; // 'admin' | 'tech'
  final String? inviteCode;
  // (identité équipe) Champs entreprise PROPRES à l'équipe, optionnels, remplis
  // au fil du temps par l'admin. Utilisés sur les PDF d'équipe (jamais les
  // infos perso). Vides tant que non remplis.
  final String? companyAddress;
  final String? companyPhone;
  final String? companyEmail;
  final String? companySiret;
  final String? companyTva;

  const TeamState({
    this.companyId,
    this.companyName,
    this.role,
    this.inviteCode,
    this.companyAddress,
    this.companyPhone,
    this.companyEmail,
    this.companySiret,
    this.companyTva,
  });

  bool get hasTeam => companyId != null;
  bool get isAdmin => role == 'admin';

  TeamState copyWith({
    String? companyId,
    String? companyName,
    String? role,
    String? inviteCode,
    String? companyAddress,
    String? companyPhone,
    String? companyEmail,
    String? companySiret,
    String? companyTva,
  }) =>
      TeamState(
        companyId: companyId ?? this.companyId,
        companyName: companyName ?? this.companyName,
        role: role ?? this.role,
        inviteCode: inviteCode ?? this.inviteCode,
        companyAddress: companyAddress ?? this.companyAddress,
        companyPhone: companyPhone ?? this.companyPhone,
        companyEmail: companyEmail ?? this.companyEmail,
        companySiret: companySiret ?? this.companySiret,
        companyTva: companyTva ?? this.companyTva,
      );
}

class TeamStateNotifier extends AsyncNotifier<TeamState> {
  static const _keyCompanyId = 'team_company_id';
  static const _keyCompanyName = 'team_company_name';
  static const _keyRole = 'team_role';
  static const _keyInviteCode = 'team_invite_code';
  // (4b/4c) Propriétaire du cache local : empêche un utilisateur B de récupérer
  // l'équipe/le nom de company d'un utilisateur A sur le même device.
  static const _keyOwnerUid = 'team_cache_owner_uid';

  static final _db = FirebaseFirestore.instance;

  @override
  Future<TeamState> build() async {
    // Rendre l'état réactif aux changements d'authentification (login/logout) :
    // à chaque changement d'utilisateur, build() est relancé avec le bon uid.
    final uid = ref.watch(firebaseUserProvider).valueOrNull?.uid ??
        FirebaseAuth.instance.currentUser?.uid;

    final prefs = await SharedPreferences.getInstance();

    // ── Déconnecté → aucune équipe. Ne JAMAIS exposer le cache d'un autre user.
    if (uid == null) return const TeamState();

    // ── Garde anti-contamination cross-compte ────────────────────────────────
    // Si le cache local appartient à un AUTRE uid, on le purge avant lecture.
    final cacheOwner = prefs.getString(_keyOwnerUid);
    if (cacheOwner != null && cacheOwner != uid) {
      await _persist(const TeamState());
    }

    final cached = TeamState(
      companyId: prefs.getString(_keyCompanyId),
      companyName: prefs.getString(_keyCompanyName),
      role: prefs.getString(_keyRole),
      inviteCode: prefs.getString(_keyInviteCode),
    );

    // ── Path A: SharedPreferences has a companyId ─────────────────────────
    // Verify the member doc still exists and sync authoritative data.
    if (cached.companyId != null) {
      try {
        final memberDoc = await _db
            .collection('companies_raptech1')
            .doc(cached.companyId)
            .collection('members_raptech1')
            .doc(uid)
            .get();
        if (!memberDoc.exists) {
          // Kicked or left while offline — wipe everything
          await _persist(const TeamState());
          await _clearFirestoreLink(uid);
          return const TeamState();
        }
        // Sync role + company name from Firestore
        final companyDoc = await _db
            .collection('companies_raptech1')
            .doc(cached.companyId)
            .get();
        final cd = companyDoc.data() ?? {};
        final fresh = TeamState(
          companyId: cached.companyId,
          companyName: cd['name'] as String? ?? cached.companyName,
          role: memberDoc.data()?['role'] as String? ?? cached.role,
          inviteCode: cd['invite_code'] as String? ?? cached.inviteCode,
          companyAddress: cd['company_address'] as String?,
          companyPhone: cd['company_phone'] as String?,
          companyEmail: cd['company_email'] as String?,
          companySiret: cd['company_siret'] as String?,
          companyTva: cd['company_tva'] as String?,
        );
        await _persist(fresh);
        // Backfill Firestore company_id for users who joined before saveTeam()
        // started writing it — ensures next sign-out/sign-in restores PRO.
        try {
          final userSnap =
              await _db.collection('users_raptech1').doc(uid).get();
          if (userSnap.data()?['company_id'] == null) {
            await _db
                .collection('users_raptech1')
                .doc(uid)
                .set({'company_id': fresh.companyId!}, SetOptions(merge: true));
          }
        } catch (_) {}
        _attachLiveCompany(fresh.companyId!); // (P) maj live des infos équipe
        return fresh;
      } catch (_) {
        // Offline — return cached, Firestore stream will update when online
        return cached;
      }
    }

    // ── Path B: SharedPreferences is empty (e.g. after sign-out) ─────────
    // Try to recover from the Firestore backup written by saveTeam().
    try {
      final userDoc =
          await _db.collection('users_raptech1').doc(uid).get();
      final companyId = userDoc.data()?['company_id'] as String?;
      if (companyId == null) return const TeamState();

      final memberDoc = await _db
          .collection('companies_raptech1')
          .doc(companyId)
          .collection('members_raptech1')
          .doc(uid)
          .get();
      if (!memberDoc.exists) {
        // Membership was revoked — clear Firestore backup too
        await _clearFirestoreLink(uid);
        return const TeamState();
      }
      final companyDoc = await _db
          .collection('companies_raptech1')
          .doc(companyId)
          .get();
      final cd = companyDoc.data() ?? {};
      final restored = TeamState(
        companyId: companyId,
        companyName: cd['name'] as String?,
        role: memberDoc.data()?['role'] as String? ?? 'tech',
        inviteCode: cd['invite_code'] as String?,
        companyAddress: cd['company_address'] as String?,
        companyPhone: cd['company_phone'] as String?,
        companyEmail: cd['company_email'] as String?,
        companySiret: cd['company_siret'] as String?,
        companyTva: cd['company_tva'] as String?,
      );
      await _persist(restored);
      _attachLiveCompany(restored.companyId!); // (P) maj live des infos équipe
      return restored;
    } catch (_) {
      return const TeamState();
    }
  }

  // (P) Abonnement LIVE au doc de l'équipe : dès que le CEO change le nom ou les
  // infos entreprise, TOUS les membres voient la maj immédiatement (avant : le
  // teamState lisait le doc UNE fois → il fallait un Ctrl+R / redémarrage).
  void _attachLiveCompany(String companyId) {
    final sub = _db
        .collection('companies_raptech1')
        .doc(companyId)
        .snapshots()
        .listen((snap) {
      final cur = state.valueOrNull;
      if (cur == null || cur.companyId != companyId) return;
      // (#2) L'équipe a été DISSOUTE (le CEO a supprimé son compte → doc company
      // supprimé). On nettoie l'état local + le lien (la donnée n'existe plus) →
      // le membre retombe sur « pas d'équipe » et peut en créer une nouvelle.
      if (!snap.exists) {
        clearTeam(removeLink: true);
        return;
      }
      final cd = snap.data();
      if (cd == null) return;
      final updated = cur.copyWith(
        companyName: cd['name'] as String?,
        inviteCode: cd['invite_code'] as String?,
        companyAddress: cd['company_address'] as String?,
        companyPhone: cd['company_phone'] as String?,
        companyEmail: cd['company_email'] as String?,
        companySiret: cd['company_siret'] as String?,
        companyTva: cd['company_tva'] as String?,
      );
      state = AsyncData(updated);
      _persist(updated);
    }, onError: (_) {});
    ref.onDispose(sub.cancel);
  }

  Future<void> _persist(TeamState s) async {
    final prefs = await SharedPreferences.getInstance();
    // Estampille le propriétaire du cache (uid courant) tant qu'il y a une équipe.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (s.companyId != null && uid != null) {
      await prefs.setString(_keyOwnerUid, uid);
    } else {
      await prefs.remove(_keyOwnerUid);
    }
    if (s.companyId != null) {
      await prefs.setString(_keyCompanyId, s.companyId!);
    } else {
      await prefs.remove(_keyCompanyId);
    }
    if (s.companyName != null) {
      await prefs.setString(_keyCompanyName, s.companyName!);
    } else {
      await prefs.remove(_keyCompanyName);
    }
    if (s.role != null) {
      await prefs.setString(_keyRole, s.role!);
    } else {
      await prefs.remove(_keyRole);
    }
    if (s.inviteCode != null) {
      await prefs.setString(_keyInviteCode, s.inviteCode!);
    } else {
      await prefs.remove(_keyInviteCode);
    }
  }

  Future<void> _clearFirestoreLink(String uid) async {
    try {
      await _db.collection('users_raptech1').doc(uid).update(
        {'company_id': FieldValue.delete()},
      );
    } catch (_) {}
  }

  Future<void> saveTeam(CompanyModel company, String role) async {
    final next = TeamState(
      companyId: company.id,
      companyName: company.name,
      role: role,
      inviteCode: company.inviteCode,
    );
    await _persist(next);
    state = AsyncData(next);
    // Backup companyId to Firestore so sign-out/sign-in restores membership
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await _db.collection('users_raptech1').doc(uid).set(
          {'company_id': company.id},
          SetOptions(merge: true),
        );
      }
    } catch (_) {}
  }

  Future<void> updateCompanyName(String companyId, String newName) async {
    await TeamService().updateCompanyName(companyId, newName);
    final current = state.valueOrNull ?? const TeamState();
    final next = current.copyWith(companyName: newName.trim());
    await _persist(next);
    state = AsyncData(next);
  }

  Future<void> refreshInviteCode(String companyId) async {
    final code = await TeamService().regenerateInviteCode(companyId);
    final current = state.valueOrNull ?? const TeamState();
    final next = current.copyWith(inviteCode: code);
    await _persist(next);
    state = AsyncData(next);
  }

  /// Clears local team state.
  ///
  /// [removeLink] = true: also deletes the Firestore backup (use on
  /// leave-team and delete-account so the user truly exits).
  /// [removeLink] = false (default): keeps the Firestore backup so the next
  /// sign-in on the same device automatically restores team membership.
  Future<void> clearTeam({bool removeLink = false}) async {
    await _persist(const TeamState());
    state = const AsyncData(TeamState());
    if (removeLink) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) await _clearFirestoreLink(uid);
    }
  }
}

final teamStateProvider =
    AsyncNotifierProvider<TeamStateNotifier, TeamState>(TeamStateNotifier.new);
