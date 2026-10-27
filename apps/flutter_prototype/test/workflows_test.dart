import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:zhixu_prototype/core/git_service.dart';
import 'package:zhixu_prototype/core/workflows.dart';
import 'package:zhixu_prototype/ui/code_editor.dart';
import 'package:flutter/material.dart';

void main() {
  late Directory temp;
  late String root;
  late GitService git;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('zhixu-parity-');
    root = p.join(temp.path, '项目 repo');
    await Directory(root).create();
    git = GitService(
      environment: {
        'GIT_CONFIG_GLOBAL': p.join(temp.path, 'gitconfig'),
        'GIT_CONFIG_NOSYSTEM': '1',
      },
    );
    await git.run(root, ['init', '-b', 'main']);
    await git.saveAuthor(root, 'Demo', 'demo@example.invalid');
    await git.run(root, ['config', 'commit.gpgsign', 'false']);
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });
  Future<void> write(String name, String value) =>
      File(p.join(root, name)).writeAsString(value);
  Future<void> commit(String msg) async {
    await git.run(root, ['add', '-A']);
    await git.run(root, ['commit', '-m', msg]);
  }

  test('nested native paths agree across history, images, restore, ignore and selected commit', () async {
    final folder = p.join('目录 with space', '[literal]');
    await Directory(p.join(root, folder)).create(recursive: true);
    final native = p.join(folder, '代码.txt');
    final key = '目录 with space/[literal]/代码.txt';
    final image = p.join(folder, '图.png');
    await write(native, 'original\n');
    await File(p.join(root, image)).writeAsBytes([137, 80, 78, 71, 0, 255]);
    await commit('initial');
    final first = await git.head(root);
    expect(repositoryRelative(p.join(root, native), from: root), key);
    expect(await git.imageAt(root, image, first), [137, 80, 78, 71, 0, 255]);
    expect((await git.history(root, path: native)).length, 1);
    await write(native, 'changed\n');
    expect((await git.changes(root)).single.path, key);
    expect(await git.editorBaseline(root, native, 'fallback'), 'original\n');
    final plan = await git.prepareFileVersion(root, first, native);
    try {
      await git.applyRestore(root, plan, {});
    } finally {
      await plan.dispose();
    }
    expect(await File(p.join(root, native)).readAsString(), 'original\n');
    await write(native, 'backup\n');
    final backup = await git.stash(root);
    final restore = await git.prepareRestore(root, backup);
    try {
      await git.applyRestore(root, restore, {});
    } finally {
      await restore.dispose();
    }
    expect(await File(p.join(root, native)).readAsString(), 'backup\n');
    await git.commitSelected(root, await git.changes(root), 'selected');
    expect((await git.run(root, ['show', 'HEAD:$key'])).out, 'backup\n');
    final ignored = p.join(folder, 'debug.log');
    await write(ignored, 'log');
    await git.ignore(root, ignored, 'file');
    expect(await git.ignoredPaths(root, [ignored]), contains(gitPath(ignored)));
  });
  test(
    'POSIX backslash filename survives ignore and historical restoration',
    () async {
      const name = r'file\name.txt';
      await write(name, 'before');
      await commit('literal backslash');
      await write(name, 'after');
      final plan = await git.prepareFileVersion(root, 'HEAD', name);
      try {
        await git.applyRestore(root, plan, {});
      } finally {
        await plan.dispose();
      }
      expect(await File(p.join(root, name)).readAsString(), 'before');
      const ignored = r'debug\trace.log';
      await write(ignored, 'ignored');
      await git.ignore(root, ignored, 'file');
      expect(await git.ignoredPaths(root, [ignored]), contains(ignored));
    },
    skip: Platform.isWindows,
  );

  test('manual staging previews index and working tree separately', () async {
    await write('a.txt', 'base\n');
    await commit('first');
    await write('a.txt', 'staged\n');
    await git.run(root, ['add', 'a.txt']);
    await write('a.txt', 'working\n');
    final change = (await git.changes(root)).single;
    final staged = await git.diff(root, change, staged: true);
    final working = await git.diff(root, change, staged: false);
    expect(staged, contains('+staged'));
    expect(staged, isNot(contains('+working')));
    expect(working, contains('-staged'));
    expect(working, contains('+working'));
  });
  test(
    'remote checkout reuses existing tracking branch and filters symbolic HEAD',
    () async {
      await write('a.txt', 'a');
      await commit('first');
      final bare = p.join(temp.path, 'remote.git');
      await git.run(temp.path, ['init', '--bare', bare]);
      await git.run(root, ['remote', 'add', 'origin', bare]);
      await git.run(root, ['push', '-u', 'origin', 'main']);
      await git.run(root, ['remote', 'set-head', 'origin', 'main']);
      await git.createBranch(root, 'feature');
      await write('a.txt', 'b');
      await commit('feature');
      var list = await git.branches(root);
      expect(list.where((b) => b.remote).length, 1);
      await git.switchBranch(root, list.firstWhere((b) => b.remote));
      expect(await git.branch(root), 'main');
      await git.switchBranch(
        root,
        (await git.branches(root)).firstWhere((b) => b.name == 'feature'),
      );
      await git.switchBranch(root, list.firstWhere((b) => b.remote));
      expect(await git.branch(root), 'main');
      expect((await git.branches(root)).where((b) => !b.remote).length, 2);
    },
  );
  test(
    'unborn branch can rename but cannot create or delete current',
    () async {
      final b = (await git.branches(root)).single;
      await git.renameBranch(root, b, 'work');
      expect(await git.branch(root), 'work');
      await expectLater(
        git.createBranch(root, 'other'),
        throwsA(isA<GitFailure>()),
      );
      await expectLater(
        git.deleteBranch(root, (await git.branches(root)).single),
        throwsA(isA<GitFailure>()),
      );
    },
  );
  test(
    'advanced commit uses selected staged version and retains working changes',
    () async {
      await write('a', 'base');
      await write('b', 'base');
      await commit('first');
      await write('a', 'staged');
      await write('b', 'staged b');
      await git.run(root, ['add', 'a', 'b']);
      await write('a', 'working');
      await git.commitSelected(
        root,
        (await git.changes(root)).where((c) => c.path == 'a').toList(),
        'selected stage',
        stagedOnly: true,
      );
      expect((await git.run(root, ['show', 'HEAD:a'])).out, 'staged');
      expect(await File(p.join(root, 'a')).readAsString(), 'working');
      expect((await git.run(root, ['show', ':b'])).out, 'staged b');
      expect((await git.run(root, ['show', 'HEAD:b'])).out, 'base');
    },
  );
  test('backup restore compares existing untracked file and keeps explicit selection', () async {
    await write('a', 'base');
    await commit('first');
    await write('a', 'backup a');
    await write('new.txt', 'backup new');
    final id = await git.stash(root);
    await write('new.txt', 'current new');
    final plan = await git.prepareRestore(root, id);
    try {
      expect(plan.items.length, 2);
      await git.applyRestore(root, plan, {'new.txt'});
      expect(await File(p.join(root, 'a')).readAsString(), 'backup a');
      expect(await File(p.join(root, 'new.txt')).readAsString(), 'current new');
      expect((await git.backups(root)).single.oid, id);
    } finally {
      await plan.dispose();
    }
  });
  test('restore rejects externally changed file before any writes', () async {
    await write('a', 'base');
    await commit('first');
    await write('a', 'backup');
    final id = await git.stash(root);
    final plan = await git.prepareRestore(root, id);
    await write('a', 'external');
    try {
      await expectLater(
        git.applyRestore(root, plan, {}),
        throwsA(isA<GitFailure>()),
      );
      expect(await File(p.join(root, 'a')).readAsString(), 'external');
    } finally {
      await plan.dispose();
    }
  });
  test('deleting one tracked and untracked backup entry preserves other files and real index', () async {
    await write('a', 'base');
    await write('b', 'base b');
    await commit('first');
    await write('a', 'backup');
    await write('b', 'backup b');
    await write('new', 'new backup');
    final id = await git.stash(root);
    final indexBefore = (await git.run(root, ['ls-files', '--stage'])).out;
    await git.deleteBackupFile(root, id, 'a', false);
    var current = (await git.backups(root)).single.oid;
    expect(
      (await git.backupFiles(root, current)).map((f) => f.$1),
      containsAll(['b', 'new']),
    );
    expect(
      (await git.backupFiles(root, current)).map((f) => f.$1),
      isNot(contains('a')),
    );
    await git.deleteBackupFile(root, current, 'new', true);
    current = (await git.backups(root)).single.oid;
    expect((await git.backupFiles(root, current)).map((f) => f.$1).toList(), [
      'b',
    ]);
    expect((await git.run(root, ['ls-files', '--stage'])).out, indexBefore);
    expect(await File(p.join(root, 'a')).readAsString(), 'base');
  });
  test(
    'merge conflict state can resolve and continue without losing history',
    () async {
      await write('a', 'base\n');
      await commit('first');
      await git.createBranch(root, 'feature');
      await write('a', 'incoming\n');
      await commit('feature');
      await git.run(root, ['switch', 'main']);
      await write('a', 'current\n');
      await commit('main');
      await git.integrate(root, 'feature');
      expect(await git.operation(root), 'merge');
      expect((await git.changes(root)).single.conflict, true);
      await expectLater(git.finishOperation(root), throwsA(isA<GitFailure>()));
      await write('a', 'current\nincoming\n');
      await git.run(root, ['add', 'a']);
      await git.finishOperation(root);
      expect(await git.operation(root), null);
      expect(
        (await git.run(root, [
          'rev-list',
          '--parents',
          '-n',
          '1',
          'HEAD',
        ])).out.trim().split(' ').length,
        3,
      );
    },
  );
  test(
    'history initial commit, review, reverse commit and safe undo',
    () async {
      await write('a', 'base');
      await commit('first');
      final first = await git.head(root);
      expect((await git.reviewFiles(root, first)).single.path, 'a');
      await write('a', 'second');
      await commit('second');
      final second = await git.head(root);
      expect((await git.history(root, path: 'a')).length, 2);
      await git.integrate(root, second, revert: true);
      expect(await File(p.join(root, 'a')).readAsString(), 'base');
      await git.undoCommit(root, await git.head(root));
      expect(await git.head(root), second);
      expect(await File(p.join(root, 'a')).readAsString(), 'base');
    },
  );
  test('ignore uses literal escaped patterns and destination blocks traversal and symlink parent', () async {
    await git.ignore(root, 'a[b].txt', 'file');
    expect(
      await File(p.join(root, '.gitignore')).readAsString(),
      '/a\\[b\\].txt\n',
    );
    await expectLater(
      git.destination(root, '../escape'),
      throwsA(isA<GitFailure>()),
    );
    await expectLater(
      git.destination(root, '.git/config'),
      throwsA(isA<GitFailure>()),
    );
    if (!Platform.isWindows) {
      await Link(p.join(root, 'outside')).create(temp.path);
      await expectLater(
        git.destination(root, 'outside/file'),
        throwsA(isA<GitFailure>()),
      );
    }
  });
  test('file history restores an earlier name to the current path', () async {
    await write('old.txt', 'original\n');
    await commit('first');
    final first = await git.head(root);
    await git.run(root, ['mv', 'old.txt', 'new.txt']);
    await commit('rename');
    await write('new.txt', 'changed\n');
    final source = await git.historicalPath(root, first, 'new.txt');
    expect(source, 'old.txt');
    final plan = await git.prepareFileVersion(
      root,
      first,
      'new.txt',
      source: source,
    );
    try {
      await git.applyRestore(root, plan, {});
      expect(await File(p.join(root, 'new.txt')).readAsString(), 'original\n');
      expect(await File(p.join(root, 'old.txt')).exists(), false);
    } finally {
      await plan.dispose();
    }
  });
  test(
    'whole-file conflict resolution preserves binary bytes and deletion',
    () async {
      await File(p.join(root, 'binary')).writeAsBytes([0, 1, 2]);
      await commit('base');
      await git.run(root, ['switch', '-c', 'feature']);
      await File(p.join(root, 'binary')).writeAsBytes([0, 3, 4]);
      await commit('feature');
      await git.run(root, ['switch', 'main']);
      await File(p.join(root, 'binary')).writeAsBytes([0, 5, 6]);
      await commit('main');
      await git.run(root, ['merge', 'feature'], check: false);
      await git.resolveWholeConflict(
        root,
        'binary',
        3,
        await git.snapshot(p.join(root, 'binary')),
      );
      expect(await File(p.join(root, 'binary')).readAsBytes(), [0, 3, 4]);
      expect((await git.run(root, ['ls-files', '-u'])).out, isEmpty);
      await git.run(root, ['merge', '--abort']);
      await git.run(root, ['switch', 'feature']);
      await git.run(root, ['rm', 'binary']);
      await commit('delete');
      await git.run(root, ['switch', 'main']);
      await git.run(root, ['merge', 'feature'], check: false);
      await git.resolveWholeConflict(
        root,
        'binary',
        3,
        await git.snapshot(p.join(root, 'binary')),
      );
      expect(await File(p.join(root, 'binary')).exists(), false);
      expect((await git.run(root, ['ls-files', '-u'])).out, isEmpty);
    },
  );
  test('completion formatter does not transform composition commits', () {
    final formatter = CodeInputFormatter();
    const old = TextEditingValue(
      text: 'ni',
      selection: TextSelection.collapsed(offset: 2),
      composing: TextRange(start: 0, end: 2),
    );
    const next = TextEditingValue(
      text: '你(',
      selection: TextSelection.collapsed(offset: 2),
    );
    expect(formatter.formatEditUpdate(old, next), next);
    const start = TextEditingValue(
      text: '',
      selection: TextSelection.collapsed(offset: 0),
    );
    const typed = TextEditingValue(
      text: '(',
      selection: TextSelection.collapsed(offset: 1),
    );
    expect(formatter.formatEditUpdate(start, typed).text, '()');
    expect(lineMarks('a\nb', 'a\nnew\nb')[1], const Color(0xff2eae57));
    expect(lineMarks('a\nold\nb', 'a\nb')[1], Colors.red);
  });
}
