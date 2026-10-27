import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:zhixu_prototype/ui/image_preview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zhixu_prototype/main.dart';
import 'package:zhixu_prototype/ui/theme.dart';
import 'package:zhixu_prototype/core/git_service.dart';
import 'package:zhixu_prototype/ui/code_editor.dart';

void main() {
  testWidgets(
    'change badges align regardless of filename and checkbox remains easy to click',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 860);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ZhixuPrototype(initialPath: '/demo', service: BadgeGit()),
      );
      await tester.pumpAndSettle();
      final badges = find.byType(ChangeBadge);
      expect(badges, findsNWidgets(3));
      final right = tester.getRect(badges.at(0)).right;
      for (var i = 1; i < 3; i++) {
        expect(tester.getRect(badges.at(i)).right, closeTo(right, .01));
      }
      expect(find.text('??'), findsNothing);
      expect(find.text('U'), findsOneWidget);
      final boxes = find.byType(CompactCheckbox);
      expect(
        tester.getCenter(boxes.first).dx,
        tester.getCenter(boxes.at(1)).dx,
      );
      final dynamic state = tester.state(find.byType(WorkspacePage));
      expect(state.checked.length, 3);
      await tester.tapAt(tester.getCenter(boxes.first) + const Offset(9, 0));
      await tester.pumpAndSettle();
      expect(state.checked, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test('status labels normalize Git porcelain and distinguish staging', () {
    expect(const Change('a', '??').badgeFor(), 'U');
    expect(const Change('a', 'MM').badgeFor(), 'M');
    expect(const Change('a', 'AM').badgeFor(staged: true), 'A');
    expect(const Change('a', 'AM').badgeFor(staged: false), 'M');
    expect(const Change('a', 'UU').badgeFor(), '!');
    expect(const Change('a', ' D').badgeFor(), 'D');
    expect(const Change('a', 'R ').badgeFor(), 'R');
  });

  testWidgets('image preview supports zoom reset and corrupt image fallback', (
    tester,
  ) async {
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aPa0AAAAASUVORK5CYII=',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ImagePreview(bytes: bytes)),
      ),
    );
    await tester.pumpAndSettle();
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    await tester.tap(find.byTooltip('放大'));
    await tester.pump();
    expect(
      viewer.transformationController!.value.getMaxScaleOnAxis(),
      greaterThan(1),
    );
    await tester.tap(find.text('适应窗口'));
    await tester.pump();
    expect(viewer.transformationController!.value.getMaxScaleOnAxis(), 1);
    expect(isPreviewImage('PHOTO.JPEG'), isTrue);
    expect(isPreviewImage('icon.svg'), isFalse);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ImagePreview(bytes: base64Decode('AAAA'))),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('图片无法加载'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'projects drag without switching or dropping the selected project',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 860);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ZhixuPrototype(initialPath: '/one', service: FakeGit()),
      );
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(WorkspacePage));
      await state.openProject('/two');
      await state.openProject('/three');
      await tester.pumpAndSettle();
      await tester.timedDrag(
        find.byKey(const ValueKey('project:/one')),
        const Offset(0, 220),
        const Duration(milliseconds: 800),
      );
      await tester.pumpAndSettle();
      expect(state.projects, ['/two', '/three', '/one']);
      expect(state.root, '/three');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Chinese composing ranges survive styling and parent rebuilds', (
    tester,
  ) async {
    final controller = CodeController(text: 'const name = "";\n');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CodeEditor(controller: controller)),
      ),
    );
    await tester.tap(find.byKey(const Key('code-input')));
    const composing = TextEditingValue(
      text: 'const name = "";\nnihao',
      selection: TextSelection.collapsed(offset: 21),
      composing: TextRange(start: 16, end: 21),
    );
    tester.testTextInput.updateEditingValue(composing);
    await tester.pump();
    expect(controller.value, composing);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CodeEditor(controller: controller)),
      ),
    );
    await tester.pump();
    expect(controller.value.composing, const TextRange(start: 16, end: 21));
    const committed = TextEditingValue(
      text: 'const name = "";\n你好',
      selection: TextSelection.collapsed(offset: 18),
    );
    tester.testTextInput.updateEditingValue(committed);
    await tester.pump();
    expect(controller.value, committed);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('workspace fits desktop and keeps editor on refresh', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ZhixuPrototype(initialPath: '/demo', service: FakeGit()),
    );
    await tester.pumpAndSettle();
    expect(find.text('工作区变更'), findsOneWidget);
    expect(find.text('提交'), findsOneWidget);
    final messageField = find.byKey(const Key('commit-message'));
    expect(tester.getSize(messageField).height, 59);
    expect(
      tester.widget<TextField>(messageField).textInputAction,
      TextInputAction.newline,
    );
    await tester.enterText(messageField, '修复预览\n\n支持多行提交说明\n第四行');
    await tester.pump();
    expect(
      tester.widget<TextField>(messageField).controller!.text,
      '修复预览\n\n支持多行提交说明\n第四行',
    );
    await tester.tap(find.text('文件').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

class FakeGit extends GitService {
  @override
  Future<GitReply> run(
    String root,
    List<String> args, {
    Map<String, String> env = const {},
    String? input,
    bool check = true,
    Duration timeout = const Duration(seconds: 45),
  }) async => throw GitFailure(FailureKind.other, 'fixture has no Git process');
  @override
  Future<String> open(String directory) async => directory;
  @override
  Future<List<Change>> changes(String root) async => [
    const Change('中文.txt', ' M'),
  ];
  @override
  Future<String> branch(String root) async => 'main';
  @override
  Future<List<String>> remotes(String root) async => [];
  @override
  Future<String> config(String root, String key) async => 'Demo';
}

class BadgeGit extends FakeGit {
  @override
  Future<List<Change>> changes(String root) async => const [
    Change('a.txt', ' M'),
    Change(
      'a-very-long-filename-that-must-not-push-the-status-column.txt',
      'MM',
    ),
    Change('nested/directory/deep/file.txt', '??'),
  ];
}
