import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'ui/directory_picker.dart';
import 'ui/native_close.dart' show syncWindowChrome, NativeModalObserver;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'core/git_service.dart';
import 'core/workflows.dart';
import 'core/completion.dart';
import 'ui/code_editor.dart';
import 'ui/theme.dart';
import 'ui/localization.dart';

import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'ui/diff_view.dart';
import 'ui/image_preview.dart';
part 'workspace/dialogs.dart';
part 'workspace/explorer.dart';

const appVersion = String.fromEnvironment(
  'FLUTTER_BUILD_NAME',
  defaultValue: '1.0.4',
);

final appearance = ValueNotifier<ThemeMode>(ThemeMode.system);
void main(List<String> args) =>
    runApp(ZhixuPrototype(initialPath: args.isEmpty ? null : args.first));

class ZhixuPrototype extends StatefulWidget {
  final String? initialPath;
  final GitService? service;
  const ZhixuPrototype({super.key, this.initialPath, this.service});
  @override
  State<ZhixuPrototype> createState() => _ZhixuPrototypeState();
}

class _ZhixuPrototypeState extends State<ZhixuPrototype> {
  final modalObserver = NativeModalObserver();
  @override
  void dispose() {
    modalObserver.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([appearance, uiLocale]),
    builder: (context, _) => MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorObservers: [modalObserver],
      title: '枝序 · 让 Git 简单一点',
      theme: workspaceTheme(Brightness.light),
      darkTheme: workspaceTheme(Brightness.dark),
      themeMode: appearance.value,
      locale: Locale(uiLanguage == 'English' ? 'en' : 'zh'),
      supportedLocales: const [Locale('en'), Locale('zh')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: WorkspacePage(
        initialPath: widget.initialPath,
        service: widget.service,
      ),
    ),
  );
}

class Document {
  String path;
  final bool diff;
  Uint8List? imageBytes;
  int previewRevision = 0;
  final CodeController controller;
  String original, patch, baseline;
  bool preview = false, pinned = false;
  final bool? staged;
  Document(
    this.path,
    this.diff,
    String text, {
    this.patch = '',
    this.baseline = '',
    this.staged,
  }) : original = text,
       controller = CodeController(text: text, language: sourceLanguage(path));
  String get id =>
      '${diff
          ? staged == null
                ? 'diff'
                : staged!
                ? 'staged'
                : 'working'
          : 'file'}:$path';
  bool get dirty => !diff && controller.text != original;
}

class WorkspacePage extends StatefulWidget {
  final String? initialPath;
  final GitService? service;
  const WorkspacePage({super.key, this.initialPath, this.service});
  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  GitService? git;
  String? root;
  String branch = '',
      status = '打开项目，开始工作',
      author = '',
      email = '',
      upstream = '';
  List<String> projects = [], remotes = [];
  List<Change> changes = [];
  Set<String> checked = {};
  List<CommitInfo> commits = [];
  Set<String> pendingPush = {};
  bool completionEnabled = true;
  bool stagedCollapsed = false, unstagedCollapsed = false;
  bool changesRefreshing = false, networkActive = false, missingGit = false;
  final branchAnchor = GlobalKey();
  final List<Document> documents = [];
  Document? document;
  final message = TextEditingController(), search = TextEditingController();
  int tab = 0, revision = 0, ahead = 0, behind = 0, historyPage = 0;
  bool busy = false, advanced = false, splitHover = false, historyMore = true;
  double listWidth = 300;
  String? operationKind, treeSelection, clipboardPath;
  bool clipboardCut = false;
  Set<String> treeSelected = {};
  List<String> clipboardPaths = [];
  String? changeAnchor;
  AppLifecycleListener? lifecycle;
  String language = Platform.localeName.startsWith('zh') ? '中文' : 'English';
  String? get file => document?.path;
  bool get dirty => documents.any((d) => d.dirty);
  File get preferences => File(
    p.join(
      Platform.environment[Platform.isWindows ? 'APPDATA' : 'HOME'] ??
          Directory.systemTemp.path,
      Platform.isWindows
          ? 'ZhixuFlutter'
          : 'Library/Application Support/ZhixuFlutter',
      'preferences.json',
    ),
  );
  @override
  void initState() {
    super.initState();
    search.addListener(redraw);
    message.addListener(redraw);
    lifecycle = AppLifecycleListener(
      onExitRequested: () async => busy
          ? AppExitResponse.cancel
          : await allowLeave()
          ? AppExitResponse.exit
          : AppExitResponse.cancel,
    );
    initialize();
  }

  void mutate(VoidCallback action) {
    if (mounted) setState(action);
  }

  void redraw() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    lifecycle?.dispose();
    message.dispose();
    search.dispose();
    for (final d in documents) {
      d.controller.dispose();
    }
    super.dispose();
  }

  Future<void> initialize() async {
    try {
      git = widget.service ?? await GitService.discover();
      missingGit = false;
      if (widget.service == null && Platform.isMacOS) {
        try {
          final languages = await const MethodChannel('app.zhixu/desktop')
              .invokeListMethod<String>('preferredLanguages');
          language = languages?.firstOrNull?.startsWith('zh') == true
              ? '中文'
              : 'English';
        } catch (_) {}
      }
      String? lastProject;
      if (widget.service == null && await preferences.exists()) {
        final data = jsonDecode(await preferences.readAsString()) as Map;
        projects = List<String>.from(data['projects'] ?? []);
        appearance.value = ThemeMode.values.firstWhere(
          (v) => v.name == data['theme'],
          orElse: () => ThemeMode.system,
        );
        advanced = data['advanced'] == true;
        completionEnabled = data['completion'] != false;
        final last = data['lastProject'];
        if (last is String && projects.contains(last)) lastProject = last;
        language = data['language'] ?? language;
      }
      uiLanguage = widget.service == null ? language : '中文';
      if (widget.initialPath != null) {
        await openProject(widget.initialPath!);
      } else if (projects.isNotEmpty) {
        await openProject(lastProject ?? projects.first);
      } else {
        redraw();
      }
    } catch (e) {
      missingGit = git == null;
      status = e is GitFailure ? e.message : '无法读取应用设置。';
      redraw();
    }
  }

  Future<void> remember() async {
    if (widget.service != null) return;
    await preferences.parent.create(recursive: true);
    await preferences.writeAsString(
      jsonEncode({
        'projects': projects,
        'theme': appearance.value.name,
        'language': language,
        'lastProject': root,
        'advanced': advanced,
        'completion': completionEnabled,
      }),
    );
  }

  Future<void> perform(String title, Future<void> Function() action) async {
    if (busy || !mounted) return;
    // Read-only dialog preparation must not repaint every toolbar button disabled.
    final quiet = title.startsWith('正在读取');
    final previousStatus = status;
    void start() {
      busy = true;
      status = title;
    }

    if (quiet) {
      start();
    } else {
      setState(start);
    }
    try {
      await action();
    } catch (e) {
      if (mounted) {
        status = e is GitFailure ? e.message : '操作未完成，请检查文件权限、路径或 Git 配置。';
        redraw();
        if (e is! GitFailure || e.kind != FailureKind.cancelled) {
          await notice('操作未完成', status);
        }
      }
    } finally {
      if (mounted) {
        void finish() {
          busy = false;
          if (status == title) status = quiet ? previousStatus : '操作完成';
        }

        if (quiet) {
          finish();
        } else {
          setState(finish);
        }
      }
    }
  }

  Future<void> notice(String title, String text) => showDialog<void>(
    context: context,
    builder: (c) => ZDialog(
      title: title,
      actions: [
        ZButton(text: '知道了', primary: true, onTap: () => Navigator.pop(c)),
      ],
      child: T(text, style: TextStyle(fontSize: 12, height: 1.7)),
    ),
  );
  Future<bool> confirm(
    String title,
    String detail, {
    String action = '确定',
    bool danger = false,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => ZDialog(
          title: title,
          actions: [
            ZButton(
              text: '取消',
              quiet: false,
              onTap: () => Navigator.pop(c, false),
            ),
            ZButton(
              text: action,
              primary: !danger,
              danger: danger,
              quiet: false,
              onTap: () => Navigator.pop(c, true),
            ),
          ],
          child: T(detail, style: TextStyle(height: 1.7, fontSize: 12)),
        ),
      ) ??
      false;
  Future<String?> prompt(
    String title, {
    String value = '',
    String hint = '',
    String action = '确定',
  }) async {
    final controller = TextEditingController(text: value);
    final result = await showDialog<String>(
      context: context,
      builder: (c) => ZDialog(
        title: title,
        width: 440,
        actions: [
          ZButton(text: '取消', quiet: false, onTap: () => Navigator.pop(c)),
          ZButton(
            text: action,
            primary: true,
            onTap: () => Navigator.pop(c, controller.text),
          ),
        ],
        child: TextField(
          autofocus: true,
          controller: controller,
          style: TextStyle(fontSize: 12),
          decoration: InputDecoration(hintText: tr(hint)),
          onSubmitted: (s) => Navigator.pop(c, s),
        ),
      ),
    );
    await Future<void>.delayed(Duration(milliseconds: 250));
    controller.dispose();
    return result;
  }

  Future<bool> allowLeave({Document? only}) async {
    for (final d
        in only == null ? documents.where((d) => d.dirty).toList() : [only]) {
      if (!d.dirty) continue;
      if (!mounted) return false;
      final result = await showDialog<int>(
        context: context,
        builder: (c) => ZDialog(
          title: '保存对「${p.basename(d.path)}」的修改？',
          width: 430,
          actions: [
            ZButton(
              text: '不保存',
              quiet: false,
              onTap: () => Navigator.pop(c, 1),
            ),
            ZButton(text: '取消', quiet: false, onTap: () => Navigator.pop(c, 0)),
            ZButton(
              text: '保存',
              primary: true,
              onTap: () => Navigator.pop(c, 2),
            ),
          ],
          child: T('关闭前保存，或放弃此文件的编辑。', style: TextStyle(color: Colors.grey)),
        ),
      );
      if (result == null || result == 0) return false;
      if (result == 2) {
        await saveDocument(d);
        if (d.dirty) return false;
      }
    }
    return true;
  }

  Future<void> chooseProject() async {
    if (busy) return;
    final path = await chooseDirectory(context, '打开项目');
    if (path != null && mounted) await openProject(path);
  }

  Future<void> createProject() async {
    final parent = await chooseDirectory(context, '选择保存位置');
    if (parent == null || !mounted) return;
    final name = await prompt('创建新项目', hint: '项目名称');
    if (name == null || name.trim().isEmpty) return;
    var created = false;
    await perform('正在创建项目…', () async {
      if (name.contains(RegExp(r'[/\\]')) || name == '.' || name == '..') {
        throw GitFailure(FailureKind.other, '请输入项目名称，不包含路径。');
      }
      final dir = Directory(p.join(parent, name));
      if (await dir.exists()) {
        throw GitFailure(FailureKind.other, '同名目录已存在，请使用打开项目。');
      }
      await dir.create();
      await git!.run(dir.path, ['init', '-b', 'main']);
      created = true;
    });
    if (created) {
      await openProject(p.join(parent, name));
    }
  }

  Future<void> openProject(String directory) async {
    if (busy || git == null || !await allowLeave()) return;
    String next;
    try {
      next = await git!.open(directory);
    } on GitFailure {
      var bare = false;
      try {
        bare =
            (await git!.run(directory, [
              'rev-parse',
              '--is-bare-repository',
            ])).out.trim() ==
            'true';
      } catch (_) {}
      if (bare ||
          !await Directory(directory).exists() ||
          await FileSystemEntity.type(
                p.join(directory, '.git'),
                followLinks: false,
              ) !=
              FileSystemEntityType.notFound) {
        await notice('无法打开项目', 'Git 数据已存在但无法读取，或目录不可访问。请检查路径和权限；不会重新初始化。');
        return;
      }
      if (!await confirm(
        '初始化 Git 项目？',
        '此目录还不是 Git 仓库。初始化会保留现有文件，让你选择需要提交的内容。',
        action: '初始化',
      )) {
        return;
      }
      await perform('正在初始化…', () async {
        await git!.run(directory, ['init', '-b', 'main']);
      });
      try {
        next = await git!.open(directory);
      } catch (_) {
        return;
      }
    }
    await perform('正在打开项目…', () async {
      for (final d in documents) {
        d.controller.dispose();
      }
      documents.clear();
      document = null;
      root = next;
      changes = [];
      checked = {};
      commits = [];
      search.clear();
      historyPage = 0;
      if (!projects.contains(next)) projects.add(next);
      await remember();
      await refresh(initial: true);
    });
  }

  Future<void> refresh({bool initial = false}) async {
    final path = root;
    if (path == null) return;
    final values = await Future.wait<Object>([
      git!.changes(path),
      git!.branch(path),
      git!.remotes(path),
      git!.config(path, 'user.name'),
      git!.config(path, 'user.email'),
    ]);
    if (!mounted || root != path) return;
    changes = values[0] as List<Change>;
    branch = values[1] as String;
    remotes = values[2] as List<String>;
    author = values[3] as String;
    email = values[4] as String;
    checked = initial
        ? changes.where((c) => !c.conflict).map((c) => c.path).toSet()
        : checked.intersection(changes.map((c) => c.path).toSet());
    try {
      final c = await git!.counts(path);
      ahead = c.$1;
      behind = c.$2;
      upstream = c.$3;
      operationKind = await git!.operation(path);
    } catch (_) {
      /* A repository may be replaced externally during refresh. */
    }
    for (final d in documents) {
      d.previewRevision++;
      try {
        if (d.imageBytes != null) {
          d.imageBytes = await git!.readImage(path, d.path);
        } else if (d.diff) {
          final items = changes.where((c) => c.path == d.path);
          d.patch = items.isEmpty
              ? ''
              : await git!.diff(path, items.first, staged: d.staged);
        } else {
          d.baseline = await git!.editorBaseline(path, d.path, d.original);
          if (!d.dirty && d.controller.value.composing.isCollapsed) {
            final text = await git!.readFile(path, d.path);
            if (text != d.original) {
              final selection = d.controller.selection;
              d.original = text;
              d.controller.value = TextEditingValue(
                text: text,
                selection: TextSelection(
                  baseOffset: selection.baseOffset.clamp(0, text.length),
                  extentOffset: selection.extentOffset.clamp(0, text.length),
                ),
              );
            }
          }
        }
      } catch (_) {
        /* Keep the last readable buffer; saving still checks disk. */
      }
    }
    revision++;
    status = '已更新 · ${changes.length} 个变更';
    redraw();
    if (tab == 2) await loadHistory(reset: true);
  }

  Future<void> refreshChangesOnly() async {
    if (busy || changesRefreshing || root == null) return;
    final current = root!;
    mutate(() => changesRefreshing = true);
    try {
      final next = await git!.changes(current);
      if (!mounted || root != current) return;
      mutate(() {
        changes = next;
        checked = checked.intersection(next.map((c) => c.path).toSet());
        status = '已更新 · ${next.length} 个变更';
      });
    } catch (e) {
      if (mounted) {
        await notice('刷新未完成', e is GitFailure ? e.message : '无法读取仓库状态。');
      }
    } finally {
      mutate(() => changesRefreshing = false);
    }
  }

  Future<void> loadHistory({bool reset = false, int? page}) async {
    if (root == null) return;
    final targetPage = reset ? 0 : page ?? historyPage;
    final next = await git!.history(root!, skip: targetPage * 80);
    final upstream = await git!.run(root!, [
      'rev-parse',
      '--verify',
      '@{upstream}',
    ], check: false);
    final pending = await git!.run(
      root!,
      upstream.code == 0
          ? ['rev-list', '${upstream.out.trim()}..HEAD']
          : ['rev-list', 'HEAD', '--not', '--remotes'],
      check: false,
    );
    if (!mounted) return;
    setState(() {
      historyPage = targetPage;
      commits = next;
      pendingPush = pending.out.split('\n').where((s) => s.isNotEmpty).toSet();
      historyMore = next.length == 80;
    });
  }

  Future<void> openFile(
    String path, {
    Change? change,
    bool? staged,
    bool pin = false,
  }) async {
    if (busy || root == null) return;
    path = gitPath(path);
    if (change?.conflict ?? false) {
      await conflictDialog(change!);
      return;
    }
    final id =
        '${change == null
            ? 'file'
            : staged == null
            ? 'diff'
            : staged
            ? 'staged'
            : 'working'}:$path';
    final existing = documents.where((d) => d.id == id);
    if (existing.isNotEmpty) {
      setState(() {
        document = existing.first;
        if (pin) document!.pinned = true;
      });
      return;
    }
    await perform('正在打开文件…', () async {
      final isImage = change == null && isPreviewImage(path);
      final bytes = isImage ? await git!.readImage(root!, path) : null;
      final text = change == null && !isImage
          ? await git!.readFile(root!, path)
          : '';
      final patch = change == null
          ? ''
          : await git!.diff(root!, change, staged: staged);
      final baseline = change == null && !isImage
          ? await git!.editorBaseline(root!, path, text)
          : '';
      final d = Document(
        path,
        change != null,
        text,
        patch: patch,
        baseline: baseline,
        staged: staged,
      );
      d.imageBytes = bytes;
      d.pinned = pin;
      d.controller.addListener(() {
        if (d.dirty) d.pinned = true;
        redraw();
      });
      final transient = documents
          .where((tab) => !tab.pinned && !tab.dirty)
          .toList();
      for (final old in transient) {
        documents.remove(old);
        Future<void>.delayed(
          const Duration(milliseconds: 250),
          old.controller.dispose,
        );
      }
      documents.add(d);
      document = d;
      status = '文件已打开';
      redraw();
    });
  }

  Future<void> closeDocument(Document d) async {
    if (!await allowLeave(only: d) || !mounted) return;
    setState(() {
      documents.remove(d);
      if (document == d) document = documents.isEmpty ? null : documents.last;
    });
    await Future<void>.delayed(Duration(milliseconds: 20));
    d.controller.dispose();
  }

  Future<void> saveDocument(Document d) async {
    if (d.imageBytes != null || !d.dirty || busy) return;
    if (!d.controller.value.composing.isCollapsed) {
      status = '请先完成输入法候选词，再保存';
      redraw();
      return;
    }
    await perform('正在保存…', () async {
      final text = d.controller.text;
      await git!.saveFile(root!, d.path, d.original, text);
      d.original = text;
      await refresh();
      status = '文件已保存';
    });
  }

  Future<void> commit({bool push = false}) async {
    if (dirty) {
      await notice('请先保存编辑', '提交使用磁盘文件，请先保存编辑器内的修改。');
      return;
    }
    final selectedRemote = push
        ? await selectRemote(operation: 'push', commitFirst: true)
        : null;
    if (push && selectedRemote == null) return;
    var success = false;
    await perform('正在提交…', () async {
      final items = changes
          .where(
            (c) =>
                checked.contains(c.path) &&
                (!advanced || c.status[0] != ' ' && !c.untracked),
          )
          .toList();
      final warning = await git!.commitSelected(
        root!,
        items,
        message.text,
        stagedOnly: advanced,
      );
      message.clear();
      await refresh();
      status = warning ?? '提交成功';
      success = true;
    });
    if (success && push) await network('push', chosenRemote: selectedRemote);
  }

  Future<String?> selectRemote({
    String operation = 'fetch',
    bool commitFirst = false,
  }) async {
    if (remotes.isEmpty) {
      await notice('没有远程仓库', '请先在设置中新增远程仓库。');
      return null;
    }
    if (remotes.length == 1) return remotes.first;
    final targets = <String, (String, List<String>)>{};
    final current = await git!.branch(root!);
    final tracked = await git!.config(root!, 'branch.$current.remote');
    final merge = await git!.config(root!, 'branch.$current.merge');
    for (final r in remotes) {
      final urls = (await git!.run(root!, [
        'remote',
        'get-url',
        if (operation == 'push') '--push',
        '--all',
        r,
      ])).out.trim().split('\n');
      targets[r] = (
        tracked == r && merge.startsWith('refs/heads/')
            ? merge.substring(11)
            : current,
        urls,
      );
    }
    if (!mounted) return null;
    var selected = remotes.contains(tracked) ? tracked : remotes.first;
    if (operation == 'push') {
      for (final key in ['branch.$current.pushRemote', 'remote.pushDefault']) {
        final candidate = await git!.config(root!, key);
        if (remotes.contains(candidate)) {
          selected = candidate;
          break;
        }
      }
    }
    final verb = operation == 'push'
        ? '推送'
        : operation == 'pull'
        ? '拉取'
        : '获取';
    if (!mounted) return null;
    return showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => ZDialog(
          title: operation == 'pull' ? '选择拉取来源' : '选择$verb目标',
          width: 508,
          actions: [
            ZButton(text: '取消', onTap: () => Navigator.pop(c)),
            ZButton(
              text: commitFirst ? '提交并推送' : verb,
              primary: true,
              onTap: () => Navigator.pop(c, selected),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              T('本地分支：$current'),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 340),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final entry in targets.entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: selected == entry.key
                                  ? brand
                                  : Colors.transparent,
                            ),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: HoverRow(
                            selected: selected == entry.key,
                            onTap: () => update(() => selected = entry.key),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        entry.key,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const Spacer(),
                                      if (selected == entry.key)
                                        const Icon(
                                          Icons.check_circle,
                                          size: 16,
                                          color: brand,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  T(
                                    '${operation == 'pull' ? '来源分支' : '目标分支'}：${entry.value.$1}',
                                  ),
                                  for (final url in entry.value.$2)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        url,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              T(
                operation == 'push'
                    ? '仅推送到所选远程；已有的分支跟踪关系保持不变。首次推送会建立跟踪关系。'
                    : '从所选远程的对应分支拉取到当前分支，不改变跟踪关系。',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> network(String operation, {String? chosenRemote}) async {
    if (busy || root == null) return;
    final remote = chosenRemote ?? await selectRemote(operation: operation);
    if (remote == null) return;
    networkActive = true;
    try {
      await perform(
        operation == 'push'
            ? '正在推送…'
            : operation == 'pull'
            ? '正在拉取…'
            : '正在获取…',
        () async {
          final action = operation == 'pull' ? 'fetch' : operation;
          try {
            status = await git!.network(root!, remote, action);
          } on GitFailure catch (e) {
            if (e.kind != FailureKind.authentication) rethrow;
            final credentials = await login(
              await git!.remoteURL(root!, remote, push: action == 'push'),
            );
            if (credentials == null) {
              status = '已取消登录';
              return;
            }
            status = await git!.network(
              root!,
              remote,
              action,
              credential: credentials,
            );
          }
          if (operation == 'pull') {
            final current = await git!.branch(root!);
            final tracked = await git!.config(root!, 'branch.$current.remote');
            final merge = await git!.config(root!, 'branch.$current.merge');
            final target =
                'refs/remotes/$remote/${tracked == remote && merge.startsWith('refs/heads/') ? merge.substring(11) : current}';
            await git!.requireClean(root!);
            final result = await git!.run(root!, [
              'merge',
              '--ff-only',
              await git!.oid(root!, target),
            ], check: false);
            if (result.code != 0) {
              if (await confirm(
                '本地与远程已分叉',
                '两边都有新提交。可以生成合并提交，保留双方历史；若产生冲突，将打开冲突处理流程。',
                action: '合并远程更新',
              )) {
                await git!.integrate(root!, target);
              } else {
                status = '已获取远程更新，尚未合并';
              }
            }
          }
          final result = status;
          await refresh();
          status = result;
        },
      );
    } finally {
      mutate(() => networkActive = false);
    }
  }

  void workspaceAction(VoidCallback action) {
    final navigator = Navigator.of(context);
    if (!busy && !navigator.canPop()) action();
  }

  Widget panel(Widget child, {bool subtle = false}) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: subtle ? subtleColor(context) : panelColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: inkColor(context).withValues(alpha: .045)),
      ),
      child: child,
    ),
  );
  Widget small(String text) => T(
    text,
    style: TextStyle(fontSize: 10, color: Colors.grey),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );
  String shortPath(String path) =>
      path.replaceFirst(Platform.environment['HOME'] ?? '\x00', '~');
  @override
  Widget build(BuildContext context) {
    syncWindowChrome(
      Theme.of(context).brightness == Brightness.dark,
      tr('枝序 · 让 Git 简单一点'),
    );
    final workspace = CallbackShortcuts(
      bindings: {
        SingleActivator(
          LogicalKeyboardKey.keyN,
          meta: Platform.isMacOS,
          control: !Platform.isMacOS,
        ): () =>
            workspaceAction(createProject),
        SingleActivator(
          LogicalKeyboardKey.comma,
          meta: Platform.isMacOS,
          control: !Platform.isMacOS,
        ): () =>
            workspaceAction(settings),
        SingleActivator(
          LogicalKeyboardKey.keyS,
          meta: Platform.isMacOS,
          control: !Platform.isMacOS,
        ): () {
          if (document != null) saveDocument(document!);
        },
        SingleActivator(
          LogicalKeyboardKey.keyO,
          meta: Platform.isMacOS,
          control: !Platform.isMacOS,
        ): chooseProject,
        SingleActivator(
          LogicalKeyboardKey.keyR,
          meta: Platform.isMacOS,
          control: !Platform.isMacOS,
        ): () =>
            refreshChangesOnly(),
        SingleActivator(
          LogicalKeyboardKey.enter,
          meta: Platform.isMacOS,
          control: !Platform.isMacOS,
        ): () {
          if (checked.isNotEmpty && message.text.trim().isNotEmpty) commit();
        },
        SingleActivator(
          LogicalKeyboardKey.keyW,
          meta: Platform.isMacOS,
          control: !Platform.isMacOS,
        ): () {
          if (document != null) closeDocument(document!);
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Padding(
            padding: EdgeInsets.fromLTRB(12, Platform.isMacOS ? 45 : 12, 12, 0),
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 220,
                        child: panel(sidebar(), subtle: true),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          children: [
                            panel(toolbar()),
                            SizedBox(height: 10),
                            Expanded(
                              child: root == null && !missingGit
                                  ? panel(welcome())
                                  : Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        SizedBox(
                                          width: listWidth,
                                          child: panel(filePanel()),
                                        ),
                                        MouseRegion(
                                          cursor: SystemMouseCursors
                                              .resizeLeftRight,
                                          onEnter: (_) =>
                                              setState(() => splitHover = true),
                                          onExit: (_) => setState(
                                            () => splitHover = false,
                                          ),
                                          child: GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onHorizontalDragUpdate: (d) =>
                                                setState(
                                                  () => listWidth =
                                                      (listWidth + d.delta.dx)
                                                          .clamp(270, 420),
                                                ),
                                            child: SizedBox(
                                              width: 8,
                                              child: Center(
                                                child: Container(
                                                  width: splitHover ? 2 : 1,
                                                  color: splitHover
                                                      ? brand
                                                      : inkColor(context)
                                                            .withValues(
                                                              alpha: .06,
                                                            ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Expanded(child: panel(editorPanel())),
                                      ],
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 26,
                  child: Row(
                    children: [
                      if (busy)
                        SizedBox(
                          width: 9,
                          height: 9,
                          child: CircularProgressIndicator(strokeWidth: 1.4),
                        )
                      else
                        Icon(Icons.circle, size: 6, color: Colors.green),
                      SizedBox(width: 8),
                      Expanded(child: small(status)),
                      if (networkActive)
                        ZButton(
                          text: '取消',
                          height: 22,
                          onTap: () => git!.cancelRunning(),
                        ),
                      if (upstream.isNotEmpty) ...[
                        BranchSymbol(),
                        SizedBox(width: 5),
                        small(upstream),
                        SizedBox(width: 20),
                      ],
                      small(
                        '$appVersion · ${Platform.isWindows ? 'Windows' : 'macOS'}',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!Platform.isMacOS ||
        Theme.of(context).platform != TargetPlatform.macOS) {
      return workspace;
    }
    return PlatformMenuBar(
      menus: [
        PlatformMenu(
          label: tr('枝序'),
          menus: [
            PlatformMenuItem(
              label: tr('设置…'),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.comma,
                meta: true,
              ),
              onSelected: busy ? null : () => workspaceAction(settings),
            ),
            PlatformMenuItem(
              label: tr('退出枝序'),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyQ,
                meta: true,
              ),
              onSelected: () =>
                  const MethodChannel('app.zhixu/desktop')
                      .invokeMethod<void>('windowAction', 'quit'),
            ),
          ],
        ),
        PlatformMenu(
          label: tr('文件'),
          menus: [
            PlatformMenuItem(
              label: tr('打开项目'),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyO,
                meta: true,
              ),
              onSelected: busy ? null : () => workspaceAction(chooseProject),
            ),
            PlatformMenuItem(
              label: tr('创建新项目'),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyN,
                meta: true,
              ),
              onSelected: busy ? null : () => workspaceAction(createProject),
            ),
            PlatformMenuItem(
              label: tr('保存文件'),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyS,
                meta: true,
              ),
              onSelected: document?.dirty == true && !busy
                  ? () => workspaceAction(() => saveDocument(document!))
                  : null,
            ),
            PlatformMenuItem(
              label: tr('关闭当前文件'),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyW,
                meta: true,
              ),
              onSelected: document != null && !busy
                  ? () => workspaceAction(() => closeDocument(document!))
                  : null,
            ),
          ],
        ),
        PlatformMenu(
          label: tr('编辑'),
          menus: [
            PlatformMenuItem(
              label: tr('撤销'),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyZ,
                meta: true,
              ),
              onSelectedIntent: const UndoTextIntent(
                SelectionChangedCause.keyboard,
              ),
            ),
            PlatformMenuItem(
              label: tr('重做'),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyZ,
                meta: true,
                shift: true,
              ),
              onSelectedIntent: const RedoTextIntent(
                SelectionChangedCause.keyboard,
              ),
            ),
            PlatformMenuItem(
              label: tr('剪切'),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyX,
                meta: true,
              ),
              onSelectedIntent: const CopySelectionTextIntent.cut(
                SelectionChangedCause.keyboard,
              ),
            ),
            PlatformMenuItem(
              label: tr('复制'),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyC,
                meta: true,
              ),
              onSelectedIntent: CopySelectionTextIntent.copy,
            ),
            PlatformMenuItem(
              label: tr('粘贴'),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyV,
                meta: true,
              ),
              onSelectedIntent: const PasteTextIntent(
                SelectionChangedCause.keyboard,
              ),
            ),
            PlatformMenuItem(
              label: tr('全选'),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyA,
                meta: true,
              ),
              onSelectedIntent: const SelectAllTextIntent(
                SelectionChangedCause.keyboard,
              ),
            ),
          ],
        ),
        PlatformMenu(
          label: 'Git',
          menus: [
            PlatformMenuItem(
              label: tr('刷新变更'),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyR,
                meta: true,
              ),
              onSelected: busy
                  ? null
                  : () => workspaceAction(refreshChangesOnly),
            ),
            PlatformMenuItem(
              label: tr('提交所选文件'),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.enter,
                meta: true,
              ),
              onSelected:
                  !busy && checked.isNotEmpty && message.text.trim().isNotEmpty
                  ? () => workspaceAction(commit)
                  : null,
            ),
          ],
        ),
        PlatformMenu(
          label: tr('窗口'),
          menus: [
            PlatformMenuItem(
              label: tr('最小化'),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyM,
                meta: true,
              ),
              onSelected: () =>
                  const MethodChannel('app.zhixu/desktop')
                      .invokeMethod<void>('windowAction', 'minimize'),
            ),
            PlatformMenuItem(
              label: tr('缩放窗口'),
              onSelected: () =>
                  const MethodChannel('app.zhixu/desktop')
                      .invokeMethod<void>('windowAction', 'zoom'),
            ),
            PlatformMenuItem(
              label: tr('切换全屏'),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyF,
                meta: true,
                control: true,
              ),
              onSelected: () =>
                  const MethodChannel('app.zhixu/desktop')
                      .invokeMethod<void>('windowAction', 'fullscreen'),
            ),
          ],
        ),
      ],
      child: workspace,
    );
  }

  Widget welcome() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset('assets/AppIcon.png', width: 56, height: 56),
        const SizedBox(height: 20),
        T(
          '开始你的下一个项目',
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        T(
          '管理分支、审阅修改、提交代码。\n所有项目，一个工作空间。',
          textAlign: TextAlign.center,
          style: const TextStyle(height: 1.7, color: Colors.grey),
        ),
        const SizedBox(height: 32),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ZButton(text: '创建新项目', primary: true, onTap: createProject),
            const SizedBox(width: 14),
            ZButton(text: '打开已有项目', quiet: false, onTap: chooseProject),
          ],
        ),
        const SizedBox(height: 46),
        T(
          '多项目切换    ·    逐文件暂存    ·    内置代码编辑',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    ),
  );

  Widget sidebar() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Row(
          children: [
            Image.asset('assets/AppIcon.png', width: 30, height: 30),
            SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  T(
                    '枝序',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  small('让 Git 简单一点'),
                ],
              ),
            ),
          ],
        ),
      ),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 22),
        child: Row(
          children: [small('我的项目'), Spacer(), small('${projects.length}')],
        ),
      ),
      SizedBox(height: 12),
      Expanded(
        child: ReorderableListView.builder(
          buildDefaultDragHandles: false,
          onReorderItem: (oldIndex, newIndex) {
            if (busy) return;
            setState(() {
              projects.insert(newIndex, projects.removeAt(oldIndex));
            });
            remember();
          },
          proxyDecorator: (child, index, animation) => Material(
            color: panelColor(context),
            borderRadius: BorderRadius.circular(8),
            elevation: 5,
            child: child,
          ),
          padding: EdgeInsets.symmetric(horizontal: 12),
          itemCount: projects.length,
          itemBuilder: (context, i) {
            final path = projects[i];
            return Padding(
              key: ValueKey('project:$path'),
              padding: const EdgeInsets.only(bottom: 6),
              child: ReorderableDragStartListener(
                index: i,
                enabled: !busy,
                child: HoverRow(
                  selected: path == root,
                  onTap: busy ? null : () => openProject(path),
                  onSecondaryTapDown: (d) =>
                      contextMenu(context, d.globalPosition, [
                        MenuAction(
                          Platform.isMacOS ? '在访达中显示' : '在资源管理器中显示',
                          () => reveal(path),
                          icon: Icons.folder_outlined,
                        ),
                        MenuAction('从列表移除（保留文件）', () async {
                          if (await confirm('移除项目？', '仅从列表移除，不删除磁盘文件。')) {
                            if (root == path && !await allowLeave()) return;
                            projects.remove(path);
                            await remember();
                            if (root == path) {
                              root = null;
                              document = null;
                              changes = [];
                            }
                            redraw();
                          }
                        }, icon: Icons.remove_circle_outline),
                      ]),
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      if (path == root)
                        Container(
                          width: 2,
                          height: 24,
                          decoration: BoxDecoration(
                            color: brand,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            ProjectStackIcon(
                              color: path == root ? brand : Colors.grey,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  T(
                                    p.basename(path),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  MiddleText(
                                    shortPath(path),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (path == root)
                              Icon(Icons.circle, size: 5, color: brand),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
      Padding(
        padding: EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ZButton(
              text: '创建新项目',
              icon: Icons.add,
              primary: true,
              onTap: busy || git == null ? null : createProject,
            ),
            SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              children: [
                ZButton(
                  text: '打开项目',
                  onTap: busy || git == null ? null : chooseProject,
                ),
                ZButton(
                  text: '克隆仓库',
                  onTap: busy || git == null ? null : cloneProject,
                ),
              ],
            ),
          ],
        ),
      ),
    ],
  );
  Widget toolbar() => SizedBox(
    height: 52,
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                T(
                  root == null ? '工作空间' : p.basename(root!),
                  maxLines: 1,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 4),
                small(root == null ? '打开项目，开始工作' : shortPath(root!)),
              ],
            ),
          ),
          if (root != null) ...[
            ZButton(
              text: branch.isEmpty ? '游离 HEAD' : branch,
              leading: BranchSymbol(),
              key: branchAnchor,
              tooltip: '选择分支',
              onTap: busy ? null : branchMenu,
            ),
            SizedBox(width: 10),
            ZButton(
              text: '待推送 $ahead 条',
              icon: Icons.arrow_circle_up,
              selected: ahead > 0,
              onTap: () => selectTab(2),
            ),
            SizedBox(width: 6),
            if (upstream.isNotEmpty)
              ZButton(
                text: '待拉取 $behind 条${ahead > 0 && behind > 0 ? ' · 已分叉' : ''}',
                icon: Icons.arrow_circle_down,
                onTap: () => reviewDialog('@{upstream}', compare: true),
              ),
            SizedBox(width: 12),
            Container(
              width: 1,
              height: 22,
              color: inkColor(context).withValues(alpha: .1),
            ),
            SizedBox(width: 6),
            for (final item in [
              ('fetch', '获取', Icons.refresh),
              ('pull', '拉取', Icons.arrow_downward),
              ('push', '推送', Icons.arrow_upward),
            ])
              ZButton(
                text: item.$2,
                icon: item.$3,
                loading: busy && status.contains('正在${item.$2}'),
                onTap: busy ? null : () => network(item.$1),
              ),
            ZButton(
              icon: Icons.sync,
              tooltip: '刷新本地状态',
              onTap: busy ? null : () => refreshChangesOnly(),
            ),
          ],
          ZButton(
            icon: Icons.settings_outlined,
            tooltip: '设置',
            onTap: busy ? null : settings,
          ),
        ],
      ),
    ),
  );
  Future<void> selectTab(int next) async {
    setState(() => tab = next);
    if (next == 2) await perform('正在读取历史…', () => loadHistory(reset: true));
  }

  Widget filePanel() => Column(
    children: [
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: SizedBox(
          height: 48,
          child: Row(
            children: [
              for (final item in [
                (0, '变更', Icons.edit_square),
                (1, '文件', Icons.folder_outlined),
                (2, '历史', Icons.history),
              ])
                Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      ZButton(
                        text: item.$2,
                        icon: item.$3,
                        selected: tab == item.$1,
                        onTap: () => selectTab(item.$1),
                      ),
                      if (tab == item.$1)
                        Container(width: 24, height: 2, color: brand),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      if (tab == 0) ...[
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            height: 28,
            child: Row(
              children: [
                T(
                  '工作区变更',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                SizedBox(width: 8),
                small('${changes.length}'),
                Spacer(),
                ZButton(
                  icon: Icons.refresh,
                  height: 24,
                  tooltip: '刷新列表，保留编辑和勾选',
                  loading: changesRefreshing,
                  onTap: root == null || busy || changesRefreshing
                      ? null
                      : () => refreshChangesOnly(),
                ),
                Builder(
                  builder: (c) => ZButton(
                    icon: Icons.more_horiz,
                    height: 24,
                    tooltip: '更多',
                    onTap: () => contextMenu(
                      context,
                      (c.findRenderObject() as RenderBox).localToGlobal(
                        Offset(0, 24),
                      ),
                      [
                        MenuAction(advanced ? '退出高级模式' : '高级模式：手动暂存', () {
                          setState(() => advanced = !advanced);
                          remember();
                        }, icon: Icons.tune),
                        MenuAction(
                          '临时收起修改',
                          stashChanges,
                          icon: Icons.archive_outlined,
                          enabled: root != null && !busy && changes.isNotEmpty,
                        ),
                        MenuAction(
                          '临时收起的修改…',
                          backupsDialog,
                          icon: Icons.inventory_2_outlined,
                          enabled: root != null && !busy,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (operationKind != null || changes.any((c) => c.conflict))
          Padding(
            padding: EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                T(
                  operationKind == null ? '存在待解决的冲突' : '正在进行：$operationKind',
                  style: TextStyle(color: Colors.orange, fontSize: 12),
                ),
                SizedBox(height: 6),
                small('点击冲突文件，保存并标记已解决后继续。'),
                if (operationKind != null)
                  Row(
                    children: [
                      ZButton(
                        text: '继续操作',
                        onTap: busy || changes.any((c) => c.conflict)
                            ? null
                            : () => perform('正在继续…', () async {
                                await git!.finishOperation(root!);
                                await refresh();
                              }),
                      ),
                      ZButton(
                        text: '中止…',
                        danger: true,
                        onTap: busy
                            ? null
                            : () async {
                                if (await confirm(
                                  '中止当前操作？',
                                  '将返回操作前状态。操作开始后的修改可能丢失。',
                                  action: '中止',
                                  danger: true,
                                )) {
                                  await perform('正在中止…', () async {
                                    await git!.finishOperation(
                                      root!,
                                      abort: true,
                                    );
                                    await refresh();
                                  });
                                }
                              },
                      ),
                    ],
                  ),
              ],
            ),
          ),
        Expanded(
          child: changes.isEmpty
              ? Center(child: small('工作区干净，没有待提交的修改'))
              : ListView(
                  children: [
                    if (!advanced) allCheck(),
                    if (advanced) ...[
                      groupHeader('未暂存', false),
                      if (!unstagedCollapsed)
                        for (final c in changes.where(
                          (c) => c.untracked || c.status[1] != ' ',
                        ))
                          changeRow(c, staged: false),
                      groupHeader('已暂存', true),
                      if (!stagedCollapsed)
                        for (final c in changes.where(
                          (c) => !c.untracked && c.status[0] != ' ',
                        ))
                          changeRow(c, staged: true),
                    ] else
                      for (final c in changes) changeRow(c),
                  ],
                ),
        ),
        commitBox(),
      ] else if (tab == 1) ...[
        Padding(
          padding: EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 30,
                  child: TextField(
                    controller: search,
                    style: TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      hintText: tr('搜索项目文件…'),
                      suffixIcon: search.text.isEmpty
                          ? null
                          : ZButton(
                              icon: Icons.close,
                              tooltip: '清空搜索',
                              onTap: search.clear,
                            ),
                      prefixIcon: Icon(Icons.search, size: 14),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 30,
                        minHeight: 30,
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 6),
              ZButton(
                icon: Icons.refresh,
                tooltip: '刷新列表，保留编辑和勾选',
                onTap: busy || root == null
                    ? null
                    : () async {
                        await refreshChangesOnly();
                        mutate(() => revision++);
                      },
              ),
            ],
          ),
        ),
        Expanded(
          child: root == null
              ? SizedBox()
              : ExplorerTree(
                  key: ValueKey(root),
                  root: root!,
                  git: git!,
                  revision: revision,
                  filter: search.text,
                  selected: treeSelection ?? file,
                  cut: clipboardCut ? clipboardPath : null,
                  cutPaths: clipboardCut ? clipboardPaths.toSet() : {},
                  changes: changes,
                  onPin: (path) => openFile(path, pin: true),
                  onOpen: (path) {
                    treeSelection = path;
                    openFile(path);
                  },
                  onSelect: (path) => treeSelection = path,
                  onMultiSelect: (paths) => mutate(() => treeSelected = paths),
                  onContext: fileMenu,
                  onClipboard: clipboardAction,
                ),
        ),
        Padding(
          padding: EdgeInsets.all(10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: small(
              treeSelected.isEmpty ? '' : '已选 ${treeSelected.length} 项',
            ),
          ),
        ),
      ] else ...[
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              T(
                '提交历史',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              Spacer(),
              ZButton(
                icon: Icons.refresh,
                tooltip: '刷新历史',
                onTap: busy || root == null
                    ? null
                    : () => perform('正在读取历史…', () => loadHistory(reset: true)),
              ),
            ],
          ),
        ),
        Expanded(
          child: commits.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.history,
                        size: 28,
                        color: Colors.grey.withValues(alpha: .45),
                      ),
                      const SizedBox(height: 10),
                      T(historyPage == 0 ? '暂无提交历史' : '本页暂无记录'),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: T(
                          historyPage == 0
                              ? '完成首次提交后，历史记录会显示在这里。'
                              : '请返回上一页查看。',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  key: ValueKey(historyPage),
                  itemCount: commits.length,
                  itemBuilder: (c, i) {
                    final entry = commits[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Column(
                        children: [
                          HoverRow(
                            onTap: busy ? null : () => reviewDialog(entry.oid),
                            onSecondaryTapDown: (d) =>
                                historyMenu(entry, d.globalPosition),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 12,
                                horizontal: 8,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.radio_button_checked,
                                    color: brand,
                                    size: 13,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${entry.oid.substring(0, 7)}  ${entry.subject}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        small(
                                          '${entry.author} · ${entry.date.replaceFirst('T', ' ').substring(0, 16)}',
                                        ),
                                        if (pendingPush.contains(entry.oid))
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 6,
                                            ),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 3,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: brand.withValues(
                                                  alpha: .09,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(5),
                                              ),
                                              child: T(
                                                '↑ 未推送',
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  color: brand,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Divider(
                            height: 1,
                            color: inkColor(context).withValues(alpha: .06),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        if (commits.isNotEmpty || historyPage > 0)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ZButton(
                  text: '上一页',
                  icon: Icons.chevron_left,
                  onTap: busy || historyPage == 0
                      ? null
                      : () => perform(
                          '正在读取历史…',
                          () => loadHistory(page: historyPage - 1),
                        ),
                ),
                const Spacer(),
                small('第 ${historyPage + 1} 页'),
                const Spacer(),
                ZButton(
                  text: '下一页',
                  icon: Icons.chevron_right,
                  onTap: busy || !historyMore
                      ? null
                      : () => perform(
                          '正在读取历史…',
                          () => loadHistory(page: historyPage + 1),
                        ),
                ),
              ],
            ),
          ),
      ],
    ],
  );
  Widget allCheck() => SizedBox(
    height: 26,
    child: Row(
      children: [
        SizedBox(width: 10),
        SizedBox(
          width: 26,
          child: CompactCheckbox(
            value:
                changes.isNotEmpty &&
                checked.length == changes.where((c) => !c.conflict).length,
            onChanged: busy
                ? null
                : (v) => setState(
                    () => checked = v == true
                        ? changes
                              .where((c) => !c.conflict)
                              .map((c) => c.path)
                              .toSet()
                        : {},
                  ),
          ),
        ),
        SizedBox(width: 6),
        small('全选'),
      ],
    ),
  );
  Widget groupHeader(String name, bool staged) => Padding(
    padding: EdgeInsets.fromLTRB(16, 6, 10, 4),
    child: Row(
      children: [
        ZButton(
          text: name,
          height: 24,
          icon: (staged ? stagedCollapsed : unstagedCollapsed)
              ? Icons.chevron_right
              : Icons.expand_more,
          onTap: () => mutate(() {
            if (staged) {
              stagedCollapsed = !stagedCollapsed;
            } else {
              unstagedCollapsed = !unstagedCollapsed;
            }
          }),
        ),
        Spacer(),
        ZButton(
          text: staged ? '取消暂存所选' : '暂存所选',
          height: 24,
          onTap: busy
              ? null
              : () => perform('正在更新暂存区…', () async {
                  await git!.stage(
                    root!,
                    changes.where((c) => checked.contains(c.path)).toList(),
                    undo: staged,
                  );
                  await refresh();
                }),
        ),
      ],
    ),
  );
  Widget changeRow(Change c, {bool staged = false}) => Padding(
    padding: EdgeInsets.symmetric(horizontal: 10),
    child: HoverRow(
      selected:
          checked.contains(c.path) ||
          (document?.diff == true && document?.path == c.path),
      onTap: busy
          ? null
          : () {
              if (HardwareKeyboard.instance.isShiftPressed &&
                  changeAnchor != null) {
                final a = changes.indexWhere((x) => x.path == changeAnchor),
                    b = changes.indexOf(c);
                if (a >= 0) {
                  checked.addAll(
                    changes
                        .sublist(a < b ? a : b, (a > b ? a : b) + 1)
                        .where((x) => !x.conflict)
                        .map((x) => x.path),
                  );
                  redraw();
                }
              }
              changeAnchor = c.path;
              openFile(c.path, change: c, staged: advanced ? staged : null);
            },
      onSecondaryTapDown: (d) => changeMenu(c, d.globalPosition),
      child: SizedBox(
        height: 24,
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: CompactCheckbox(
                value: checked.contains(c.path),
                onChanged: busy || c.conflict
                    ? null
                    : (v) => setState(() {
                        if (v == true) {
                          checked.add(c.path);
                        } else {
                          checked.remove(c.path);
                        }
                      }),
              ),
            ),
            FileSymbol(c.path),
            SizedBox(width: 5),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      p.basename(c.path),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 12,
                        color: changeBadgeColor(
                          c.badgeFor(staged: advanced ? staged : null),
                        ),
                      ),
                    ),
                  ),
                  if (p.dirname(c.path) != '.') ...[
                    const SizedBox(width: 5),
                    Flexible(
                      child: MiddleText(
                        p.dirname(c.path),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            ChangeBadge(
              c.badgeFor(staged: advanced ? staged : null),
              key: ValueKey('change-status:${c.path}'),
            ),
            SizedBox(width: 8),
          ],
        ),
      ),
    ),
  );
  Widget commitBox() {
    final can =
        !busy &&
        checked.isNotEmpty &&
        message.text.trim().isNotEmpty &&
        root != null;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: subtleColor(context),
        border: Border(
          top: BorderSide(color: inkColor(context).withValues(alpha: .07)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              T(
                '提交更改',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              Spacer(),
              small(Platform.isMacOS ? '⌘ ↵' : 'Ctrl ↵'),
            ],
          ),
          if (author.isNotEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: small('$author · $email'),
            ),
          SizedBox(height: 4),
          SizedBox(
            // 18 pt line height × 2.5 lines + 7 pt padding on each side.
            height: 59,
            child: TextField(
              key: Key('commit-message'),
              controller: message,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              textAlignVertical: TextAlignVertical.top,
              maxLines: null,
              expands: true,
              style: const TextStyle(fontSize: 12, height: 1.5),
              strutStyle: const StrutStyle(
                fontSize: 12,
                height: 1.5,
                forceStrutHeight: true,
              ),
              decoration: InputDecoration(
                hintText: tr('填写提交说明…'),
                fillColor: panelColor(context),
                contentPadding: EdgeInsets.fromLTRB(10, 7, 10, 7),
              ),
            ),
          ),
          SizedBox(height: 6),
          small('已选择 ${checked.length} 个文件${advanced ? '的暂存内容' : ''}'),
          SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: ZButton(
                  text: '提交',
                  icon: Icons.check,
                  quiet: false,
                  onTap: can ? () => commit() : null,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: ZButton(
                  text: '提交并推送',
                  icon: Icons.arrow_upward,
                  primary: true,
                  onTap: can ? () => commit(push: true) : null,
                ),
              ),
            ],
          ),
          SizedBox(height: 6),
          Center(
            child: T(
              advanced ? '仅提交勾选文件的已暂存内容' : '仅提交勾选文件 · 自动准备提交内容',
              style: TextStyle(fontSize: 9, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Widget editorPanel() => Column(
    children: [
      if (document != null)
        Container(
          height: 32,
          color: subtleColor(context),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final d in documents)
                        GestureDetector(
                          onDoubleTap: () => mutate(() => d.pinned = true),
                          child: Container(
                            decoration: BoxDecoration(
                              color: d == document
                                  ? panelColor(context)
                                  : Colors.transparent,
                              border: Border(
                                top: BorderSide(
                                  color: d == document
                                      ? brand
                                      : Colors.transparent,
                                  width: 2,
                                ),
                                right: BorderSide(
                                  color: inkColor(context)
                                      .withValues(alpha: .07),
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                ZButton(
                                  height: 30,
                                  text:
                                      '${p.basename(d.path)}${d.diff ? ' · 差异' : ''}',
                                  leading: FileSymbol(d.path),
                                  onTap: () => setState(() => document = d),
                                  italic: !d.pinned,
                                ),
                                if (d.dirty)
                                  Icon(Icons.circle, size: 6, color: brand),
                                ZButton(
                                  icon: Icons.close,
                                  height: 20,
                                  tooltip: '关闭文件',
                                  onTap: () => closeDocument(d),
                                ),
                                SizedBox(width: 5),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (!document!.diff && document!.path.endsWith('.md'))
                ZButton(
                  text: document!.preview ? '原文' : '预览',
                  icon: Icons.visibility_outlined,
                  height: 24,
                  selected: true,
                  onTap: () =>
                      setState(() => document!.preview = !document!.preview),
                ),
              if (!document!.diff && document!.imageBytes == null)
                ZButton(
                  icon: Icons.save_outlined,
                  height: 24,
                  tooltip: '保存 ${Platform.isMacOS ? '⌘' : 'Ctrl'}+S',
                  onTap: () => saveDocument(document!),
                ),
            ],
          ),
        ),
      Expanded(
        child: missingGit
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    T('首次使用：安装 Git'),
                    const SizedBox(height: 12),
                    T('未检测到可用的 Git，请安装后重新检查。'),
                    const SizedBox(height: 12),
                    ZButton(
                      text: Platform.isMacOS ? '安装命令行工具' : '下载 Git for Windows',
                      primary: true,
                      onTap: () async {
                        if (Platform.isMacOS) {
                          await Process.run('/usr/bin/xcode-select', [
                            '--install',
                          ]);
                        } else {
                          await openUrl('https://git-scm.com/downloads/win');
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    ZButton(text: '重新检查', onTap: initialize),
                  ],
                ),
              )
            : document == null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: subtleColor(context),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        Icons.code,
                        size: 32,
                        color: Color(0xffcccccc),
                      ),
                    ),
                    SizedBox(height: 18),
                    T(
                      '选择文件以查看修改',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 14),
                    T(
                      '在左侧查看变更，或切换到文件树编辑代码。',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    SizedBox(height: 38),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final x in [
                          ('O', '打开项目'),
                          ('S', '保存文件'),
                          ('R', '刷新状态'),
                        ])
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              children: [
                                T(
                                  '${Platform.isMacOS ? '⌘' : 'Ctrl'} ${x.$1}',
                                  style: TextStyle(
                                    fontFamily: codeFontFamily,
                                    fontFamilyFallback: codeFontFallback,
                                    fontSize: 12,
                                  ),
                                ),
                                SizedBox(height: 12),
                                small(x.$2),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              )
            : document!.imageBytes != null
            ? ImagePreview(
                key: ValueKey(document!.id),
                bytes: document!.imageBytes!,
              )
            : document!.diff
            ? isPreviewImage(document!.path)
                  ? GitImageComparison(
                      key: ValueKey(
                        '${document!.id}:${document!.previewRevision}',
                      ),
                      git: git!,
                      root: root!,
                      path: document!.path,
                      beforePath: changes
                          .where((c) => c.path == document!.path)
                          .firstOrNull
                          ?.oldPath,
                      before: document!.staged == false ? '' : 'HEAD',
                      after: document!.staged == true ? '' : null,
                    )
                  : DiffView(document!.patch, path: document!.path)
            : document!.preview
            ? markdownPreview(document!.controller.text)
            : CodeEditor(
                key: PageStorageKey(document!.id),
                controller: document!.controller,
                baseline: document!.baseline,
                assistance: completionEnabled,
              ),
      ),
      if (document != null)
        Container(
          height: 22,
          color: subtleColor(context),
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(child: small(document!.path)),
              small(
                document!.imageBytes != null
                    ? '图片 · 只读'
                    : document!.diff
                    ? 'Diff · 只读'
                    : '行 ${document!.controller.text.substring(0, document!.controller.selection.baseOffset.clamp(0, document!.controller.text.length)).split('\n').length}，列 ${document!.controller.text.substring(0, document!.controller.selection.baseOffset.clamp(0, document!.controller.text.length)).split('\n').last.length + 1}',
              ),
              SizedBox(width: 12),
              small(
                document!.imageBytes != null
                    ? p
                          .extension(document!.path)
                          .replaceFirst('.', '')
                          .toUpperCase()
                    : sourceLanguage(document!.path),
              ),
              const SizedBox(width: 12),
              if (document!.imageBytes == null) small('UTF-8'),
            ],
          ),
        ),
    ],
  );
}
