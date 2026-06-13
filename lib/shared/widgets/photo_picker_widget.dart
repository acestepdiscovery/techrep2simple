import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/app_colors.dart';

class PhotoPickerWidget extends StatelessWidget {
  final List<XFile> photos;
  final void Function(XFile) onAdd;
  final void Function(int) onRemove;

  const PhotoPickerWidget({
    super.key,
    required this.photos,
    required this.onAdd,
    required this.onRemove,
  });

  Future<void> _pick(BuildContext context, ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1920,
    );
    if (picked != null) onAdd(picked);
  }

  void _showOptions(BuildContext context) {
    if (kIsWeb) {
      _pick(context, ImageSource.gallery);
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppColors.primary),
              title: const Text('Prendre une photo'),
              onTap: () { Navigator.pop(context); _pick(context, ImageSource.camera); },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppColors.primary),
              title: const Text('Galerie photo'),
              onTap: () { Navigator.pop(context); _pick(context, ImageSource.gallery); },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) {
      return OutlinedButton.icon(
        onPressed: () => _showOptions(context),
        icon: const Icon(Icons.add_a_photo),
        label: const Text('Ajouter des photos'),
      );
    }
    return SizedBox(
      height: 106,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 3),
        itemCount: photos.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          if (i == photos.length) {
            return _AddMoreButton(onTap: () => _showOptions(context));
          }
          return _Thumbnail(xFile: photos[i], onRemove: () => onRemove(i));
        },
      ),
    );
  }
}

class _AddMoreButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddMoreButton({required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 90,
          height: 100,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.5), width: 1.5),
            borderRadius: BorderRadius.circular(10),
            color: AppColors.primary.withValues(alpha: 0.05),
          ),
          child: const Icon(Icons.add_a_photo_outlined, color: AppColors.primary, size: 28),
        ),
      );
}

class _Thumbnail extends StatelessWidget {
  final XFile xFile;
  final VoidCallback onRemove;
  const _Thumbnail({required this.xFile, required this.onRemove});

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: kIsWeb
                ? Image.network(xFile.path, width: 90, height: 100, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const _PhotoError())
                : Image.file(File(xFile.path), width: 90, height: 100, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const _PhotoError()),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                child: const Icon(Icons.close, size: 13, color: Colors.white),
              ),
            ),
          ),
        ],
      );
}

class _PhotoError extends StatelessWidget {
  const _PhotoError();
  @override
  Widget build(BuildContext context) => Container(
        width: 90,
        height: 100,
        color: Colors.grey.shade200,
        child: const Icon(Icons.broken_image, color: Colors.grey),
      );
}
