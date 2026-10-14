// Anti-régression (2026-10-14) : kAppBuildNumber (comparé par le kill switch à
// min_build / latest_build de config/app_control) doit être ÉGAL au numéro de
// build de pubspec.yaml (« version: 1.2.0+20 » → 20). Il était resté à 14.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reportnew1cld/core/config/app_build.dart';

void main() {
  test('kAppBuildNumber == numéro de build de pubspec.yaml', () {
    final m = RegExp(r'^version:\s*[\d.]+\+(\d+)', multiLine: true)
        .firstMatch(File('pubspec.yaml').readAsStringSync());
    expect(m, isNotNull, reason: 'ligne « version: x.y.z+N » introuvable');
    expect(kAppBuildNumber, int.parse(m!.group(1)!),
        reason: 'mettre à jour kAppBuildNumber dans lib/core/config/app_build.dart');
  });
}
