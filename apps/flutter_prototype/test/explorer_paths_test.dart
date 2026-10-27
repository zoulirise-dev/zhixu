import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:zhixu_prototype/main.dart';
import 'package:zhixu_prototype/core/git_service.dart';
import 'package:zhixu_prototype/ui/theme.dart';
import 'package:zhixu_prototype/ui/localization.dart';

class TreeGit extends GitService {
  @override
  Future<Set<String>> ignoredPaths(String root, Iterable<String> paths) async =>
      paths.where((name) => name == 'route/debug.log').toSet();
}

void main() {
  for (final language in ['中文', 'English']) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'nested file badges and repository keys $language $brightness',
        (tester) async {
          uiLanguage = language;
          final dir = Directory.systemTemp.createTempSync('zhixu-tree-');
          addTearDown(() async {
            uiLanguage = '中文';
            dir.deleteSync(recursive: true);
          });
          Directory(p.join(dir.path, 'route')).createSync();
          File(p.join(dir.path, 'route', 'app.php')).writeAsStringSync('<?php');
          File(p.join(dir.path, 'route', 'debug.log')).writeAsStringSync('log');
          String? opened;
          await tester.runAsync(() async {
            await tester.pumpWidget(
              MaterialApp(
                theme: workspaceTheme(brightness),
                home: Scaffold(
                  body: ExplorerTree(
                    root: dir.path,
                    git: TreeGit(),
                    revision: 0,
                    filter: '',
                    changes: const [Change('route/app.php', ' M')],
                    onOpen: (path) => opened = path,
                    onPin: (_) {},
                    onSelect: (_) {},
                    onContext: (_, _, _) {},
                    onClipboard: (_, _) {},
                    onMultiSelect: (_) {},
                  ),
                ),
              ),
            );
            await Future<void>.delayed(const Duration(milliseconds: 200));
          });
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            await tester.tap(find.text('route'));
            await Future<void>.delayed(const Duration(milliseconds: 200));
          });
          await tester.pumpAndSettle();
          expect(find.text('app.php'), findsOneWidget);
          final row = find.ancestor(
            of: find.text('app.php'),
            matching: find.byType(InkWell),
          );
          expect(
            tester.widget<InkWell>(row).mouseCursor,
            SystemMouseCursors.click,
          );
          expect(find.text('M'), findsOneWidget);
          expect(
            tester.widget<Text>(find.text('app.php')).style!.color,
            changeBadgeColor('M'),
          );
          expect(
            tester.widget<Text>(find.text('debug.log')).style!.color,
            Colors.grey,
          );
          await tester.tap(find.text('app.php'));
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pumpAndSettle();
          expect(opened, 'route/app.php');
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
