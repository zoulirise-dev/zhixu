import 'dart:io';
import 'dart:async';

import 'package:zhixu_prototype/ui/image_preview.dart';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:zhixu_prototype/main.dart';
import 'package:zhixu_prototype/ui/theme.dart';
import 'package:zhixu_prototype/ui/localization.dart';
import 'package:zhixu_prototype/core/workflows.dart';
import 'package:zhixu_prototype/core/git_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('desktop editing, refresh, save and selected commit', (
    tester,
  ) async {
    final temp = await Directory.systemTemp.createTemp('zhixu-desktop-');
    final root = p.join(temp.path, 'Task Garden');
    await Directory(root).create();
    final git = GitService(
      environment: {
        'GIT_CONFIG_GLOBAL': p.join(temp.path, 'global'),
        'GIT_CONFIG_NOSYSTEM': '1',
      },
    );
    await git.run(root, ['init', '-b', 'main']);
    await git.saveAuthor(root, 'Demo Developer', 'demo@example.invalid');
    await git.run(root, ['config', 'commit.gpgsign', 'false']);
    final file = File(p.join(root, 'tasks.js'));
    await file.writeAsString(
      '// 枝序 Flutter 原型\nconst title = "你好，枝序";\n\nfunction greet(name) {\n  return "Hello " + name;\n}\n',
    );
    await File(p.join(root, 'theme.js'))
        .writeAsString('const theme = "light";\n');
    await git.run(root, ['add', '.']);
    await git.run(root, ['commit', '-m', 'seed']);
    await file.writeAsString(
      '${await file.readAsString()}\nconst message = "一起验证跨平台";\n',
    );
    await File(p.join(root, 'theme.js'))
        .writeAsString('const theme = "system";\n');
    await git.run(root, ['add', 'theme.js']);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: ZhixuPrototype(initialPath: root, service: git),
      ),
    );
    Future<void> waitFor(Finder finder) async {
      for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(finder, findsWidgets);
      await tester.pumpAndSettle();
    }

    await waitFor(find.text('tasks.js'));
    await tester.tap(find.text('tasks.js').first);
    await tester.pumpAndSettle();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    final out = Directory(
      p.join(Directory.current.path, 'build', 'prototype-screenshots'),
    );
    await out.create(recursive: true);
    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 1.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(p.join(out.path, '$name.png'))
          .writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    }

    if (Platform.isMacOS) {
      final metrics = await const MethodChannel('app.zhixu/desktop')
          .invokeMapMethod<String, dynamic>('chromeMetrics')
          .timeout(const Duration(seconds: 10));
      expect(metrics!['height'], 45);
      expect((metrics['left'] as num) - (metrics['top'] as num), closeTo(0, 1));
    }
    await capture('changes');
    // Uncheck theme.js; it is already staged and must remain outside our commit.
    final row = find
        .ancestor(of: find.text('theme.js'), matching: find.byType(HoverRow))
        .first;
    await tester.tap(find.descendant(of: row, matching: find.byType(Checkbox)));
    await tester.tap(find.text('文件').first);
    await tester.pumpAndSettle();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('tasks.js').first);
    await tester.pumpAndSettle();
    await waitFor(find.byKey(const Key('code-input')));
    final field = tester.widget<TextField>(find.byKey(const Key('code-input')));
    final before = field.controller!.text;
    // This is programmatic composing-state coverage, not an OS candidate-window test.
    field.controller!.value = TextEditingValue(
      text: '${before}zhongwen',
      selection: TextSelection.collapsed(offset: before.length + 8),
      composing: TextRange(start: before.length, end: before.length + 8),
    );
    await tester.pump();
    final value = field.controller!.value;
    await tester.tap(find.byTooltip('刷新列表，保留编辑和勾选'));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(field.controller!.value, value);
    field.controller!.value = TextEditingValue(
      text: '$before// 中文输入验证完成',
      selection: TextSelection.collapsed(offset: before.length + 11),
    );
    await tester.pumpAndSettle();
    await capture('editor');
    await tester.tap(find.byTooltip('保存 ${Platform.isMacOS ? '⌘' : 'Ctrl'}+S'));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(await file.readAsString(), contains('中文输入验证完成'));
    await tester.tap(find.text('变更').first);
    await tester.pumpAndSettle();
    tester
            .widget<TextField>(find.byKey(const Key('commit-message')))
            .controller!
            .text =
        'prototype selected commit';
    await tester.pumpAndSettle();
    // onChanged drives button state, so invoke through the widget too.
    tester
        .widget<TextField>(find.byKey(const Key('commit-message')))
        .onChanged
        ?.call('prototype selected commit');
    await tester.pumpAndSettle();
    await tester.tap(find.text('提交'));
    await Future<void>.delayed(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(
      (await git.run(root, ['show', 'HEAD:theme.js'])).out,
      'const theme = "light";\n',
    );
    expect(
      (await git.run(root, ['show', ':theme.js'])).out,
      'const theme = "system";\n',
    );
    expect(
      (await git.run(root, ['show', 'HEAD:tasks.js'])).out,
      contains('中文输入验证完成'),
    );
    await tester.tap(find.text('历史').first);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await capture('history');
    await tester.tap(find.textContaining('prototype selected commit').first);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('提交详情'), findsOneWidget);
    await capture('commit-detail');
    Navigator.of(tester.element(find.byType(ZDialog))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('设置'));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('本项目提交署名'), findsOneWidget);
    await capture('settings');
    Future<double> titleOpacity() async {
      final metrics = await const MethodChannel('app.zhixu/desktop')
          .invokeMapMethod<String, dynamic>('chromeMetrics')
          .timeout(const Duration(seconds: 10));
      return (metrics!['modalOpacity'] as num).toDouble();
    }

    if (Platform.isMacOS) {
      expect(await titleOpacity(), closeTo(0x38 / 255, .01));
      unawaited(
        showDialog<void>(
          context: tester.element(find.byType(ZDialog)),
          barrierColor: const Color(0x38000000),
          builder: (_) =>
              const AlertDialog(content: Text('Nested barrier test')),
        ),
      );
      await tester.pumpAndSettle();
      expect(await titleOpacity(), greaterThan(.35));
      Navigator.of(tester.element(find.byType(AlertDialog))).pop();
      await tester.pumpAndSettle();
      expect(await titleOpacity(), closeTo(0x38 / 255, .01));
    }
    Navigator.of(tester.element(find.byType(ZDialog))).pop();
    await tester.pumpAndSettle();
    if (Platform.isMacOS) expect(await titleOpacity(), closeTo(0, .001));
    await git.stash(root, message: '验证备份列表');
    await tester.tap(find.text('变更').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('临时收起的修改…'));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('临时收起的修改'), findsOneWidget);
    await capture('backups');
    Navigator.of(tester.element(find.byType(ZDialog))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开项目').first);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('常用位置'), findsOneWidget);
    await capture('directory-picker');
    Navigator.of(tester.element(find.byType(ZDialog))).pop();
    await tester.pumpAndSettle();
    await File(p.join(root, 'preview.png'))
        .writeAsBytes(await File('assets/AppIcon.png').readAsBytes());
    final dynamic state = tester.state(find.byType(WorkspacePage));
    await state.openFile('preview.png', pin: true);
    await tester.pumpAndSettle();
    expect(find.byType(ImagePreview), findsOneWidget);
    expect(find.text('图片 · 只读'), findsOneWidget);
    await capture('image-preview');
    await File(p.join(root, 'long.dart')).writeAsString(
      List.generate(
        2500,
        (i) => '    final value$i = "long preview line $i";',
      ).join('\n'),
    );
    await state.openFile('long.dart', pin: true);
    await tester.pumpAndSettle();
    await capture('long-editor');
    await state.openFile('long.dart', change: const Change('long.dart', '??'));
    await tester.pumpAndSettle();
    await capture('long-diff');
    await Directory(p.join(root, '.ignored-cache')).create();
    await File(p.join(root, '.ignored-cache', 'cache-image.txt'))
        .writeAsString('ignored content');
    await File(p.join(root, '.gitignore')).writeAsString('.ignored-cache/\n');
    await state.refresh();
    await tester.tap(find.text('文件').first);
    await tester.pumpAndSettle();
    Future<void> expectFileColor(String name, Color color) async {
      final finder = find.byWidgetPredicate(
        (w) => w is MiddleText && w.text == name,
      );
      for (var i = 0; i < 60; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
        if (finder.evaluate().isNotEmpty &&
            tester.widget<MiddleText>(finder.first).style.color == color) {
          break;
        }
      }
      expect(finder, findsWidgets);
      expect(tester.widget<MiddleText>(finder.first).style.color, color);
    }

    await expectFileColor('.ignored-cache', Colors.grey);
    state.search.text = 'cache-image';
    await tester.pump();
    await expectFileColor('.ignored-cache/cache-image.txt', Colors.grey);
    await capture('ignored-search');
    state.search.clear();
    await tester.pumpAndSettle();
    await tester.tap(find.text('.ignored-cache').first);
    await expectFileColor('cache-image.txt', Colors.grey);
    await capture('ignored-files');
    await File(p.join(root, '.gitignore')).writeAsString('');
    await state.refresh();
    await expectFileColor('cache-image.txt', const Color(0xff007d36));

    await git.run(root, ['add', 'preview.png']);
    await git.run(root, ['commit', '-m', 'image preview']);
    await tester.tap(
      find.text(uiLanguage == 'English' ? 'History' : '历史').first,
    );
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('image preview').first);
    await waitFor(find.byType(GitImageComparison));
    await tester.pumpAndSettle();
    expect(find.byType(ImagePreview), findsOneWidget);
    expect(find.text('图片无法加载'), findsNothing);
    if (Platform.isMacOS) {
      final metrics = await const MethodChannel('app.zhixu/desktop')
          .invokeMapMethod<String, dynamic>('chromeMetrics')
          .timeout(const Duration(seconds: 10));
      expect(
        metrics!['menuLabels'],
        containsAll(['退出枝序', '最小化', '缩放窗口', '切换全屏']),
      );
      expect(metrics['menuLabels'], isNot(contains('Quit Zhixu Prototype')));
    }
    await capture('image-history-light-zh');
    Navigator.of(tester.element(find.byType(ZDialog))).pop();
    await tester.pumpAndSettle();
    uiLanguage = 'English';
    appearance.value = ThemeMode.dark;
    state.redraw();
    await tester.pumpAndSettle();
    await tester.tap(
      find.text(uiLanguage == 'English' ? 'History' : '历史').first,
    );
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('image preview').first);
    await waitFor(find.byType(GitImageComparison));
    await tester.pumpAndSettle();
    expect(find.text('Before'), findsOneWidget);
    expect(find.text('After'), findsOneWidget);
    expect(find.text('Unable to load image'), findsNothing);
    if (Platform.isMacOS) {
      final metrics = await const MethodChannel('app.zhixu/desktop')
          .invokeMapMethod<String, dynamic>('chromeMetrics')
          .timeout(const Duration(seconds: 10));
      expect(
        metrics!['menuLabels'],
        containsAll(['Quit Zhixu', 'Minimize', 'Zoom', 'Toggle Full Screen']),
      );
    }
    await capture('image-history-dark-en');
    Navigator.of(tester.element(find.byType(ZDialog))).pop();
    await tester.pumpAndSettle();
    uiLanguage = '中文';
    appearance.value = ThemeMode.system;
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await temp.delete(recursive: true);
  });
}
