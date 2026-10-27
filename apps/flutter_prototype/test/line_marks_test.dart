import 'package:zhixu_prototype/core/git_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zhixu_prototype/ui/code_editor.dart';

void main() {
  test(
    'new files mark all lines as additions and empty files stay neutral',
    () {
      expect(lineMarks('', ''), isEmpty);
      expect(lineMarks('', 'first\nsecond').values.toSet(), {
        const Color(0xff2eae57),
      });
    },
  );
  test('renaming a document updates highlighting without changing text', () {
    final controller = CodeController(
      text: 'const value = 1;',
      language: 'javascript',
    );
    var notifications = 0;
    controller.addListener(() => notifications++);
    controller.language = 'typescript';
    expect(controller.language, 'typescript');
    expect(controller.text, 'const value = 1;');
    expect(notifications, 1);
    controller.language = 'typescript';
    expect(notifications, 1);
    controller.dispose();
  });
  test('path separator conversion respects platform filename rules', () {
    expect(gitPath(r'dir\file.txt', windows: true), 'dir/file.txt');
    expect(gitPath(r'dir\file.txt', windows: false), r'dir\file.txt');
    expect(
      gitPath(r'\\server\share\repo', windows: true),
      '//server/share/repo',
    );
  });
  test('unchanged CRLF checkout has no gutter or minimap changes', () {
    expect(lineMarks('one\ntwo\n', 'one\r\ntwo\r\n'), isEmpty);
    expect(lineMarks('one\r\ntwo\r\n', 'one\ntwo\n'), isEmpty);
    expect(lineMarks('one\ntwo\n', 'one\r\nchanged\r\n').keys, [1]);
  });
}
