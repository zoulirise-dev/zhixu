import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zhixu_prototype/ui/image_preview.dart';
import 'package:zhixu_prototype/ui/localization.dart';
import 'package:zhixu_prototype/ui/theme.dart';
import 'package:zhixu_prototype/main.dart';
import 'package:zhixu_prototype/core/git_service.dart';

void main() {
  for (final language in ['中文', 'English']) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'image controls and compact checkbox: $language $brightness',
        (tester) async {
          uiLanguage = language;
          addTearDown(() => uiLanguage = '中文');
          await tester.pumpWidget(
            MaterialApp(
              theme: workspaceTheme(brightness),
              home: Scaffold(
                body: Column(
                  children: [
                    CompactCheckbox(value: true, onChanged: (_) {}),
                    Expanded(
                      child: ImagePreview(
                        bytes: File('assets/AppIcon.png').readAsBytesSync(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.text(language == 'English' ? 'Fit to window' : '适应窗口'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          final tooltip = Theme.of(tester.element(find.byType(ImagePreview)))
              .tooltipTheme;
          expect(
            tooltip.textStyle!.color,
            brightness == Brightness.dark ? Colors.black : Colors.white,
          );
          expect(
            find.byWidgetPredicate(
              (w) => w is MouseRegion && w.cursor == SystemMouseCursors.grab,
            ),
            findsOneWidget,
          );
        },
      );
    }
  }
  testWidgets('app language updates built-in material localization live', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ZhixuPrototype(service: GitService()));
    await tester.pumpAndSettle();
    uiLanguage = 'English';
    await tester.pumpAndSettle();
    var context = tester.element(find.byType(WorkspacePage));
    expect(MaterialLocalizations.of(context).copyButtonLabel, 'Copy');
    uiLanguage = '中文';
    await tester.pumpAndSettle();
    context = tester.element(find.byType(WorkspacePage));
    expect(MaterialLocalizations.of(context).copyButtonLabel, '复制');
    await tester.pumpWidget(const SizedBox());
  });
  test('operation and error messages translate', () {
    uiLanguage = 'English';
    addTearDown(() => uiLanguage = '中文');
    expect(tr('正在读取提交详情…'), 'Loading commit details…');
    expect(tr('文件不是 UTF-8 编码。'), 'File is not UTF-8 encoded.');
  });
}
