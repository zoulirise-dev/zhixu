import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zhixu_prototype/core/directory_browser.dart';
import 'package:zhixu_prototype/ui/directory_picker.dart';
import 'package:zhixu_prototype/ui/localization.dart';
import 'package:zhixu_prototype/ui/theme.dart';

void main() {
  test('drive mask and Windows roots preserve drive letters and UNC paths', () {
    expect(windowsDrivesFromMask(60), ['C:\\', 'D:\\', 'E:\\', 'F:\\']);
    final b = DirectoryBrowser(windows: true, home: r'C:\Users\demo');
    expect(b.normalize(' D: ', b.home), 'D:\\');
    expect(b.normalize('E:/project', b.home), r'E:\project');
    expect(b.normalize(r'\\server\share\repo', b.home), r'\\server\share\repo');
    expect(b.isRoot('C:\\'), isTrue);
  });
  test('native Windows drive enumeration and root listing', () async {
    final b = DirectoryBrowser();
    final drives = await b.drives();
    expect(drives, contains('C:\\'));
    expect(await b.folders('C:\\'), isNotEmpty);
  }, skip: !Platform.isWindows);
  for (final language in ['中文', 'English']) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'Windows drives, permission recovery and close button $language $brightness',
        (tester) async {
          debugDefaultTargetPlatformOverride = TargetPlatform.windows;
          uiLanguage = language;
          addTearDown(() {
            debugDefaultTargetPlatformOverride = null;
            uiLanguage = '中文';
          });
          tester.view.physicalSize = const Size(1000, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final browser = DirectoryBrowser(
            windows: true,
            home: r'C:\Users\demo',
            driveLoader: () async => ['C:\\', 'D:\\', 'E:\\', 'F:\\'],
            folderLoader: (path) async {
              if (path == 'C:\\') {
                throw const FileSystemException(
                  'denied',
                  '',
                  OSError('access denied', 5),
                );
              }
              return path == 'D:\\' ? [r'D:\project'] : [];
            },
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: workspaceTheme(brightness),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) =>
                          DirectoryPicker(title: '打开项目', browser: browser),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
          final close = find.byKey(const Key('windows-dialog-close'));
          expect(
            tester.getCenter(close).dx,
            greaterThan(tester.getCenter(find.text(tr('打开项目'))).dx),
          );
          expect(
            Theme.of(tester.element(close)).textTheme.bodyMedium!.fontFamily,
            'Segoe UI',
          );
          expect(codeFontFamily, 'Consolas');
          await tester.tap(find.text(tr('此电脑')));
          await tester.pumpAndSettle();
          for (final drive in ['C:\\', 'D:\\', 'E:\\', 'F:\\']) {
            expect(find.text(drive), findsOneWidget);
          }
          await tester.tap(find.text('C:\\'));
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pumpAndSettle();
          expect(find.text(tr('无法读取此文件夹，请检查访问权限后重试。')), findsOneWidget);
          final choose = tester.widget<ZButton>(
            find.widgetWithText(ZButton, tr('选择文件夹')),
          );
          expect(choose.onTap, isNull);
          await tester.tap(find.text(tr('此电脑')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('D:\\'));
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pumpAndSettle();
          expect(find.text('project'), findsOneWidget);
          await tester.tap(find.text('project'));
          await tester.pumpAndSettle();
          expect(find.text(r'D:\project'), findsWidgets);
          expect(
            tester
                .widget<ZButton>(find.widgetWithText(ZButton, tr('选择文件夹')))
                .onTap,
            isNotNull,
          );
          await tester.tap(find.text(tr('上一级')));
          await tester.pumpAndSettle();
          await tester.tap(find.text(tr('上一级')));
          await tester.pumpAndSettle();
          expect(find.text('F:\\'), findsOneWidget);
          await tester.tap(close);
          await tester.pumpAndSettle();
          expect(find.byType(DirectoryPicker), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          debugDefaultTargetPlatformOverride = null;
        },
      );
    }
  }
}
