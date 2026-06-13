import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── Debug nav-pill options (kDebugMode only) ───────────────────────────────────
// Multi-highlight: highlight all section pills whose header is visible on screen.
final debugNavMultiHighlightProvider = StateProvider<bool>((ref) => false);
// Extra bottom pad: adds 400 px at the bottom so last sections can scroll past threshold.
final debugNavExtraBottomPadProvider = StateProvider<bool>((ref) => false);
