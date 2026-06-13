import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

/// Aperçu PDF avec zoom GARANTI (boutons +/− ET pinch ET pan). On rastérise les
/// pages en images et on les affiche dans un `InteractiveViewer` (`constrained:
/// false`) → on déplace (1 doigt) et on zoome (pinch / boutons). Le `PdfPreview`
/// natif ne zoomait pas de façon fiable (surtout sur émulateur).
class ZoomablePdfView extends StatefulWidget {
  final Uint8List bytes;
  final String title;
  const ZoomablePdfView({
    super.key,
    required this.bytes,
    this.title = 'Aperçu PDF',
  });

  @override
  State<ZoomablePdfView> createState() => _ZoomablePdfViewState();
}

class _ZoomablePdfViewState extends State<ZoomablePdfView> {
  final _tc = TransformationController();
  final List<Uint8List> _pages = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await for (final page in Printing.raster(widget.bytes, dpi: 150)) {
        final png = await page.toPng();
        if (!mounted) return;
        setState(() => _pages.add(png));
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _zoom(double factor) {
    _tc.value = _tc.value.clone()..scaleByDouble(factor, factor, factor, 1);
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Dézoomer',
            icon: const Icon(Icons.zoom_out),
            onPressed: _pages.isEmpty ? null : () => _zoom(1 / 1.3),
          ),
          IconButton(
            tooltip: 'Zoomer',
            icon: const Icon(Icons.zoom_in),
            onPressed: _pages.isEmpty ? null : () => _zoom(1.3),
          ),
          IconButton(
            tooltip: 'Réinitialiser le zoom',
            icon: const Icon(Icons.center_focus_strong_outlined),
            onPressed:
                _pages.isEmpty ? null : () => _tc.value = Matrix4.identity(),
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Erreur d\'aperçu : $_error',
                    textAlign: TextAlign.center),
              ),
            )
          : (_pages.isEmpty && _loading)
              ? const Center(child: CircularProgressIndicator())
              : InteractiveViewer(
                  transformationController: _tc,
                  minScale: 0.4,
                  maxScale: 6,
                  constrained: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: _pages
                        .map((p) => Padding(
                              padding: const EdgeInsets.all(6),
                              child: Image.memory(p, width: width),
                            ))
                        .toList(),
                  ),
                ),
    );
  }
}
