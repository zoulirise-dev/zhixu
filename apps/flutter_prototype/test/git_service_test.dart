import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:zhixu_prototype/core/git_service.dart';

void main() {
  late Directory temp;
  late String root;
  late GitService git;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('zhixu-flutter-test-');
    root = p.join(temp.path, '中文 repo');
    await Directory(root).create();
    git = GitService(
      environment: {
        'GIT_CONFIG_GLOBAL': p.join(temp.path, 'global'),
        'GIT_CONFIG_NOSYSTEM': '1',
      },
    );
    await git.run(root, ['init', '-b', 'main']);
    await git.saveAuthor(root, 'Prototype Test', 'prototype@example.invalid');
    await git.run(root, ['config', 'commit.gpgsign', 'false']);
  });
  tearDown(() async => temp.delete(recursive: true));
  Future<void> write(String name, String text) async =>
      File(p.join(root, name)).writeAsString(text);
  Future<void> seed() async {
    await write('chosen.txt', 'base\n');
    await write('other.txt', 'base\n');
    await git.run(root, ['add', '.']);
    await git.run(root, ['commit', '-m', 'seed']);
  }

  test('editor baseline reads nested tracked files and keeps ignored files neutral', () async {
    await Directory(p.join(root, 'public')).create();
    final relative = p.join('public', '页面.html');
    await write(relative, '<html>unchanged</html>\n');
    await write('.gitignore', '*.log\n');
    await git.run(root, ['add', '.']);
    await git.run(root, ['commit', '-m', 'nested file']);
    expect(
      await git.editorBaseline(root, relative, 'fallback'),
      '<html>unchanged</html>\n',
    );
    await write('debug.log', 'ignored\n');
    expect(
      await git.editorBaseline(root, 'debug.log', 'ignored\n'),
      'ignored\n',
    );
    await write('new.txt', 'new\n');
    expect(await git.editorBaseline(root, 'new.txt', 'new\n'), '');
    await git.run(root, ['add', 'new.txt']);
    expect(await git.editorBaseline(root, 'new.txt', 'new\n'), '');
  });

  test('ignore queries support folders, nested rules, negation and tracked exceptions', () async {
    await Directory(p.join(root, 'cache')).create();
    await Directory(p.join(root, 'nested')).create();
    await write('.gitignore', 'cache/\n*.log\n!important.log\n');
    await write('nested/.gitignore', '*.tmp\n');
    await write('cache/item.txt', 'ignored');
    await write('nested/local.tmp', 'ignored');
    await write('debug.log', 'ignored');
    await write('important.log', 'included');
    await write('tracked.log', 'tracked');
    await git.run(root, ['add', '-f', '--', 'tracked.log']);
    final names = [
      'cache',
      'cache/item.txt',
      'nested/local.tmp',
      'debug.log',
      'important.log',
      'tracked.log',
    ];
    expect(await git.ignoredPaths(root, names), {
      'cache',
      'cache/item.txt',
      'nested/local.tmp',
      'debug.log',
    });
    await write('.gitignore', '');
    expect(await git.ignoredPaths(root, names), {'nested/local.tmp'});
    final global = p.join(temp.path, 'global-ignore');
    await File(global).writeAsString('private-*.txt\n');
    await git.run(root, ['config', 'core.excludesFile', global]);
    await write('private-中文.txt', 'ignored');
    final oddName = Platform.isWindows
        ? 'private-odd name.txt'
        : 'private-odd\nname.txt';
    await write(oddName, 'ignored');
    expect(await git.ignoredPaths(root, ['private-中文.txt', oddName]), {
      'private-中文.txt',
      oddName,
    });
  });

  test(
    'image reader preserves binary bytes and rejects outside symlinks',
    () async {
      final bytes = [137, 80, 78, 71, 0, 255, 42];
      await File(p.join(root, 'preview.png')).writeAsBytes(bytes);
      expect(await git.readImage(root, 'preview.png'), bytes);
      final outside = File(p.join(temp.path, 'outside.png'));
      await outside.writeAsBytes(bytes);
      await Link(p.join(root, 'linked.png')).create(outside.path);
      await expectLater(
        git.readImage(root, 'linked.png'),
        throwsA(isA<GitFailure>()),
      );
    },
  );
  test(
    'initial commit excludes unchecked staged files and retains staging',
    () async {
      await write('中文 file.txt', '你好\n');
      await write('other.txt', 'leave\n');
      await git.run(root, ['add', 'other.txt']);
      final change = (await git.changes(root))
          .firstWhere((c) => c.path == '中文 file.txt');
      await git.commitSelected(root, [change], 'first');
      expect(
        (await git.run(root, [
          'ls-tree',
          '--name-only',
          '-r',
          'HEAD',
        ])).out.trim(),
        isNotEmpty,
      );
      expect(
        (await git.run(root, ['show', 'HEAD:other.txt'], check: false)).code,
        isNot(0),
      );
      expect((await git.run(root, ['show', ':other.txt'])).out, 'leave\n');
    },
  );
  test('unchecked partial staging and working content are preserved', () async {
    await seed();
    await write('other.txt', 'staged\n');
    await git.run(root, ['add', 'other.txt']);
    await write('other.txt', 'unstaged\n');
    await write('chosen.txt', 'chosen\n');
    final before = (await git.run(root, [
      'ls-files',
      '--stage',
      'other.txt',
    ])).out;
    final c = (await git.changes(root))
        .firstWhere((c) => c.path == 'chosen.txt');
    await git.commitSelected(root, [c], 'selected');
    expect((await git.run(root, ['show', 'HEAD:other.txt'])).out, 'base\n');
    expect(
      (await git.run(root, ['ls-files', '--stage', 'other.txt'])).out,
      before,
    );
    expect(await File(p.join(root, 'other.txt')).readAsString(), 'unstaged\n');
    expect((await git.changes(root)).any((c) => c.path == 'chosen.txt'), false);
  });
  test('renames, deletions, literal pathspec names and spaces', () async {
    await seed();
    await git.run(root, ['mv', 'chosen.txt', '重命名 file.txt']);
    var c = (await git.changes(root))
        .firstWhere((c) => c.path == '重命名 file.txt');
    expect(c.oldPath, 'chosen.txt');
    await git.commitSelected(root, [c], 'rename');
    expect(
      (await git.run(root, ['show', 'HEAD:chosen.txt'], check: false)).code,
      isNot(0),
    );
    await File(p.join(root, 'other.txt')).delete();
    c = (await git.changes(root)).firstWhere((c) => c.path == 'other.txt');
    await git.commitSelected(root, [c], 'delete');
    final special = Platform.isWindows ? '[special] file.txt' : ':(glob)*.txt';
    await write(special, 'literal');
    await write('unchecked.txt', 'leave');
    c = (await git.changes(root)).firstWhere((c) => c.path == special);
    await git.commitSelected(root, [c], 'literal');
    expect(
      (await git.run(root, ['show', 'HEAD:unchecked.txt'], check: false)).code,
      isNot(0),
    );
  });
  test('rejected hook keeps original HEAD, index and worktree', () async {
    await seed();
    await write('chosen.txt', 'new\n');
    final hook = File(p.join(root, '.git', 'hooks', 'pre-commit'));
    await hook.writeAsString('#!/bin/sh\nexit 1\n');
    if (!Platform.isWindows) await Process.run('chmod', ['+x', hook.path]);
    final oldHead = await git.head(root),
        oldIndex = await File(p.join(root, '.git', 'index')).readAsBytes();
    final c = (await git.changes(root))
        .firstWhere((c) => c.path == 'chosen.txt');
    await expectLater(
      git.commitSelected(root, [c], 'reject'),
      throwsA(isA<GitFailure>()),
    );
    expect(await git.head(root), oldHead);
    expect(await File(p.join(root, '.git', 'index')).readAsBytes(), oldIndex);
    expect(await File(p.join(root, 'chosen.txt')).readAsString(), 'new\n');
  });
  test(
    'external edits and paths outside repository are not overwritten',
    () async {
      await write('中文.txt', 'original');
      final original = await git.readFile(root, '中文.txt');
      await write('中文.txt', 'external');
      await expectLater(
        git.saveFile(root, '中文.txt', original, 'mine'),
        throwsA(isA<GitFailure>()),
      );
      expect(await File(p.join(root, '中文.txt')).readAsString(), 'external');
      await File(p.join(temp.path, 'outside.txt')).writeAsString('outside');
      await expectLater(
        git.readFile(root, '../outside.txt'),
        throwsA(isA<GitFailure>()),
      );
      await write('large.txt', 'a' * (2 * 1024 * 1024 + 1));
      await expectLater(
        git.readFile(root, 'large.txt'),
        throwsA(isA<GitFailure>()),
      );
    },
  );
  test(
    'explicit target push contacts only the selected local remote',
    () async {
      await seed();
      for (final name in ['one', 'two']) {
        final remote = p.join(temp.path, '$name.git');
        await git.run(temp.path, ['init', '--bare', remote]);
        await git.run(root, ['remote', 'add', name, remote]);
      }
      await git.network(root, 'two', 'push');
      expect(
        (await git.run(p.join(temp.path, 'two.git'), [
          'rev-parse',
          '--verify',
          'refs/heads/main',
        ])).out.trim(),
        await git.head(root),
      );
      expect(
        (await git.run(p.join(temp.path, 'one.git'), [
          'rev-parse',
          '--verify',
          'refs/heads/main',
        ], check: false)).code,
        isNot(0),
      );
      expect(await git.config(root, 'user.email'), 'prototype@example.invalid');
    },
  );
  test('existing Git credential helper is reused by a real HTTP Git request', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var authenticated = 0;
    server.listen((request) async {
      if (request.headers.value('authorization') !=
          'Basic ${base64Encode(utf8.encode('demo:fixture'))}') {
        request.response.statusCode = 401;
        request.response.headers.set('www-authenticate', 'Basic realm="test"');
      } else {
        authenticated++;
        request.response.headers.set(
          'content-type',
          'application/x-git-upload-pack-advertisement',
        );
        const service = '# service=git-upload-pack\n';
        request.response.write(
          '${(service.length + 4).toRadixString(16).padLeft(4, '0')}${service}00000000',
        );
      }
      await request.response.close();
    });
    await git.run(root, [
      'config',
      'credential.helper',
      r'!f() { if [ "$1" = get ]; then printf "username=demo\npassword=fixture\n"; fi; }; f',
    ]);
    await git.run(root, [
      'remote',
      'add',
      'test',
      'http://127.0.0.1:${server.port}/repo.git',
    ]);
    await git.network(root, 'test', 'check');
    expect(authenticated, greaterThan(0));
  });
  test('auth, permission and network failures have distinct safe messages', () {
    expect(
      GitFailure.fromOutput('fatal: Authentication failed token=secret').kind,
      FailureKind.authentication,
    );
    expect(GitFailure.fromOutput('HTTP 403').kind, FailureKind.permission);
    expect(
      GitFailure.fromOutput('Could not resolve host').kind,
      FailureKind.network,
    );
    expect(
      GitFailure.fromOutput('token=secret').toString(),
      isNot(contains('secret')),
    );
    expect(
      () => HttpsCredential(Uri.parse('http://example.invalid'), 'a', 'b'),
      throwsA(isA<GitFailure>()),
    );
    expect(
      () => HttpsCredential(
        Uri.parse('https://example.invalid'),
        'a\npassword=x',
        'b',
      ),
      throwsA(isA<GitFailure>()),
    );
  });
}
