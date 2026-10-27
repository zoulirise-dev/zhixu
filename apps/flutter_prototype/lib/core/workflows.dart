import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'git_service.dart';

class BranchInfo {
  final String ref, name, upstream;
  final bool remote, current;
  const BranchInfo(
    this.ref,
    this.name,
    this.upstream,
    this.remote,
    this.current,
  );
}

class CommitInfo {
  final String oid, subject, author, email, date;
  const CommitInfo(this.oid, this.subject, this.author, this.email, this.date);
}

class BackupInfo {
  final String oid, ref, subject, date;
  const BackupInfo(this.oid, this.ref, this.subject, this.date);
  String get branch =>
      subject.replaceFirst(RegExp(r'^(WIP on |On )'), '').split(': ').first;
}

class ReviewFile {
  final String path, status;
  const ReviewFile(this.path, this.status);
}

class RestoreItem {
  final String path, source, snapshot;
  const RestoreItem(this.path, this.source, this.snapshot);
}

class RestorePlan {
  final Directory directory;
  final List<RestoreItem> items;
  const RestorePlan(this.directory, this.items);
  Future<void> dispose() => directory.delete(recursive: true);
}

extension GitWorkflows on GitService {
  Future<String> oid(String root, String ref) async {
    if (ref.startsWith('-') || ref.contains('\x00')) {
      throw GitFailure(FailureKind.other, '无效的版本。');
    }
    return (await run(root, [
      'rev-parse',
      '--verify',
      '$ref^{commit}',
    ])).out.trim();
  }

  Future<List<BranchInfo>> branches(String root) async {
    final text = (await run(root, [
      'for-each-ref',
      '--sort=-committerdate',
      '--format=%(refname)%00%(refname:short)%00%(upstream:short)%00%(HEAD)%00%(symref)',
      'refs/heads',
      'refs/remotes',
    ])).out;
    final result = <BranchInfo>[];
    for (final line in text.split('\n')) {
      final f = line.split('\x00');
      if (f.length != 5 || f[4].isNotEmpty) continue;
      result.add(
        BranchInfo(
          f[0],
          f[1],
          f[2],
          f[0].startsWith('refs/remotes/'),
          f[3] == '*',
        ),
      );
    }
    if (result.every((b) => !b.current) && (await head(root)).isEmpty) {
      final name = await branch(root);
      if (name.isNotEmpty) {
        result.insert(0, BranchInfo('refs/heads/$name', name, '', false, true));
      }
    }
    return [
      ...result.where((b) => b.current),
      ...result.where((b) => !b.current),
    ];
  }

  Future<(int, int, String)> counts(String root) async {
    final upstream = (await run(root, [
      'rev-parse',
      '--abbrev-ref',
      '--symbolic-full-name',
      '@{upstream}',
    ], check: false)).out.trim();
    if ((await head(root)).isEmpty) return (0, 0, upstream);
    if (upstream.isEmpty) {
      final out = (await run(root, [
        'rev-list',
        '--count',
        'HEAD',
        '--not',
        '--remotes',
      ])).out;
      return (int.tryParse(out.trim()) ?? 0, 0, '');
    }
    final fields = (await run(root, [
      'rev-list',
      '--left-right',
      '--count',
      'HEAD...@{upstream}',
    ])).out.trim().split(RegExp(r'\s+'));
    return (
      int.tryParse(fields.first) ?? 0,
      int.tryParse(fields.last) ?? 0,
      upstream,
    );
  }

  Future<void> validateBranch(String root, String name) async {
    if (name.startsWith('-') ||
        (await run(root, [
              'check-ref-format',
              '--branch',
              name,
            ], check: false)).code !=
            0) {
      throw GitFailure(FailureKind.other, '分支名称无效。');
    }
  }

  Future<void> createBranch(String root, String name) async {
    await validateBranch(root, name);
    if ((await head(root)).isEmpty) {
      throw GitFailure(FailureKind.other, '尚无首次提交，暂时不能创建第二条分支。可以重命名当前分支。');
    }
    await run(root, ['switch', '-c', name]);
  }

  Future<void> switchBranch(String root, BranchInfo target) async {
    if (!target.remote) {
      await run(root, ['switch', '--', target.name]);
      return;
    }
    // Reuse existing tracking branch instead of trying to recreate it.
    final local = (await branches(root))
        .where((b) => !b.remote && b.upstream == target.name)
        .toList();
    if (local.isNotEmpty) {
      await run(root, ['switch', '--', local.first.name]);
      return;
    }
    final slash = target.name.indexOf('/');
    final desired = target.name.substring(slash + 1);
    final existing = (await branches(root))
        .where((b) => !b.remote)
        .map((b) => b.name)
        .toSet();
    var name = desired;
    if (existing.contains(name)) name = target.name;
    var n = 2;
    while (existing.contains(name)) {
      name = '${target.name}-$n';
      n++;
    }
    await run(root, ['switch', '--track', '-c', name, target.ref]);
  }

  Future<void> renameBranch(String root, BranchInfo target, String name) async {
    await validateBranch(root, name);
    if (!target.remote) {
      await run(root, ['branch', '-m', target.name, name]);
      return;
    }
    final slash = target.name.indexOf('/');
    final remote = target.name.substring(0, slash);
    final old = target.name.substring(slash + 1);
    if ((await run(root, [
      'ls-remote',
      '--heads',
      '--',
      remote,
      'refs/heads/$name',
    ])).out.trim().isNotEmpty) {
      throw GitFailure(FailureKind.other, '远程已存在同名分支，请使用其他名称。');
    }
    await run(root, [
      'push',
      '--',
      remote,
      '${await oid(root, target.ref)}:refs/heads/$name',
    ], timeout: const Duration(minutes: 2));
    await run(root, [
      'push',
      '--',
      remote,
      ':refs/heads/$old',
    ], timeout: const Duration(minutes: 2));
    for (final b in await branches(root)) {
      if (!b.remote && b.upstream == target.name) {
        await run(root, [
          'config',
          'branch.${b.name}.merge',
          'refs/heads/$name',
        ]);
      }
    }
    await run(root, ['fetch', '--prune', '--', remote]);
  }

  Future<void> deleteBranch(String root, BranchInfo target) async {
    final current = await branch(root);
    if (target.current ||
        (!target.remote && target.name == current) ||
        (target.remote &&
            '${await config(root, 'branch.$current.remote')}/${(await config(root, 'branch.$current.merge')).replaceFirst('refs/heads/', '')}' ==
                target.name)) {
      throw GitFailure(FailureKind.other, '不能删除当前使用的分支。');
    }
    if (!target.remote) {
      await run(root, ['branch', '-d', target.name]);
      return;
    }
    final slash = target.name.indexOf('/');
    await run(root, [
      'push',
      '--',
      target.name.substring(0, slash),
      ':refs/heads/${target.name.substring(slash + 1)}',
    ], timeout: const Duration(minutes: 2));
    await run(root, [
      'fetch',
      '--prune',
      '--',
      target.name.substring(0, slash),
    ]);
  }

  Future<List<CommitInfo>> history(
    String root, {
    String? path,
    int skip = 0,
    String ref = 'HEAD',
  }) async {
    if ((await head(root)).isEmpty) return [];
    final out = (await run(root, [
      'log',
      '--date=iso-strict',
      '--format=%H%x00%s%x00%an%x00%ae%x00%aI',
      '--max-count=80',
      '--skip=$skip',
      if (path != null) '--follow',
      ref,
      if (path != null) '--',
      if (path != null) gitPath(path),
    ])).out;
    return out
        .split('\n')
        .map((s) => s.split('\x00'))
        .where((f) => f.length == 5)
        .map((f) => CommitInfo(f[0], f[1], f[2], f[3], f[4]))
        .toList();
  }

  Future<List<ReviewFile>> reviewFiles(
    String root,
    String ref, {
    bool compare = false,
  }) async {
    final id = await oid(root, ref);
    final parent = await run(root, [
      'rev-parse',
      '--verify',
      '$id^1',
    ], check: false);
    final args = compare
        ? ['diff', '--name-status', '--no-renames', '-z', 'HEAD', id]
        : parent.code == 0
        ? ['diff', '--name-status', '--no-renames', '-z', parent.out.trim(), id]
        : [
            'diff-tree',
            '--root',
            '--no-commit-id',
            '--name-status',
            '--no-renames',
            '-r',
            '-z',
            id,
          ];
    final parts = (await run(root, args)).out.split('\x00');
    return [
      for (var i = 0; i + 1 < parts.length; i += 2)
        if (parts[i].isNotEmpty) ReviewFile(parts[i + 1], parts[i]),
    ];
  }

  Future<String> reviewPatch(
    String root,
    String ref,
    String path, {
    bool compare = false,
  }) async {
    path = gitPath(path);
    final id = await oid(root, ref);
    final parent = await run(root, [
      'rev-parse',
      '--verify',
      '$id^1',
    ], check: false);
    final args = compare || parent.code == 0
        ? [
            'diff',
            '--no-ext-diff',
            '--no-textconv',
            '--no-color',
            '--unified=10000',
            compare ? 'HEAD' : parent.out.trim(),
            id,
            '--',
            path,
          ]
        : [
            'show',
            '--format=',
            '--no-ext-diff',
            '--no-textconv',
            '--no-color',
            '--unified=10000',
            id,
            '--',
            path,
          ];
    return (await run(root, args)).out;
  }

  Future<void> resolveWholeConflict(
    String root,
    String path,
    int stage,
    String expected,
  ) async {
    if (stage != 2 && stage != 3) {
      throw GitFailure(FailureKind.other, '无效的冲突版本。');
    }
    final target = await destination(root, path);
    final unresolved = (await run(root, [
      'ls-files',
      '-u',
      '-z',
      '--',
      path,
    ])).out;
    if (unresolved.isEmpty) throw GitFailure(FailureKind.other, '冲突状态已变化，请刷新。');
    final entries = unresolved
        .split('\x00')
        .where((e) => e.isNotEmpty)
        .toList();
    final selected = entries
        .where((e) => e.split('\t').first.split(' ').last == '$stage')
        .toList();
    final temp = await Directory.systemTemp.createTemp('zhixu-conflict-');
    try {
      final export = p.join(temp.path, 'files');
      await Directory(export).create();
      final source = p.join(export, path);
      if (selected.isNotEmpty) {
        final info = selected.single.split('\t').first.split(' ');
        final env = {'GIT_INDEX_FILE': p.join(temp.path, 'index')};
        await run(root, ['read-tree', '--empty'], env: env);
        await run(root, [
          'update-index',
          '--add',
          '--cacheinfo',
          info[0],
          info[1],
          path,
        ], env: env);
        await run(
          root,
          ['checkout-index', '--prefix=${gitPath(export)}/', '-z', '--stdin'],
          env: env,
          input: '$path\x00',
        );
      }
      if ((await run(root, ['ls-files', '-u', '-z', '--', path])).out !=
              unresolved ||
          await snapshot(target) != expected) {
        throw GitFailure(FailureKind.other, '文件或冲突状态已变化，请刷新后重试。');
      }
      await applyRestore(
        root,
        RestorePlan(temp, [RestoreItem(path, source, expected)]),
        {},
      );
      await run(root, ['add', '-A', '--', path]);
    } finally {
      await temp.delete(recursive: true);
    }
  }

  Future<String> historicalPath(String root, String ref, String path) async {
    path = gitPath(path);
    final id = await oid(root, ref);
    final parts = (await run(root, [
      'log',
      '--follow',
      '--format=%H%x00',
      '--name-only',
      '-z',
      '--',
      path,
    ])).out.split('\x00');
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].trim() != id) continue;
      for (var j = i + 1; j < parts.length; j++) {
        if (parts[j].isEmpty) continue;
        final source = parts[j].startsWith('\n')
            ? parts[j].substring(1)
            : parts[j];
        if (source.isEmpty) continue;
        await destination(root, source);
        return source;
      }
    }
    throw GitFailure(FailureKind.other, '无法定位此文件在所选提交中的路径。未修改工作区。');
  }

  Future<RestorePlan> prepareFileVersion(
    String root,
    String ref,
    String target, {
    String? source,
  }) async {
    final id = await oid(root, ref);
    target = gitPath(target);
    final path = gitPath(source ?? target);
    await destination(root, path);
    final destinationPath = await destination(root, target);
    final temporary = await Directory.systemTemp.createTemp('zhixu-version-');
    try {
      final export = p.join(temporary.path, 'files');
      await Directory(export).create();
      final present = (await run(root, [
        'ls-tree',
        '-r',
        '--name-only',
        '-z',
        id,
        '--',
        path,
      ])).out;
      if (present.isNotEmpty) {
        final env = {'GIT_INDEX_FILE': p.join(temporary.path, 'index')};
        await run(root, ['read-tree', id], env: env);
        await run(
          root,
          ['checkout-index', '--prefix=${gitPath(export)}/', '-z', '--stdin'],
          env: env,
          input: present,
        );
      }
      return RestorePlan(temporary, [
        RestoreItem(
          target,
          p.join(export, path),
          await snapshot(destinationPath),
        ),
      ]);
    } catch (_) {
      await temporary.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> requireClean(String root) async {
    if ((await changes(root)).isNotEmpty || await operation(root) != null) {
      throw GitFailure(FailureKind.other, '请先提交或临时收起当前修改，再进行此操作。');
    }
  }

  Future<void> integrate(
    String root,
    String ref, {
    bool revert = false,
    String? expectedHead,
  }) async {
    if (expectedHead != null && await head(root) != expectedHead) {
      throw GitFailure(FailureKind.other, '当前提交已变化，请重新确认操作。');
    }
    await requireClean(root);
    final id = await oid(root, ref);
    final result = await run(
      root,
      revert ? ['revert', '--no-edit', id] : ['merge', '--no-edit', id],
      check: false,
      env: {'GIT_EDITOR': 'true'},
    );
    if (result.code != 0 && !(await changes(root)).any((c) => c.conflict)) {
      throw GitFailure.fromOutput(result.err);
    }
  }

  Future<String?> operation(String root) async {
    for (final pair in [
      ('MERGE_HEAD', 'merge'),
      ('REVERT_HEAD', 'revert'),
      ('CHERRY_PICK_HEAD', 'cherry-pick'),
      ('rebase-merge', 'rebase'),
      ('rebase-apply', 'rebase'),
    ]) {
      final loc = (await run(root, [
        'rev-parse',
        '--git-path',
        pair.$1,
      ])).out.trim();
      if (await FileSystemEntity.type(
            p.isAbsolute(loc) ? loc : p.join(root, loc),
          ) !=
          FileSystemEntityType.notFound) {
        return pair.$2;
      }
    }
    return null;
  }

  Future<void> finishOperation(String root, {bool abort = false}) async {
    final op = await operation(root);
    if (op == null) return;
    if (!abort && (await changes(root)).any((c) => c.conflict)) {
      throw GitFailure(FailureKind.other, '还有未解决的冲突。');
    }
    await run(
      root,
      [op, abort ? '--abort' : '--continue'],
      env: {'GIT_EDITOR': 'true', 'GIT_SEQUENCE_EDITOR': 'true'},
    );
  }

  Future<void> stage(
    String root,
    List<Change> files, {
    bool undo = false,
  }) async {
    final paths = files.expand((c) => c.paths).toSet();
    if (paths.isEmpty) return;
    if (undo && (await head(root)).isEmpty) {
      await run(root, [
        'rm',
        '--cached',
        '-r',
        '--ignore-unmatch',
        '--',
        ...paths,
      ]);
      return;
    }
    await run(
      root,
      undo
          ? ['reset', '-q', 'HEAD', '--', ...paths]
          : ['add', '-A', '--', ...paths],
    );
  }

  Future<void> undoCommit(String root, String id, {String? message}) async {
    if (await head(root) != id) {
      throw GitFailure(FailureKind.other, '只能撤销或修改最新提交。');
    }
    if ((await run(root, [
      'for-each-ref',
      '--contains',
      id,
      '--format=%(refname)',
      'refs/remotes',
    ])).out.trim().isNotEmpty) {
      throw GitFailure(FailureKind.other, '提交已存在于远程，请使用生成反向提交。');
    }
    if (await operation(root) != null) {
      throw GitFailure(FailureKind.other, '请先完成当前 Git 操作。');
    }
    if (message != null) {
      if ((await changes(root))
          .any((c) => !c.untracked && c.status[0] != ' ')) {
        throw GitFailure(FailureKind.other, '暂存区非空，请先取消暂存。');
      }
      await run(root, [
        'commit',
        '--amend',
        '--only',
        '-F',
        '-',
      ], input: message);
    } else {
      final parent = (await run(root, [
        'rev-parse',
        '--verify',
        '$id^',
      ], check: false));
      if (parent.code == 0) {
        await run(root, ['update-ref', 'HEAD', parent.out.trim(), id]);
      } else {
        await run(root, ['update-ref', '-d', 'HEAD', id]);
      }
    }
  }

  Future<String> destination(String root, String relative) async {
    if (p.isAbsolute(relative) ||
        p.split(relative).any((s) => s == '..' || s.toLowerCase() == '.git') ||
        relative.contains('\x00')) {
      throw GitFailure(FailureKind.other, '不能操作项目外或 Git 内部文件。');
    }
    final base = await Directory(root).resolveSymbolicLinks();
    final result = p.normalize(p.join(base, relative));
    if (result != base && !p.isWithin(base, result)) {
      throw GitFailure(FailureKind.other, '路径不在项目内。');
    }
    var parent = p.dirname(result);
    while (parent != base && p.isWithin(base, parent)) {
      final type = await FileSystemEntity.type(parent, followLinks: false);
      if (type == FileSystemEntityType.link ||
          (type != FileSystemEntityType.directory &&
              type != FileSystemEntityType.notFound)) {
        throw GitFailure(FailureKind.other, '上级路径不是普通文件夹。');
      }
      parent = p.dirname(parent);
    }
    return result;
  }

  Future<void> ignore(String root, String path, String kind) async {
    path = gitPath(path);
    await destination(root, path);
    String escape(String s) =>
        s.replaceAllMapped(RegExp(r'[\\*?\[\]#! ]'), (m) => '\\${m[0]}');
    final pattern = kind == 'type'
        ? '*${escape(p.extension(path))}'
        : '/${escape(gitPath(path))}${kind == 'folder' ? '/' : ''}';
    if (kind == 'type' && p.extension(path).isEmpty) {
      throw GitFailure(FailureKind.other, '此文件没有扩展名。');
    }
    final file = File(await destination(root, '.gitignore'));
    final text = await file.exists() ? await file.readAsString() : '';
    if (!text.split('\n').contains(pattern)) {
      await file.writeAsString(
        '$text${text.isNotEmpty && !text.endsWith('\n') ? '\n' : ''}$pattern\n',
      );
    }
  }

  Future<List<BackupInfo>> backups(String root) async {
    final out = (await run(root, [
      'stash',
      'list',
      '--format=%H%x00%gd%x00%gs%x00%cI',
    ])).out;
    return out
        .split('\n')
        .map((s) => s.split('\x00'))
        .where((f) => f.length == 4)
        .map((f) => BackupInfo(f[0], f[1], f[2], f[3]))
        .toList();
  }

  Future<String> stash(String root, {String message = '枝序 · 临时收起修改'}) async {
    await run(root, ['stash', 'push', '--include-untracked', '-m', message]);
    return (await oid(root, 'refs/stash'));
  }

  Future<void> dropBackup(String root, String id) async {
    final records = (await backups(root)).where((b) => b.oid == id);
    if (records.isEmpty) throw GitFailure(FailureKind.other, '备份已变化，请刷新。');
    await run(root, ['stash', 'drop', records.first.ref]);
  }

  Future<List<(String, bool)>> backupFiles(String root, String id) async {
    final files =
        (await run(root, [
              'diff',
              '--name-only',
              '--no-renames',
              '-z',
              '$id^1',
              id,
            ])).out
            .split('\x00')
            .where((s) => s.isNotEmpty)
            .map((s) => (s, false))
            .toList();
    if ((await run(root, [
          'rev-parse',
          '--verify',
          '$id^3',
        ], check: false)).code ==
        0) {
      files.addAll(
        (await run(root, [
          'ls-tree',
          '-r',
          '--name-only',
          '-z',
          '$id^3',
        ])).out.split('\x00').where((s) => s.isNotEmpty).map((s) => (s, true)),
      );
    }
    return files..sort((a, b) => a.$1.compareTo(b.$1));
  }

  Future<String> snapshot(String path) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return 'missing';
    if (type == FileSystemEntityType.directory) return 'directory';
    if (type == FileSystemEntityType.link) {
      return 'link:${await Link(path).target()}';
    }
    return 'file:${(await File(path).stat()).mode & 73}:${base64Encode(await File(path).readAsBytes())}';
  }

  Future<RestorePlan> prepareRestore(String root, String id) async {
    if (!(await backups(root)).any((b) => b.oid == id)) {
      throw GitFailure(FailureKind.other, '备份已不存在。');
    }
    final dir = await Directory.systemTemp.createTemp('zhixu-restore-');
    final exported = p.join(dir.path, 'files');
    await Directory(exported).create();
    try {
      final files = await backupFiles(root, id);
      final env = {'GIT_INDEX_FILE': p.join(dir.path, 'index')};
      for (final untracked in [false, true]) {
        final paths = files
            .where((f) => f.$2 == untracked)
            .map((f) => f.$1)
            .toList();
        if (paths.isEmpty) continue;
        for (final path in paths) {
          await destination(root, path);
        }
        final ref = untracked ? '$id^3' : id;
        final present = (await run(root, [
          'ls-tree',
          '-r',
          '--name-only',
          '-z',
          ref,
          '--',
          ...paths,
        ])).out;
        await run(root, ['read-tree', ref], env: env);
        if (present.isNotEmpty) {
          await run(
            root,
            [
              'checkout-index',
              '--prefix=${gitPath(exported)}/',
              '-z',
              '--stdin',
            ],
            env: env,
            input: present,
          );
        }
      }
      final items = <RestoreItem>[];
      for (final f in files) {
        items.add(
          RestoreItem(
            f.$1,
            p.join(exported, f.$1),
            await snapshot(await destination(root, f.$1)),
          ),
        );
      }
      return RestorePlan(dir, items);
    } catch (_) {
      await dir.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> applyRestore(
    String root,
    RestorePlan plan,
    Set<String> keep,
  ) async {
    for (final item in plan.items) {
      if (await snapshot(await destination(root, item.path)) != item.snapshot) {
        throw GitFailure(FailureKind.other, '文件在比较后已变化，请重新确认；未恢复任何文件。');
      }
    }
    for (final item in plan.items) {
      if (keep.contains(item.path)) continue;
      final target = await destination(root, item.path);
      final backup = await snapshot(item.source);
      if (backup == item.snapshot) continue;
      if (item.snapshot == 'directory') {
        throw GitFailure(FailureKind.other, '不能用备份替换文件夹。');
      }
      if (await snapshot(target) != item.snapshot) {
        throw GitFailure(FailureKind.other, '文件在恢复时发生变化，后续操作已停止，备份仍保留。');
      }
      if (backup == 'missing') {
        if (await FileSystemEntity.type(target, followLinks: false) !=
            FileSystemEntityType.notFound) {
          await File(target).delete();
        }
        continue;
      }
      await Directory(p.dirname(target)).create(recursive: true);
      final temporary =
          '$target.zhixu-restore-${DateTime.now().microsecondsSinceEpoch}';
      try {
        if (backup.startsWith('link:')) {
          await Link(temporary).create(await Link(item.source).target());
          await Link(temporary).rename(target);
        } else {
          await File(item.source).copy(temporary);
          if (!Platform.isWindows) {
            final mode = (await File(item.source).stat()).mode & 511;
            await Process.run('chmod', [mode.toRadixString(8), temporary]);
          }
          await File(temporary).rename(target);
        }
      } finally {
        if (await FileSystemEntity.type(temporary, followLinks: false) !=
            FileSystemEntityType.notFound) {
          await File(temporary).delete();
        }
      }
    }
  }

  Future<void> deleteBackupFile(
    String root,
    String id,
    String path,
    bool untracked,
  ) async {
    if (!(await backups(root)).any((b) => b.oid == id) ||
        !(await backupFiles(root, id)).contains((path, untracked))) {
      throw GitFailure(FailureKind.other, '备份内容已变化。');
    }
    final temp = await Directory.systemTemp.createTemp('zhixu-backup-edit-');
    final env = {'GIT_INDEX_FILE': p.join(temp.path, 'index')};
    try {
      final base = await oid(root, '$id^1');
      Future<String> tree(String ref, bool restore) async {
        await run(root, ['read-tree', ref], env: env);
        final entry = restore
            ? (await run(root, ['ls-tree', '-z', base, '--', path])).out
            : '';
        if (entry.isNotEmpty) {
          final f = entry.split('\t').first.split(' ');
          await run(root, [
            'update-index',
            '--add',
            '--cacheinfo',
            f[0],
            f[2],
            path,
          ], env: env);
        } else {
          await run(root, [
            'update-index',
            '--force-remove',
            '--',
            path,
          ], env: env);
        }
        return (await run(root, ['write-tree'], env: env)).out.trim();
      }

      Future<String> commit(
        String ref,
        String tree,
        List<String> parents,
      ) async {
        final meta = (await run(root, [
          'show',
          '-s',
          '--format=%an%x00%ae%x00%aI%x00%cn%x00%ce%x00%cI',
          ref,
        ])).out.trim().split('\x00');
        final msg = (await run(root, ['show', '-s', '--format=%B', ref])).out;
        return (await run(
          root,
          [
            'commit-tree',
            tree,
            for (final parent in parents) ...['-p', parent],
          ],
          input: msg,
          env: {
            'GIT_AUTHOR_NAME': meta[0],
            'GIT_AUTHOR_EMAIL': meta[1],
            'GIT_AUTHOR_DATE': meta[2],
            'GIT_COMMITTER_NAME': meta[3],
            'GIT_COMMITTER_EMAIL': meta[4],
            'GIT_COMMITTER_DATE': meta[5],
          },
        )).out.trim();
      }

      final oldIndex = await oid(root, '$id^2');
      final index = untracked
          ? oldIndex
          : await commit(oldIndex, await tree(oldIndex, true), [base]);
      final parents = [base, index];
      final third = await run(root, [
        'rev-parse',
        '--verify',
        '$id^3',
      ], check: false);
      if (third.code == 0) {
        final ref = third.out.trim();
        parents.add(
          untracked ? await commit(ref, await tree(ref, false), []) : ref,
        );
      }
      final replacement = await commit(
        id,
        untracked
            ? (await run(root, ['rev-parse', '$id^{tree}'])).out.trim()
            : await tree(id, true),
        parents,
      );
      await run(root, [
        'stash',
        'store',
        '-m',
        (await run(root, ['show', '-s', '--format=%s', id])).out.trim(),
        replacement,
      ]);
      await dropBackup(root, id);
    } finally {
      await temp.delete(recursive: true);
    }
  }
}
