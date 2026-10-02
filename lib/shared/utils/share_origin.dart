import 'package:flutter/material.dart';

/// Anchor rect for the iOS/iPad share popover (UIActivityViewController).
///
/// Sur iPhone/Android la feuille de partage s'affiche depuis le bas et ce
/// paramètre est ignoré. Sur **iPad**, iOS présente le partage en *popover* et
/// **exige** un rectangle d'ancrage : sans lui, `Share.share` / `Share.shareXFiles`
/// (et `Printing.sharePdf`) **plantent** sur iPad.
///
/// Usage :
///   Share.share(text, sharePositionOrigin: shareOrigin(context));
///   Printing.sharePdf(bytes: bytes, bounds: shareOrigin(context));
///
/// Renvoie `null` si le contexte n'a pas encore de taille (sans risque : sur
/// iPhone/Android `null` est correct ; le crash iPad n'arrive que si le popover
/// est réellement présenté, ce qui suppose une UI déjà mesurée).
Rect? shareOrigin(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}
