import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/services/account_switch_guard.dart';

enum _AuthMode { login, register }

class AuthScreen extends StatefulWidget {
  final bool startInLoginMode;
  const AuthScreen({super.key, this.startInLoginMode = false});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();

  late _AuthMode _mode = widget.startInLoginMode ? _AuthMode.login : _AuthMode.register;
  bool _loading = false;
  bool _obscure = true;
  bool _marketing = false; // (1.6) opt-in marketing à l'inscription
  String? _error;

  // Apple Sign-In — Service ID created in Apple Developer Portal
  // → must match what's configured in Firebase Console → Auth → Apple provider
  // Redirect URI = https://{firebase-project-id}.firebaseapp.com/__/auth/handler
  static const _appleServiceId = 'com.tec.reportnew1cld.signin';
  static const _appleRedirectUri =
      'https://smallfun.firebaseapp.com/__/auth/handler';

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _displayName.dispose();
    super.dispose();
  }

  // ── Post sign-in routing ──────────────────────────────────────────────────

  /// Routes after any successful sign-in.
  /// If a team_intent is pending (set before redirect to auth), goes to /team-setup.
  Future<void> _afterSignIn() async {
    // (4a/4c) Purge l'identité entreprise locale si c'est un autre compte.
    await AccountSwitchGuard.ensureCleanFor(
        FirebaseAuth.instance.currentUser?.uid);
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final teamIntent = prefs.getString('team_intent');
    if (!mounted) return;
    if (teamIntent != null) {
      context.go('/team-setup');
    } else {
      context.go('/home');
    }
  }

  // ── Firestore user document ───────────────────────────────────────────────

  /// Creates users_raptech1/{uid} on first sign-in; updates email/name on return.
  Future<void> _ensureUserDoc(User user, String provider) async {
    try {
      final ref = FirebaseFirestore.instance
          .collection('users_raptech1')
          .doc(user.uid);
      final snap = await ref.get();
      if (!snap.exists) {
        final now = DateTime.now();
        await ref.set({
          'subscription_tier': 'free',
          'subscription_platform': null,
          'subscription_expires_at': null,
          'monthly_exports_used': 0,
          'monthly_exports_reset':
              Timestamp.fromDate(DateTime(now.year, now.month, 1)),
          'email': user.email ?? '',
          'display_name': user.displayName ?? '',
          'auth_provider': provider,
          // (1.6) opt-in marketing coché à l'inscription (doc neuf = inscription).
          'marketing_consent': _marketing,
          'marketing_consent_at':
              _marketing ? FieldValue.serverTimestamp() : null,
          'created_at': FieldValue.serverTimestamp(),
        });
      } else {
        await ref.update({
          'email': user.email ?? '',
          'display_name': user.displayName ?? '',
        });
      }
    } catch (_) {
      // Non-fatal — subscription check will create doc lazily if needed
    }
  }

  // ── Email / password ──────────────────────────────────────────────────────

  // (F) Un email ne contient JAMAIS d'espace : on retire TOUS les blancs ET les
  // caractères invisibles (espaces insécables, zero-width…) souvent introduits
  // par un copier-coller — ils faisaient échouer l'inscription « alors que ça a
  // l'air bon visuellement ».
  String get _cleanEmail => _email.text
      // espaces, tabs, retours + espace insécable (U+00A0) + zero-width
      // (U+200B–U+200D, U+2060, U+FEFF).
      .replaceAll(RegExp('[\\s ​-‍⁠﻿]'), '');

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      UserCredential cred;
      if (_mode == _AuthMode.register) {
        cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _cleanEmail,
          password: _password.text,
        );
        await cred.user?.updateDisplayName(_displayName.text.trim());
        await cred.user?.reload();
      } else {
        cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _cleanEmail,
          password: _password.text,
        );
      }
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) await _ensureUserDoc(user, 'email');
      await _afterSignIn();
    } on FirebaseAuthException catch (e) {
      setState(() { _error = _friendlyError(e.code); });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<void> _resetPassword() async {
    if (_email.text.trim().isEmpty) {
      setState(() {
        _error = 'Entrez votre email pour réinitialiser le mot de passe.';
      });
      return;
    }
    try {
      await FirebaseAuth.instance
          .sendPasswordResetEmail(email: _email.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email de réinitialisation envoyé.')),
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() { _error = _friendlyError(e.code); });
    }
  }

  // ── Google Sign-In ────────────────────────────────────────────────────────

  Future<void> _signInWithGoogle() async {
    setState(() { _loading = true; _error = null; });
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        // User cancelled
        setState(() { _loading = false; });
        return;
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final result =
          await FirebaseAuth.instance.signInWithCredential(credential);
      final user = result.user;
      if (user != null) await _ensureUserDoc(user, 'google');
      await _afterSignIn();
    } on FirebaseAuthException catch (e) {
      setState(() { _error = _friendlyError(e.code); });
    } catch (e) {
      setState(() { _error = 'Connexion Google échouée. Réessayez.'; });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  // ── Apple Sign-In ─────────────────────────────────────────────────────────

  Future<void> _signInWithApple() async {
    setState(() { _loading = true; _error = null; });
    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        webAuthenticationOptions: WebAuthenticationOptions(
          clientId: _appleServiceId,
          redirectUri: Uri.parse(_appleRedirectUri),
        ),
      );
      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );
      final result =
          await FirebaseAuth.instance.signInWithCredential(oauthCredential);
      // Apple sends name ONLY on the very first sign-in — persist it immediately
      final user = result.user;
      if (user != null) {
        if (user.displayName == null || user.displayName!.isEmpty) {
          final given = appleCredential.givenName ?? '';
          final family = appleCredential.familyName ?? '';
          final fullName = '$given $family'.trim();
          if (fullName.isNotEmpty) {
            await user.updateDisplayName(fullName);
            await user.reload();
          }
        }
        await _ensureUserDoc(
            FirebaseAuth.instance.currentUser ?? user, 'apple');
      }
      await _afterSignIn();
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code != AuthorizationErrorCode.canceled) {
        setState(() { _error = 'Connexion Apple échouée. Réessayez.'; });
      }
    } on FirebaseAuthException catch (e) {
      setState(() { _error = _friendlyError(e.code); });
    } catch (e) {
      setState(() { _error = 'Connexion Apple échouée. Réessayez.'; });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  // ── Offline mode ──────────────────────────────────────────────────────────

  Future<void> _continueOffline(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_mode', 'offline');
    await prefs.setBool('onboarding_done', true);
    if (context.mounted) context.go('/home');
  }

  // ── Error messages ────────────────────────────────────────────────────────

  String _friendlyError(String code) => switch (code) {
        'email-already-in-use' => 'Cet email est déjà utilisé.',
        'invalid-email' => 'Email invalide.',
        'weak-password' => 'Mot de passe trop faible (min. 6 caractères).',
        'user-not-found' ||
        'wrong-password' ||
        'invalid-credential' =>
          'Email ou mot de passe incorrect.',
        'too-many-requests' => 'Trop de tentatives. Réessayez plus tard.',
        'network-request-failed' => 'Pas de connexion internet.',
        _ => 'Erreur : $code',
      };

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isRegister = _mode == _AuthMode.register;

    return Scaffold(
      backgroundColor: AppColors.primary,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(isRegister ? 'Créer un compte' : 'Connexion'),
        actions: [
          TextButton(
            onPressed: () => _continueOffline(context),
            child: const Text(
              'Sans compte',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),

                // ── Email / password form ─────────────────────────────
                if (isRegister) ...[
                  _Field(
                    controller: _displayName,
                    label: 'Votre prénom / nom',
                    icon: Icons.person_outline,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Champ requis' : null,
                  ),
                  const SizedBox(height: 14),
                ],
                _Field(
                  controller: _email,
                  label: 'Email',
                  icon: Icons.email_outlined,
                  keyboard: TextInputType.emailAddress,
                  validator: (v) {
                    final email = (v ?? '').trim();
                    // Format basique nom@domaine.tld — attrape "t3bbb", "t3bbb@", "t3bbb@g"
                    final re = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                    return re.hasMatch(email)
                        ? null
                        : 'Email invalide (ex : nom@domaine.com)';
                  },
                ),
                const SizedBox(height: 14),
                _Field(
                  controller: _password,
                  label: 'Mot de passe',
                  icon: Icons.lock_outline,
                  obscure: _obscure,
                  suffix: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility_off : Icons.visibility,
                      color: Colors.white70,
                    ),
                    onPressed: () =>
                        setState(() => _obscure = !_obscure),
                  ),
                  validator: (v) =>
                      (v == null || v.length < 6) ? 'Min. 6 caractères' : null,
                ),
                if (!isRegister) ...[
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _resetPassword,
                      child: const Text(
                        'Mot de passe oublié ?',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
                  ),
                ] else
                  const SizedBox(height: 14),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade700.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(_error!,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13)),
                  ),
                  const SizedBox(height: 8),
                ],
                if (isRegister) ...[
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () => setState(() => _marketing = !_marketing),
                    borderRadius: BorderRadius.circular(8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: _marketing,
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          checkColor: AppColors.primary,
                          fillColor: WidgetStateProperty.resolveWith(
                            (s) => s.contains(WidgetState.selected)
                                ? Colors.white
                                : Colors.white24,
                          ),
                          side: const BorderSide(color: Colors.white54),
                          onChanged: (v) =>
                              setState(() => _marketing = v ?? false),
                        ),
                        const SizedBox(width: 4),
                        const Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(top: 11),
                            child: Text(
                              'Je souhaite recevoir par email des offres, nouveautés '
                              'et bons plans (facultatif).',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 12.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.primary,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          isRegister ? 'Créer mon compte' : 'Se connecter',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      isRegister
                          ? 'Déjà un compte ? '
                          : 'Pas encore de compte ? ',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _mode = isRegister
                            ? _AuthMode.login
                            : _AuthMode.register;
                        _error = null;
                      }),
                      child: Text(
                        isRegister ? 'Se connecter' : 'Créer un compte',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),

                // ── Divider ───────────────────────────────────────────
                const SizedBox(height: 24),
                Row(children: [
                  Expanded(
                      child: Divider(
                          color: Colors.white.withValues(alpha: 0.25))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('ou',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 13)),
                  ),
                  Expanded(
                      child: Divider(
                          color: Colors.white.withValues(alpha: 0.25))),
                ]),
                const SizedBox(height: 16),

                // ── Continuer avec Google ─────────────────────────────
                _GoogleButton(
                  onPressed: _loading ? null : _signInWithGoogle,
                ),
                const SizedBox(height: 12),

                // ── Continuer avec Apple ──────────────────────────────
                // Required by Apple if other social sign-in options are shown
                _AppleButton(
                  onPressed: _loading ? null : _signInWithApple,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

// Google-branded button: white background, 4-color G icon, colored border.
class _GoogleButton extends StatelessWidget {
  final VoidCallback? onPressed;
  const _GoogleButton({required this.onPressed});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 52,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              colors: [
                Color(0xFF4285F4), // blue
                Color(0xFFEA4335), // red
                Color(0xFFFBBC04), // yellow
                Color(0xFF34A853), // green
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(2), // gradient border thickness
            child: ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF3C4043),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _GoogleGIcon(),
                  SizedBox(width: 10),
                  Text(
                    'Continuer avec Google',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

// Google G icon: 4-color circle with bold "G" letter on top.
// The 4 pie-slice sectors use the official Google brand colors,
// and the white "G" is rendered as text over them.
class _GoogleGIcon extends StatelessWidget {
  const _GoogleGIcon();

  @override
  Widget build(BuildContext context) => Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(26, 26),
            painter: _GoogleColorsPainter(),
          ),
          const Text(
            'G',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              height: 1.0,
            ),
          ),
        ],
      );
}

class _GoogleColorsPainter extends CustomPainter {
  static const _blue = Color(0xFF4285F4);
  static const _red = Color(0xFFEA4335);
  static const _yellow = Color(0xFFFBBC04);
  static const _green = Color(0xFF34A853);
  static const _pi = 3.14159265358979;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    final p = Paint()..style = PaintingStyle.fill;

    // Blue: top-right quadrant — widest segment (135°)
    p.color = _blue;
    canvas.drawArc(rect, _r(-45), _r(135), true, p);
    // Red: bottom-left (120°)
    p.color = _red;
    canvas.drawArc(rect, _r(90), _r(120), true, p);
    // Yellow: bottom (60°)
    p.color = _yellow;
    canvas.drawArc(rect, _r(210), _r(60), true, p);
    // Green: right-lower (45°)
    p.color = _green;
    canvas.drawArc(rect, _r(270), _r(45), true, p);
  }

  static double _r(double deg) => deg * _pi / 180.0;

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// Apple-branded button: black background, white apple icon, white text
class _AppleButton extends StatelessWidget {
  final VoidCallback? onPressed;
  const _AppleButton({required this.onPressed});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 52,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 1,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.apple, size: 24, color: Colors.white),
              SizedBox(width: 8),
              Text(
                'Continuer avec Apple',
                style: TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 15, color: Colors.white),
              ),
            ],
          ),
        ),
      );
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscure;
  final Widget? suffix;
  final TextInputType? keyboard;
  final String? Function(String?)? validator;

  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    this.obscure = false,
    this.suffix,
    this.keyboard,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboard,
      style: const TextStyle(color: Colors.white),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        prefixIcon: Icon(icon, color: Colors.white70),
        suffixIcon: suffix,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: Colors.white.withValues(alpha: 0.35)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        errorStyle: const TextStyle(color: Colors.orangeAccent),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.08),
      ),
    );
  }
}
