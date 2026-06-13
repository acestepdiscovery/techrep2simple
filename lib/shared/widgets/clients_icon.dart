import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

/// Icône "Clients" = carte contact + petit badge « C » en coin, pour bien la
/// distinguer de l'icône "profil" (deux personnes). [selected] remplit l'icône.
class ClientsIcon extends StatelessWidget {
  final bool selected;
  final double size;
  const ClientsIcon({super.key, this.selected = false, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(selected ? Icons.contacts : Icons.contacts_outlined, size: size),
        Positioned(
          right: -2,
          bottom: -1,
          child: Container(
            width: size * 0.5,
            height: size * 0.5,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: Text(
              'C',
              style: TextStyle(
                fontSize: size * 0.34,
                height: 1,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
