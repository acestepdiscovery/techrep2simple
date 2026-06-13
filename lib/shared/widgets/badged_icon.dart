import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

/// Technique "2 icônes en 1" : un [Stack] superpose une icône de base et un
/// petit badge en coin (cf. QUICK_TIPS.md). Réutilisable pour Clients (« C »),
/// Profil (« P »), Accueil (flèche retour), etc.
///
/// - [base] : l'icône principale (déjà dimensionnée).
/// - [badge] : le petit widget affiché en coin (lettre, mini-icône…).
/// - [size] : sert à positionner/dimensionner le badge proportionnellement.
class BadgedIcon extends StatelessWidget {
  final Widget base;
  final Widget badge;
  final double size;
  final double right;
  final double bottom;
  const BadgedIcon({
    super.key,
    required this.base,
    required this.badge,
    this.size = 24,
    this.right = -2,
    this.bottom = -1,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        base,
        Positioned(right: right, bottom: bottom, child: badge),
      ],
    );
  }
}

/// Badge circulaire contenant une lettre (ex. « C », « P »).
class LetterBadge extends StatelessWidget {
  final String letter;
  final double size; // = la taille de l'icône hôte
  final Color color;
  const LetterBadge({
    super.key,
    required this.letter,
    this.size = 24,
    this.color = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size * 0.5,
      height: size * 0.5,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Text(
        letter,
        style: TextStyle(
          fontSize: size * 0.34,
          height: 1,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Icône "Profil" = avatar + badge « P ». Distincte de l'icône Clients (« C »).
class ProfileIcon extends StatelessWidget {
  final bool selected;
  final double size;
  const ProfileIcon({super.key, this.selected = false, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return BadgedIcon(
      size: size,
      base: Icon(
        selected ? Icons.account_circle : Icons.account_circle_outlined,
        size: size,
      ),
      badge: LetterBadge(letter: 'P', size: size),
    );
  }
}

/// Icône "Accueil" (maison) + petit badge flèche-retour, pour signifier
/// "revenir à la page de garde".
class HomeBackIcon extends StatelessWidget {
  final double size;
  const HomeBackIcon({super.key, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return BadgedIcon(
      size: size,
      base: Icon(Icons.home_outlined, size: size),
      badge: Container(
        width: size * 0.5,
        height: size * 0.5,
        alignment: Alignment.center,
        decoration:
            const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
        child: Icon(Icons.arrow_back, size: size * 0.34, color: Colors.white),
      ),
    );
  }
}
