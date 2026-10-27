import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zhixu_prototype/main.dart';
import 'package:zhixu_prototype/ui/localization.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('specific translations win over generic suffix templates', () {
    uiLanguage = 'English';
    addTearDown(() => uiLanguage = '中文');
    expect(tr('待推送 12 条'), '12 to Push');
    expect(tr('待拉取 3 条'), '3 to Pull');
    expect(tr('待拉取 3 条 · 已分叉'), '3 to Pull · Diverged');
    for (final entry in english.entries) {
      final source = entry.key.replaceAllMapped(
        RegExp(r'\{(\d+)\}'),
        (m) => 'sample${m[1]}',
      );
      final expected = entry.value.replaceAllMapped(
        RegExp(r'\{(\d+)\}'),
        (m) => 'sample${m[1]}',
      );
      expect(tr(source), expected, reason: entry.key);
    }
    // A user's repository/branch name must not be translated as UI text.
    expect(tr('项目 · 我的项目'), 'Project · 我的项目');
  });
  test('About and footer version matches package version', () {
    final source = File('pubspec.yaml').readAsStringSync();
    expect(
      RegExp(r'^version: ([^+\s]+)', multiLine: true).firstMatch(source)![1],
      appVersion,
    );
  });
}
