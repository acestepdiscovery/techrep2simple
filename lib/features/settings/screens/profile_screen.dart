import 'dart:io' show Platform;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/services/team_service.dart';
import '../../../shared/services/subscription_service.dart';
import '../../../shared/services/notification_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../subscription/subscription_provider.dart';

/// Page "Mon profil" — regroupe les actions de compte :
/// changer email, changer mot de passe, se déconnecter, supprimer le compte.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(firebaseUserProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Mon profil')),
      body: user == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.account_circle_outlined,
                      size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  const Text('Connectez-vous pour gérer votre compte.'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => context.push('/auth'),
                    child: const Text('Se connecter'),
                  ),
                ]),
              ),
            )
          : _ProfileBody(user: user),
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  final User user;
  const _ProfileBody({required this.user});

  bool get _isPasswordUser =>
      user.providerData.any((p) => p.providerId == 'password');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayName = user.displayName?.isNotEmpty == true
        ? user.displayName!
        : user.email ?? '';
    final email = user.email ?? '';
    final initials = displayName.isNotEmpty
        ? displayName.trim().split(' ').map((w) => w[0]).take(2).join().toUpperCase()
        : '?';

    return ListView(
      children: [
        // ── Carte compte ───────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: AppColors.primary,
                backgroundImage:
                    user.photoURL != null ? NetworkImage(user.photoURL!) : null,
                child: user.photoURL == null
                    ? Text(initials,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (user.displayName?.isNotEmpty == true)
                    Text(user.displayName!,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(email,
                      style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ]),
              ),
            ]),
          ),
        ),

        const _Header('Compte'),
        ListTile(
          leading: const Icon(Icons.email_outlined, color: AppColors.primary),
          title: const Text('Changer d\'adresse email'),
          subtitle: Text(email, style: const TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
          onTap: () => _changeEmail(context),
        ),
        if (_isPasswordUser)
          ListTile(
            leading: const Icon(Icons.lock_outline, color: AppColors.primary),
            title: const Text('Changer mon mot de passe'),
            trailing: const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
            onTap: () => _changePassword(context),
          ),

        const _Header('Session'),
        ListTile(
          leading: const Icon(Icons.logout, color: Colors.orange),
          title: const Text('Se déconnecter'),
          onTap: () => _signOut(context, ref),
        ),
        ListTile(
          leading: const Icon(Icons.delete_forever_outlined, color: Colors.red),
          title: const Text('Supprimer mon compte',
              style: TextStyle(color: Colors.red)),
          onTap: () => _deleteAccount(context, ref),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  // ── Changer email ─────────────────────────────────────────────────────────
  Future<void> _changeEmail(BuildContext context) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Changer d\'adresse email'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Email actuel : ${user.email ?? '—'}',
              style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Nouvelle adresse email', isDense: true),
          ),
          const SizedBox(height: 8),
          const Text(
            'Un email de confirmation sera envoyé à la nouvelle adresse. '
            'La mise à jour prendra effet après validation.',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Annuler')),
          ElevatedButton(onPressed: () => Navigator.pop(dialogCtx, true), child: const Text('Envoyer')),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    try {
      final newEmail = ctrl.text.trim();
      await user.verifyBeforeUpdateEmail(newEmail);
      await FirebaseFirestore.instance.collection('users_raptech1').doc(user.uid).set({
        'email_change_history': FieldValue.arrayUnion([
          {'old_email': user.email, 'new_email': newEmail, 'requested_at': DateTime.now().toIso8601String()}
        ]),
      }, SetOptions(merge: true));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Email de confirmation envoyé. Vérifiez votre nouvelle boîte mail.'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : ${e.toString().replaceFirst('Exception: ', '')}'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  // ── Changer mot de passe (ré-auth en ligne) ───────────────────────────────
  Future<void> _changePassword(BuildContext context) async {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? error;
    bool loading = false;

    await showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Changer mon mot de passe'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: currentCtrl, obscureText: true,
                decoration: const InputDecoration(labelText: 'Mot de passe actuel', isDense: true)),
            const SizedBox(height: 10),
            TextField(controller: newCtrl, obscureText: true,
                decoration: const InputDecoration(labelText: 'Nouveau mot de passe', isDense: true)),
            const SizedBox(height: 10),
            TextField(controller: confirmCtrl, obscureText: true,
                decoration: const InputDecoration(labelText: 'Confirmer le nouveau', isDense: true)),
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            FilledButton(
              onPressed: loading ? null : () async {
                final current = currentCtrl.text;
                final next = newCtrl.text;
                if (current.isEmpty || next.isEmpty) { setS(() => error = 'Remplissez tous les champs.'); return; }
                if (next.length < 6) { setS(() => error = 'Min. 6 caractères.'); return; }
                if (next != confirmCtrl.text) { setS(() => error = 'Les mots de passe ne correspondent pas.'); return; }
                setS(() { loading = true; error = null; });
                try {
                  final cred = EmailAuthProvider.credential(email: user.email ?? '', password: current);
                  await user.reauthenticateWithCredential(cred);
                  await user.updatePassword(next);
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                      content: Text('Mot de passe mis à jour.'), backgroundColor: Colors.green));
                  }
                } on FirebaseAuthException catch (e) {
                  final msg = switch (e.code) {
                    'wrong-password' || 'invalid-credential' => 'Mot de passe actuel incorrect.',
                    'weak-password' => 'Nouveau mot de passe trop faible.',
                    'requires-recent-login' => 'Reconnectez-vous puis réessayez.',
                    _ => 'Erreur : ${e.code}',
                  };
                  setS(() { error = msg; loading = false; });
                } catch (_) {
                  setS(() { error = 'Erreur inattendue.'; loading = false; });
                }
              },
              child: loading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Mettre à jour'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Se déconnecter ────────────────────────────────────────────────────────
  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dlg) => AlertDialog(
        title: const Text('Se déconnecter ?'),
        content: const Text('Vous retournerez en mode hors ligne.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlg, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(dlg, true), child: const Text('Se déconnecter')),
        ],
      ),
    );
    if (ok != true) return;
    // Capturer le routeur AVANT les awaits : après signOut, ce widget est démonté
    // (firebaseUserProvider → null) donc context.mounted devient faux.
    final router = GoRouter.of(context);
    // (notif) Retirer le token FCM de CE compte AVANT le signOut (sinon
    // l'appareil continue de recevoir les notifs de l'ancien compte, et le
    // token reste collé dans son doc — le prochain compte ne pourra pas l'en
    // retirer, règles Firestore obligent).
    final outgoingUid = FirebaseAuth.instance.currentUser?.uid;
    if (outgoingUid != null) {
      try {
        await NotificationService().clearTokenForUser(outgoingUid);
      } catch (_) {}
    }
    await FirebaseAuth.instance.signOut();
    await ref.read(teamStateProvider.notifier).clearTeam();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_mode', 'offline');
    router.go('/welcome');
  }

  // ── Supprimer le compte (ré-auth EN LIGNE pour les comptes mot de passe) ──
  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    // ── Garde-fou : abonnement RÉCURRENT actif → bloquer (sinon la carte continue
    //    d'être débitée après la suppression). Le prépayé (à vie / N mois) n'a pas de
    //    débit récurrent → autorisé (avertissement plus bas).
    final sub = ref.read(subscriptionProvider).valueOrNull;
    final companySub = ref.read(companySubscriptionProvider).valueOrNull;
    final hasRecurringPersonal = sub.isActive && sub.isRecurring &&
        (sub?['stripe_subscription_id'] != null);
    final team = ref.read(teamStateProvider).valueOrNull;
    final isAdmin = team?.isAdmin ?? false;
    final hasRecurringTeam = isAdmin && companySub.isActive && companySub.isRecurring &&
        (companySub?['stripe_subscription_id'] != null);

    if (hasRecurringPersonal || hasRecurringTeam) {
      await showDialog<void>(
        context: context,
        builder: (dlg) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Expanded(child: Text('Abonnement actif')),
          ]),
          content: Text(
            hasRecurringTeam
                ? 'Votre équipe a un abonnement mensuel en cours. Annulez-le d\'abord '
                  '(sinon la carte continue d\'être débitée), puis revenez supprimer votre compte.'
                : 'Vous avez un abonnement en cours. Pour éviter d\'être encore débité, '
                  'annulez-le d\'abord via « Gérer l\'abonnement », puis revenez supprimer '
                  'votre compte.',
            style: const TextStyle(fontSize: 13),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dlg), child: const Text('Plus tard')),
            FilledButton.icon(
              icon: const Icon(Icons.manage_accounts_outlined, size: 18),
              label: const Text('Gérer l\'abonnement'),
              onPressed: () async {
                Navigator.pop(dlg);
                try {
                  // [PAUSED-STRIPE] IAP : gestion de l'abonnement via le store.
                  final url = Platform.isIOS
                      ? 'https://apps.apple.com/account/subscriptions'
                      : 'https://play.google.com/store/account/subscriptions';
                  await SubscriptionService.openUrl(url);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Erreur : ${e.toString().replaceFirst('Exception: ', '')}')));
                  }
                }
              },
            ),
          ],
        ),
      );
      return;  // on NE supprime PAS tant qu'un abonnement récurrent est actif
    }

    // (#2) CEO/admin avec d'AUTRES membres → on bloque : supprimer son compte
    // laisserait l'équipe sans responsable (ni gestion, ni paiement). Il doit
    // d'abord retirer tous les membres ; ils pourront recréer leur propre équipe.
    if (isAdmin && team?.companyId != null) {
      int others = 0;
      try {
        final members = await TeamService().getMembers(team!.companyId!);
        others = members.where((m) => m.uid != user.uid).length;
      } catch (_) {}
      if (others > 0 && context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (dlg) => AlertDialog(
            icon: Icon(Icons.groups_outlined, color: Colors.orange.shade700),
            title: const Text('Retirez d\'abord votre équipe'),
            content: Text(
              'Vous êtes le responsable d\'une équipe ($others autre(s) membre(s)). '
              'Supprimer votre compte les laisserait sans responsable.\n\n'
              'Retirez d\'abord tous les membres (onglet Équipe → Gérer), puis '
              'revenez supprimer votre compte. Ils pourront alors créer leur '
              'propre équipe.',
              style: const TextStyle(fontSize: 13),
            ),
            actions: [
              FilledButton(
                  onPressed: () => Navigator.pop(dlg),
                  child: const Text('Compris')),
            ],
          ),
        );
        return; // on NE supprime PAS tant que l'équipe a d'autres membres
      }
    }

    // Prépayé (à vie / N mois) ou aucun abonnement : avertir s'il reste un accès prépayé.
    final hasPrepaid = (sub.isActive && !sub.isRecurring);
    final confirmCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dlg) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Supprimer mon compte'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Cette action est irréversible. Toutes vos données seront supprimées.',
                style: TextStyle(fontSize: 13)),
            if (hasPrepaid) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '⚠️ Vous avez un accès prépayé (à vie ou plusieurs mois) encore valable. '
                  'Il sera définitivement perdu, sans remboursement.',
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Text('Tapez DELETE pour confirmer :',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(
              controller: confirmCtrl,
              autofocus: true,
              onChanged: (_) => setS(() {}),
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), hintText: 'DELETE'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: confirmCtrl.text == 'DELETE' ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Supprimer définitivement'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    final uid = user.uid;
    try {
      await _runDelete(context, ref, uid);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        // Ré-auth EN LIGNE : si compte mot de passe → demander le mot de passe et réessayer,
        // sinon (Google/Apple) → fallback déconnexion + message.
        if (_isPasswordUser && context.mounted) {
          final pwd = await _promptPassword(context);
          if (pwd == null) return;
          try {
            final cred = EmailAuthProvider.credential(email: user.email ?? '', password: pwd);
            await user.reauthenticateWithCredential(cred);
            if (context.mounted) await _runDelete(context, ref, uid);
          } on FirebaseAuthException catch (e2) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(e2.code == 'wrong-password' || e2.code == 'invalid-credential'
                    ? 'Mot de passe incorrect.' : 'Erreur : ${e2.code}'),
                backgroundColor: Colors.red));
            }
          }
        } else {
          await FirebaseAuth.instance.signOut();
          await ref.read(teamStateProvider.notifier).clearTeam();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Session expirée. Reconnectez-vous et réessayez de supprimer votre compte.'),
              duration: Duration(seconds: 5)));
            context.go('/auth?mode=login');
          }
        }
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : ${e.message}')));
      }
    }
  }

  Future<String?> _promptPassword(BuildContext context) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dlg) => AlertDialog(
        title: const Text('Confirmez votre mot de passe'),
        content: TextField(
          controller: ctrl, obscureText: true, autofocus: true,
          decoration: const InputDecoration(labelText: 'Mot de passe', isDense: true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlg), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(dlg, ctrl.text), child: const Text('Confirmer')),
        ],
      ),
    );
  }

  Future<void> _runDelete(BuildContext context, WidgetRef ref, String uid) async {
    final router = GoRouter.of(context);  // capturé avant la suppression (widget démonté après)
    final team = ref.read(teamStateProvider).valueOrNull;
    final companyId = team?.companyId;
    if (companyId != null) {
      // Retire le doc membre du CEO (il ne peut pas se retirer via l'UI normale).
      try { await TeamService().leaveCompany(companyId, uid); } catch (_) {}
      // (#2) CEO = dernier membre (les autres ont déjà été retirés, cf. garde-fou)
      // → on DISSOUT l'équipe (supprime le doc company) pour ne pas laisser un
      // doc orphelin sans responsable.
      if (team!.isAdmin) {
        try {
          await FirebaseFirestore.instance
              .collection('companies_raptech1')
              .doc(companyId)
              .delete();
        } catch (_) {}
      }
    }
    try {
      await FirebaseFirestore.instance.collection('users_raptech1').doc(uid).delete();
    } catch (_) {}
    await user.delete();
    await ref.read(teamStateProvider.notifier).clearTeam(removeLink: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_mode', 'offline');
    router.go('/welcome');
  }
}

class _Header extends StatelessWidget {
  final String label;
  const _Header(this.label);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(label.toUpperCase(),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black54)),
    );
  }
}
