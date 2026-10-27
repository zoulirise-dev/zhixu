import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// Convert native separators only on Windows. A backslash is a valid POSIX filename.
String gitPath(String value, {bool? windows}) =>
    (windows ?? Platform.isWindows) ? value.replaceAll(r'\', '/') : value;

/// Canonical repository-relative keys shared by Git and the file tree.
String repositoryRelative(String path, {required String from}) =>
    p.split(p.relative(path, from: from)).join('/');

enum FailureKind {
  cancelled,
  authentication,
  permission,
  network,
  worktreeConflict,
  other,
}

class GitFailure implements Exception {
  final FailureKind kind;
  final String message;
  GitFailure(this.kind, this.message);
  factory GitFailure.fromOutput(String output) {
    final s = output.toLowerCase();
    if (s.contains('would be overwritten') ||
        s.contains('local changes to the following files')) {
      return GitFailure(FailureKind.worktreeConflict, '切换会覆盖当前修改，请先选择如何处理。');
    }
    if (s.contains('could not resolve') ||
        s.contains('failed to connect') ||
        s.contains('timed out') ||
        s.contains('ssl certificate') ||
        s.contains('connection reset')) {
      return GitFailure(FailureKind.network, '无法连接远程仓库，请检查网络、代理或证书后重试。');
    }
    if (s.contains('403') ||
        s.contains('permission denied') ||
        s.contains('protected branch') ||
        s.contains('not allowed to push')) {
      return GitFailure(FailureKind.permission, '当前认证没有操作权限，或分支受到保护。请检查账号权限。');
    }
    if (s.contains('authentication failed') ||
        s.contains('could not read username') ||
        s.contains('could not read password') ||
        s.contains('401') ||
        s.contains('terminal prompts disabled') ||
        s.contains('invalid username or')) {
      return GitFailure(
        FailureKind.authentication,
        '需要登录此仓库。可使用电脑上的 Git 客户端登录后重试，或输入 HTTPS 凭据。',
      );
    }
    if (s.contains('non-fast-forward') || s.contains('fetch first')) {
      return GitFailure(FailureKind.other, '远程已有更新。请先获取并检查历史，不会强制覆盖远程。');
    }
    if (s.contains('index.lock')) {
      return GitFailure(FailureKind.other, '其他 Git 操作正在占用暂存区，请稍后重试。');
    }
    if (s.contains('author identity unknown') ||
        s.contains('unable to auto-detect email')) {
      return GitFailure(FailureKind.other, '尚未配置提交姓名和邮箱，请在本项目设置中填写。');
    }
    if (s.contains('not a git repository')) {
      return GitFailure(FailureKind.other, '此目录不是 Git 仓库。请在打开项目时初始化，或选择已有仓库。');
    }
    // Never surface raw output: servers and helpers can echo secrets.
    return GitFailure(
      FailureKind.other,
      'Git 操作未完成。请检查仓库状态、远程地址或 Git hooks；不会自动重试写入操作。',
    );
  }
  @override
  String toString() => message;
}

class Change {
  final String path;
  final String status;
  final String? oldPath;
  const Change(this.path, this.status, [this.oldPath]);
  List<String> get paths => [path, ?oldPath];
  bool get untracked => status == '??';
  String badgeFor({bool? staged}) {
    if (conflict) return '!';
    if (untracked) return 'U';
    final value = staged == null || status.length < 2
        ? status
        : status[staged ? 0 : 1];
    if (value.contains('D')) return 'D';
    if (value.contains('R') || value.contains('C')) return 'R';
    if (value.contains('A')) return 'A';
    return 'M';
  }

  bool get conflict => status.contains('U') || status == 'AA' || status == 'DD';
  static List<Change> parse(String text) {
    final entries = text.split('\x00');
    final result = <Change>[];
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      if (entry.length < 4) continue;
      final status = entry.substring(0, 2);
      String? old;
      if (status.contains('R') || status.contains('C')) {
        if (++i >= entries.length || entries[i].isEmpty) {
          throw GitFailure(FailureKind.other, '无法读取重命名状态，请刷新。');
        }
        old = entries[i];
      }
      // Copies do not select their unchanged source.
      result.add(
        Change(entry.substring(3), status, status.contains('R') ? old : null),
      );
    }
    return result;
  }
}

class GitReply {
  final int code;
  final String out;
  final String err;
  const GitReply(this.code, this.out, this.err);
}

class HttpsCredential {
  final Uri url;
  final String username;
  final String password;
  HttpsCredential(this.url, this.username, this.password) {
    if (url.scheme != 'https' ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        url.hasQuery ||
        url.hasFragment ||
        username.isEmpty ||
        password.isEmpty ||
        [
          username,
          password,
          url.toString(),
        ].any((s) => s.contains(RegExp(r'[\r\n\x00]'))) ||
        username.contains(':')) {
      throw GitFailure(FailureKind.other, '请使用不含账号密码的 HTTPS 地址，并填写有效的登录凭据。');
    }
  }
  String get input =>
      'protocol=https\nhost=${url.authority}\npath=${url.path.replaceFirst(RegExp(r'^/'), '')}\nusername=$username\npassword=$password\n\n';
  Map<String, String> get environment => {
    // Credentials never enter process arguments, repository config or logs.
    'GIT_CONFIG_COUNT': '3',
    'GIT_CONFIG_KEY_0': 'http.${url.toString()}.extraHeader',
    'GIT_CONFIG_VALUE_0':
        'Authorization: Basic ${base64Encode(utf8.encode('$username:$password'))}',
    'GIT_CONFIG_KEY_1': 'credential.helper', 'GIT_CONFIG_VALUE_1': '',
    'GIT_CONFIG_KEY_2': 'http.followRedirects', 'GIT_CONFIG_VALUE_2': 'false',
  };
}

class GitService {
  final String executable;
  final Map<String, String> environment;
  final bool usePlatformHelper;
  final Set<Process> _running = {};
  final Set<int> _cancelled = {};
  GitService({
    this.executable = 'git',
    this.environment = const {},
    this.usePlatformHelper = false,
  });

  Future<void> cancelRunning() async {
    for (final process in List<Process>.of(_running)) {
      _cancelled.add(process.pid);
      if (Platform.isWindows) {
        await Process.run('taskkill', ['/PID', '${process.pid}', '/T', '/F']);
      } else {
        process.kill(ProcessSignal.sigterm);
      }
    }
  }

  Future<List<String>> credentialPrefix(String root, String url) async {
    if (!usePlatformHelper ||
        !Platform.isMacOS ||
        !url.startsWith('https://')) {
      return [];
    }
    final configured = (await run(root, [
      'config',
      '--get-urlmatch',
      'credential.helper',
      url,
    ], check: false)).out.trim();
    if (configured.isNotEmpty) return [];
    final path = (await run(root, ['--exec-path'])).out.trim();
    return await File(p.join(path, 'git-credential-osxkeychain')).exists()
        ? ['-c', 'credential.helper=osxkeychain']
        : [];
  }

  static Future<GitService> discover() async {
    final candidates = <String>['git'];
    if (Platform.isMacOS) {
      candidates.addAll([
        '/usr/bin/git',
        '/opt/homebrew/bin/git',
        '/usr/local/bin/git',
      ]);
    }
    if (Platform.isWindows) {
      for (final key in ['ProgramFiles', 'ProgramFiles(x86)', 'LOCALAPPDATA']) {
        final base = Platform.environment[key];
        if (base != null) {
          candidates.addAll([
            p.join(base, 'Git', 'cmd', 'git.exe'),
            p.join(base, 'Programs', 'Git', 'cmd', 'git.exe'),
          ]);
        }
      }
    }
    for (final executable in candidates) {
      try {
        final git = GitService(executable: executable, usePlatformHelper: true);
        await git.run(Directory.current.path, ['--version']);
        return git;
      } catch (_) {
        /* Try next installation without changing the system. */
      }
    }
    throw GitFailure(
      FailureKind.other,
      '未找到 Git。请安装 Git（Windows 使用 Git for Windows）后重新打开应用。',
    );
  }

  Future<GitReply> run(
    String root,
    List<String> args, {
    Map<String, String> env = const {},
    String? input,
    bool check = true,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final process = await Process.start(
      executable,
      ['--literal-pathspecs', '-C', root, ...args],
      environment: {
        ...environment,
        'LC_ALL': 'C',
        'GIT_TERMINAL_PROMPT': '0',
        'GIT_TRACE': '0',
        'GIT_TRACE_CURL': '0',
        'GIT_CURL_VERBOSE': '0',
        ...env,
      },
      runInShell: false,
    );
    _running.add(process);
    final stdoutFuture = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    final stderrFuture = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    if (input != null) process.stdin.add(utf8.encode(input));
    await process.stdin.close();
    try {
      final code = await process.exitCode.timeout(timeout);
      final reply = GitReply(
        code,
        await stdoutFuture.timeout(
          const Duration(seconds: 5),
          onTimeout: () => '',
        ),
        await stderrFuture.timeout(
          const Duration(seconds: 5),
          onTimeout: () => '',
        ),
      );
      if (_cancelled.contains(process.pid)) {
        throw GitFailure(FailureKind.cancelled, '已取消网络操作。已完成的提交会保留，请刷新确认远程状态。');
      }
      if (check && code != 0) throw GitFailure.fromOutput(reply.err);
      return reply;
    } on TimeoutException {
      process.kill();
      throw GitFailure(FailureKind.network, '操作超时。若正在推送，请先获取并确认远程结果，再决定是否重试。');
    } finally {
      _running.remove(process);
      _cancelled.remove(process.pid);
    }
  }

  Future<String> open(String directory) async =>
      (await run(directory, ['rev-parse', '--show-toplevel'])).out.trim();
  Future<List<Change>> changes(String root) async => Change.parse(
    (await run(root, [
      'status',
      '--porcelain=v1',
      '-z',
      '--untracked-files=all',
    ])).out,
  );
  Future<String> branch(String root) async => (await run(root, [
    'symbolic-ref',
    '--short',
    'HEAD',
  ], check: false)).out.trim();
  Future<String> head(String root) async => (await run(root, [
    'rev-parse',
    '--verify',
    'HEAD',
  ], check: false)).out.trim();
  Future<List<String>> remotes(String root) async => (await run(root, [
    'remote',
  ])).out.split('\n').where((x) => x.isNotEmpty).toList();
  Future<String> config(String root, String key) async =>
      (await run(root, ['config', '--get', key], check: false)).out.trim();
  Future<void> saveAuthor(String root, String name, String email) async {
    if ([
      name,
      email,
    ].any((s) => s.trim().isEmpty || s.contains(RegExp(r'[\r\n<>\x00]')))) {
      throw GitFailure(FailureKind.other, '请填写有效的姓名和邮箱。');
    }
    await run(root, ['config', '--local', 'user.name', name.trim()]);
    await run(root, ['config', '--local', 'user.email', email.trim()]);
  }

  Future<String?> commitSelected(
    String root,
    List<Change> selected,
    String message, {
    bool stagedOnly = false,
  }) async {
    if (selected.isEmpty || message.trim().isEmpty) {
      throw GitFailure(FailureKind.other, '请勾选文件并填写提交说明。');
    }
    final current = await changes(root);
    if (current.any((c) => c.conflict)) {
      throw GitFailure(FailureKind.other, '请先解决冲突，再按文件提交。');
    }
    for (final ref in ['MERGE_HEAD', 'CHERRY_PICK_HEAD', 'REVERT_HEAD']) {
      if ((await run(root, [
            'rev-parse',
            '--verify',
            ref,
          ], check: false)).code ==
          0) {
        throw GitFailure(FailureKind.other, '仓库正在合并或还原，请先在现有客户端完成操作。');
      }
    }
    for (final name in ['rebase-merge', 'rebase-apply']) {
      final location = (await run(root, [
        'rev-parse',
        '--git-path',
        name,
      ])).out.trim();
      if (await Directory(
        p.isAbsolute(location) ? location : p.join(root, location),
      ).exists()) {
        throw GitFailure(FailureKind.other, '仓库正在变基，请先完成或中止变基。');
      }
    }
    final paths = <String>{};
    for (final choice in selected) {
      final matches = current.where(
        (c) =>
            c.path == choice.path &&
            c.status == choice.status &&
            c.oldPath == choice.oldPath,
      );
      if (matches.isEmpty) {
        throw GitFailure(FailureKind.other, '文件状态已变化，请刷新后重新确认。');
      }
      paths.addAll(choice.paths);
    }
    final beforeHead = await head(root);
    final indexPath = (await run(root, [
      'rev-parse',
      '--git-path',
      'index',
    ])).out.trim();
    final realIndex = File(
      p.isAbsolute(indexPath) ? indexPath : p.join(root, indexPath),
    );
    final beforeIndex = await realIndex.exists()
        ? base64Encode(await realIndex.readAsBytes())
        : '';
    final temp = await Directory.systemTemp.createTemp('zhixu-selected-');
    final env = {'GIT_INDEX_FILE': p.join(temp.path, 'index')};
    try {
      await run(
        root,
        beforeHead.isEmpty
            ? ['read-tree', '--empty']
            : ['read-tree', beforeHead],
        env: env,
      );
      if (stagedOnly) {
        final entries = (await run(root, [
          'ls-files',
          '--stage',
          '-z',
          '--',
          ...paths,
        ])).out;
        await run(root, [
          'update-index',
          '--force-remove',
          '--',
          ...paths,
        ], env: env);
        await run(
          root,
          ['update-index', '-z', '--index-info'],
          env: env,
          input: entries,
        );
      } else {
        await run(
          root,
          ['add', '-A', '--pathspec-from-file=-', '--pathspec-file-nul'],
          env: env,
          input: '${paths.join('\x00')}\x00',
        );
      }
      final included = (await run(root, [
        'diff',
        '--cached',
        '--name-only',
        '--no-renames',
        '-z',
      ], env: env)).out.split('\x00').where((s) => s.isNotEmpty).toSet();
      if (included.isEmpty || !paths.containsAll(included)) {
        throw GitFailure(FailureKind.other, '没有可提交内容或提交范围发生变化，已取消。');
      }
      final nowIndex = await realIndex.exists()
          ? base64Encode(await realIndex.readAsBytes())
          : '';
      if (await head(root) != beforeHead || nowIndex != beforeIndex) {
        throw GitFailure(FailureKind.other, '其他客户端改变了提交或暂存区，请刷新后重试。');
      }
      await run(root, ['commit', '-F', '-'], input: message, env: env);
      try {
        await run(root, [
          'reset',
          '-q',
          'HEAD',
          '--pathspec-from-file=-',
          '--pathspec-file-nul',
        ], input: '${paths.join('\x00')}\x00');
      } catch (_) {
        return '提交已成功，但暂存区同步失败。请刷新检查，不要重复提交。';
      }
      return null;
    } finally {
      await temp.delete(recursive: true);
    }
  }

  Future<String> diff(String root, Change c, {bool? staged}) async {
    if (c.untracked) {
      String content;
      try {
        content = await readFile(root, c.path);
      } catch (_) {
        return '此文件没有可显示的文本差异，可能为二进制、权限更改或内容过大。';
      }
      return '新增文件：${c.path}\n${content.split('\n').map((s) => '+$s').join('\n')}';
    }
    final reference = await head(root);
    if (reference.isEmpty || staged == true) {
      return (await run(root, [
        'diff',
        '--cached',
        '--no-ext-diff',
        '--no-textconv',
        '--unified=10000',
        '--',
        ...c.paths,
      ])).out;
    }
    return (await run(root, [
      'diff',
      '--no-ext-diff',
      '--no-textconv',
      '--unified=10000',
      if (staged == null) 'HEAD',
      '--',
      ...c.paths,
    ])).out;
  }

  Future<String> safePath(String root, String relative) async {
    final base = await Directory(root).resolveSymbolicLinks();
    final path = await File(p.join(base, relative)).resolveSymbolicLinks();
    if (!p.isWithin(base, path)) {
      throw GitFailure(FailureKind.other, '此链接指向项目外，不能编辑项目外文件。');
    }
    return path;
  }

  Future<Set<String>> ignoredPaths(String root, Iterable<String> paths) async {
    final names = paths.map((path) => gitPath(path)).toSet().toList();
    if (names.isEmpty) return {};
    // check-ignore takes literal names on stdin and rejects --literal-pathspecs.
    final result = await run(
      root,
      ['--no-literal-pathspecs', 'check-ignore', '-z', '--stdin'],
      input: '${names.join('\x00')}\x00',
      check: false,
    );
    if (result.code != 0 && result.code != 1) {
      throw GitFailure(FailureKind.other, '无法读取忽略规则，请刷新后重试。');
    }
    return result.out.split('\x00').where((name) => name.isNotEmpty).toSet();
  }

  /// Read the blob itself, never decode image bytes through UTF-8.
  Future<Uint8List?> imageAt(String root, String relative, String? ref) async {
    if (ref == null) {
      final path = p.normalize(p.join(root, relative));
      if (!p.isWithin(p.normalize(root), path)) {
        throw GitFailure(FailureKind.other, '路径不在项目内。');
      }
      if (!await File(path).exists()) return null;
      return readImage(root, relative);
    }
    final object = await run(root, [
      'rev-parse',
      '--verify',
      '--end-of-options',
      '$ref:${gitPath(relative)}',
    ], check: false);
    if (object.code != 0) return null;
    final oid = object.out.trim();
    if (!RegExp(r'^[0-9a-f]{40,64}$').hasMatch(oid)) {
      throw GitFailure(FailureKind.other, '图片无法加载');
    }
    final size = await run(root, ['cat-file', '-s', oid]);
    if ((int.tryParse(size.out.trim()) ?? 0) > 32 * 1024 * 1024) {
      throw GitFailure(FailureKind.other, '图片超过 32 MB，请使用系统图片查看器打开。');
    }
    final result = await Process.run(
      executable,
      ['--literal-pathspecs', '-C', root, 'cat-file', 'blob', oid],
      environment: {...environment, 'GIT_TERMINAL_PROMPT': '0'},
      stdoutEncoding: null,
    );
    if (result.exitCode != 0) throw GitFailure(FailureKind.other, '图片无法加载');
    return Uint8List.fromList(result.stdout as List<int>);
  }

  Future<Uint8List> readImage(String root, String relative) async {
    final file = File(await safePath(root, relative));
    if (await file.length() > 32 * 1024 * 1024) {
      throw GitFailure(FailureKind.other, '图片超过 32 MB，请使用系统图片查看器打开。');
    }
    return file.readAsBytes();
  }

  /// Git object names always use slash-separated paths, including on Windows.
  Future<String> editorBaseline(
    String root,
    String relative,
    String current,
  ) async {
    final path = gitPath(relative);
    final head = await run(root, ['show', 'HEAD:$path'], check: false);
    if (head.code == 0) return head.out;
    // A failed read is not proof that every line is new. Only a confirmed
    // addition/untracked file may use an empty baseline; ignored files stay neutral.
    final status = await run(root, [
      'status',
      '--porcelain=v1',
      '--untracked-files=all',
      '--',
      path,
    ], check: false);
    if (status.code == 0 &&
        (status.out.startsWith('?? ') ||
            status.out.startsWith('A ') ||
            status.out.startsWith(' A'))) {
      return '';
    }
    return current;
  }

  Future<String> readFile(String root, String relative) async {
    final file = File(await safePath(root, relative));
    if (await file.length() > 2 * 1024 * 1024) {
      throw GitFailure(FailureKind.other, '编辑器支持不超过 2 MB 的 UTF-8 文本。');
    }
    final bytes = await file.readAsBytes();
    if (bytes.contains(0)) throw GitFailure(FailureKind.other, '此文件不是可编辑文本。');
    try {
      return utf8.decode(bytes);
    } catch (_) {
      throw GitFailure(FailureKind.other, '文件不是 UTF-8 编码。');
    }
  }

  Future<void> saveFile(
    String root,
    String relative,
    String original,
    String text,
  ) async {
    final path = await safePath(root, relative);
    if (await readFile(root, relative) != original) {
      throw GitFailure(FailureKind.other, '文件已被其他程序修改，未覆盖。请保留编辑内容并重新打开比较。');
    }
    await File(path).writeAsString(text, flush: true);
  }

  Future<String> remoteURL(
    String root,
    String remote, {
    bool push = false,
  }) async {
    final urls = (await run(root, [
      'remote',
      'get-url',
      if (push) '--push',
      '--all',
      remote,
    ])).out.trim().split('\n');
    if (urls.length != 1) {
      throw GitFailure(FailureKind.other, '同一远程配置了多个地址。请拆分为独立远程仓库后操作。');
    }
    return urls.single;
  }

  Future<String> network(
    String root,
    String remote,
    String operation, {
    HttpsCredential? credential,
  }) async {
    final urls = credential != null
        ? [await remoteURL(root, remote, push: operation == 'push')]
        : (await run(root, [
            'remote',
            'get-url',
            if (operation == 'push') '--push',
            '--all',
            remote,
          ])).out.trim().split('\n');
    if (credential != null && urls.length != 1) {
      throw GitFailure(FailureKind.other, '此远程有多个地址，请先在电脑的 Git 中完成各地址认证，再重试。');
    }
    final url = urls.first;
    final prefix = await credentialPrefix(root, url);
    if (credential != null && credential.url.toString() != url) {
      throw GitFailure(FailureKind.other, '远程地址已改变，请重新确认。');
    }
    final args = switch (operation) {
      'check' => ['ls-remote', '--', url, 'HEAD'],
      'fetch' => ['fetch', '--', remote],
      'push' => await _pushArguments(root, remote),
      _ => throw ArgumentError.value(operation),
    };
    await run(
      root,
      [...prefix, ...args],
      env: credential?.environment ?? {},
      timeout: const Duration(minutes: 2),
    );
    if (credential != null) {
      final helper = (await run(root, [
        'config',
        '--get-urlmatch',
        'credential.helper',
        url,
      ], check: false)).out.trim();
      if (helper.isEmpty && prefix.isEmpty) {
        return '操作成功。电脑未配置 Git 凭据助手，本次未保存密码。';
      }
      try {
        await run(root, [
          ...prefix,
          'credential',
          'approve',
        ], input: credential.input);
      } catch (_) {
        return '操作成功，但系统凭据助手未能保存登录信息。';
      }
    }
    return operation == 'check' ? '远程连接成功（公开仓库不代表写入权限已验证）' : '操作完成';
  }

  Future<List<String>> _pushArguments(String root, String remote) async {
    final name = await branch(root);
    if (name.isEmpty) throw GitFailure(FailureKind.other, '请切换到本地分支后推送。');
    final tracked = await config(root, 'branch.$name.remote');
    final merge = await config(root, 'branch.$name.merge');
    final target = tracked == remote && merge.startsWith('refs/heads/')
        ? merge
        : 'refs/heads/$name';
    return [
      'push',
      '--no-follow-tags',
      if (tracked.isEmpty) '--set-upstream',
      '--',
      remote,
      'HEAD:$target',
    ];
  }
}
