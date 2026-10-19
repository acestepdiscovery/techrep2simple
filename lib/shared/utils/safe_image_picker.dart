import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:image_picker/image_picker.dart';

import 'error_text.dart';

/// (2026-10-19) Choisir / prendre une photo SANS échec silencieux : si l'accès
/// aux photos ou à l'appareil photo a été refusé (fréquent sur iPhone), le
/// sélecteur lève une erreur → avant, le bouton ne faisait rien, sans message.
/// Renvoie null (et explique quoi faire) en cas d'échec.
Future<XFile?> pickImageSafe(
  BuildContext context, {
  required ImageSource source,
  int? imageQuality,
  double? maxWidth,
  double? maxHeight,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    return await ImagePicker().pickImage(
      source: source,
      imageQuality: imageQuality,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
    );
  } catch (e) {
    final code = e is PlatformException ? e.code.toLowerCase() : '';
    messenger?.showSnackBar(SnackBar(
      content: Text(code.contains('denied') || code.contains('access')
          ? 'photo_access_denied'.tr()
          : 'common_error'.tr(args: [errorText(e)])),
      duration: const Duration(seconds: 6),
    ));
    return null;
  }
}
