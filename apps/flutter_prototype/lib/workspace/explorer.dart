part of '../main.dart';

const desktopChannel = MethodChannel('app.zhixu/desktop');

extension _WorkspaceExplorer on _WorkspacePageState {
  Future<void> openUrl(String url) async {
    if (Platform.isMacOS) {
      await Process.run('/usr/bin/open', [url]);
    } else if (Platform.isWindows) {
      await Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
    }
  }

  Future<void> reveal(String path) async {
    if (Platform.isMacOS) {
      await Process.run(
        '/usr/bin/open',
        await Directory(path).exists() ? [path] : ['-R', path],
      );
    } else if (Platform.isWindows) {
      await Process.run(
        'explorer.exe',
        await Directory(path).exists() ? [path] : ['/select,', path],
      );
    }
  }

  Future<void> trash(String path) async {
    if (Platform.isMacOS) {
      await desktopChannel.invokeMethod('trash', {'path': path});
    } else if (Platform.isWindows) {
      final result = await Process.run(
        'powershell.exe',
        [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          r'Add-Type -AssemblyName Microsoft.VisualBasic; if (Test-Path -LiteralPath $env:ZHIXU_TRASH_PATH -PathType Container) { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($env:ZHIXU_TRASH_PATH,"OnlyErrorDialogs","SendToRecycleBin") } else { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($env:ZHIXU_TRASH_PATH,"OnlyErrorDialogs","SendToRecycleBin") }',
        ],
        environment: {'ZHIXU_TRASH_PATH': path},
      );
      if (result.exitCode != 0) {
        throw GitFailure(FailureKind.other, '未能移到回收站，文件未删除。');
      }
    } else {
      throw GitFailure(FailureKind.other, '当前平台不支持移到废纸篓。');
    }
  }

  void changeMenu(Change c, Offset point) => contextMenu(context, point, [
    MenuAction(
      '打开文件',
      () => openFile(c.path),
      icon: Icons.code,
      enabled: !c.status.contains('D'),
    ),
    MenuAction(
      '撤销更改…',
      () => discardFiles([c]),
      icon: Icons.undo,
      destructive: true,
    ),
    if (checked.length == changes.length && changes.isNotEmpty)
      MenuAction(
        '撤销所有更改…',
        () => discardFiles(changes),
        icon: Icons.restore,
        destructive: true,
      ),
    MenuAction('查看文件历史', () => fileHistory(c.path), icon: Icons.history),
    MenuAction(
      '忽略此文件',
      () => ignoreEntry(c.path, 'file'),
      icon: Icons.visibility_off_outlined,
    ),
    if (advanced)
      MenuAction(
        '暂存文件',
        () => perform('正在暂存…', () async {
          await git!.stage(root!, [c]);
          await refresh();
        }),
        icon: Icons.add,
      ),
    if (advanced)
      MenuAction(
        '取消暂存',
        () => perform('正在取消暂存…', () async {
          await git!.stage(root!, [c], undo: true);
          await refresh();
        }),
        icon: Icons.remove,
      ),
  ]);
  Future<void> discardFiles(
    List<Change> selected, {
    bool confirmed = false,
    bool insideOperation = false,
  }) async {
    final expectedHead = await git!.head(root!);
    final expectedIndex = (await git!.run(root!, [
      'ls-files',
      '--stage',
      '-z',
      '--',
      ...selected.expand((c) => c.paths),
    ])).out;
    final snapshots = <String, String>{};
    for (final path in selected.expand((c) => c.paths)) {
      snapshots[path] = await git!.snapshot(
        await git!.destination(root!, path),
      );
    }
    if (!confirmed &&
        !await confirm(
          selected.length == 1 ? '撤销此文件的更改？' : '撤销所有更改？',
          '已暂存、未暂存修改恢复到最近提交；新增文件移到废纸篓。\n\n${selected.map((c) => c.path).join('\n')}',
          action: '撤销更改',
          danger: true,
        )) {
      return;
    }
    Future<void> discard() async {
      if (await git!.head(root!) != expectedHead ||
          (await git!.run(root!, [
                'ls-files',
                '--stage',
                '-z',
                '--',
                ...snapshots.keys,
              ])).out !=
              expectedIndex) {
        throw GitFailure(FailureKind.other, '仓库状态已变化，请重新确认撤销。');
      }
      for (final entry in snapshots.entries) {
        if (await git!.snapshot(await git!.destination(root!, entry.key)) !=
            entry.value) {
          throw GitFailure(FailureKind.other, '文件已变化，请重新确认撤销。');
        }
      }
      final current = await git!.changes(root!);
      for (final c in selected) {
        if (!current.any(
          (x) =>
              x.path == c.path &&
              x.status == c.status &&
              x.oldPath == c.oldPath,
        )) {
          throw GitFailure(FailureKind.other, '文件状态已变化，请刷新后重新确认。');
        }
      }
      final hasHead = (await git!.head(root!)).isNotEmpty;
      for (final c in selected) {
        for (final path in c.paths) {
          final target = await git!.destination(root!, path);
          final tracked =
              hasHead &&
              (await git!.run(root!, [
                'ls-tree',
                '-z',
                'HEAD',
                '--',
                path,
              ])).out.isNotEmpty;
          if (tracked) {
            await git!.run(root!, [
              'restore',
              '--source=HEAD',
              '--staged',
              '--worktree',
              '--',
              path,
            ]);
          } else {
            if (await FileSystemEntity.type(target, followLinks: false) !=
                FileSystemEntityType.notFound) {
              await trash(target);
            }
            await git!.run(root!, [
              'rm',
              '--cached',
              '--ignore-unmatch',
              '--',
              path,
            ], check: false);
          }
        }
        for (final d
            in documents.where((d) => c.paths.contains(d.path)).toList()) {
          documents.remove(d);
          if (document == d) document = null;
          d.controller.dispose();
        }
      }
      await refresh();
    }

    if (insideOperation) {
      await discard();
    } else {
      await perform('正在撤销更改…', discard);
    }
  }

  Future<void> ignoreEntry(String path, String kind) =>
      perform('正在更新忽略规则…', () async {
        await git!.ignore(root!, path, kind);
        await refresh();
      });
  void fileMenu(String? path, bool folder, Offset point) {
    final parent = path == null
        ? ''
        : folder
        ? path
        : p.dirname(path) == '.'
        ? ''
        : p.dirname(path);
    contextMenu(context, point, [
      MenuAction(
        '创建文件…',
        () => createEntry(parent, false),
        icon: Icons.note_add_outlined,
      ),
      MenuAction(
        '创建文件夹…',
        () => createEntry(parent, true),
        icon: Icons.create_new_folder_outlined,
      ),
      MenuAction(
        Platform.isMacOS ? '在访达中打开' : '在资源管理器中打开',
        () => reveal(p.join(root!, path ?? '')),
        icon: Icons.folder_open,
      ),
      if (path != null) ...[
        MenuAction('剪切', () => clipboardAction('x', path), icon: Icons.cut),
        MenuAction('复制', () => clipboardAction('c', path), icon: Icons.copy),
      ],
      MenuAction(
        '粘贴',
        () => pasteEntry(parent),
        icon: Icons.paste,
        enabled: clipboardPath != null,
      ),
      if (path != null) ...[
        MenuAction('重命名…', () => renameEntry(path), icon: Icons.edit_outlined),
        MenuAction(
          '移到废纸篓…',
          () => deleteEntries(
            treeSelected.contains(path) ? treeSelected : {path},
          ),
          icon: Icons.delete_outline,
          destructive: true,
        ),
        if (!folder)
          MenuAction('查看文件历史', () => fileHistory(path), icon: Icons.history),
        MenuAction(
          folder ? '忽略此文件夹' : '忽略此文件',
          () => ignoreEntry(path, folder ? 'folder' : 'file'),
          icon: Icons.visibility_off_outlined,
        ),
        if (!folder && p.extension(path).isNotEmpty)
          MenuAction(
            '忽略此类文件 (${p.extension(path)})',
            () => ignoreEntry(path, 'type'),
            icon: Icons.filter_alt_outlined,
          ),
      ],
    ]);
  }

  Future<void> deleteEntries(Set<String> entries) async {
    final paths = entries
        .where(
          (entry) => !entries.any(
            (parent) => parent != entry && p.isWithin(parent, entry),
          ),
        )
        .toList();
    if (!await confirm(
      '移到废纸篓？',
      '将选中的 ${paths.length} 项移到废纸篓，可从系统恢复。\n\n${paths.join('\n')}',
      action: '移到废纸篓',
      danger: true,
    )) {
      return;
    }
    final docs = documents
        .where(
          (d) =>
              paths.any((path) => d.path == path || p.isWithin(path, d.path)),
        )
        .toList();
    for (final d in docs) {
      if (!await allowLeave(only: d)) return;
    }
    await perform('正在移到废纸篓…', () async {
      for (final path in paths) {
        await trash(await git!.destination(root!, path));
      }
      for (final d in docs) {
        documents.remove(d);
        if (document == d) document = null;
        d.controller.dispose();
      }
      treeSelected.clear();
      treeSelection = null;
      await refresh();
    });
  }

  void clipboardAction(String action, String? path) {
    if (action == 'v') {
      () async {
        final folder =
            path != null && await Directory(p.join(root!, path)).exists();
        await pasteEntry(
          path == null
              ? ''
              : folder
              ? path
              : p.dirname(path) == '.'
              ? ''
              : p.dirname(path),
        );
      }();
    } else if (path != null) {
      mutate(() {
        final selected = treeSelected.contains(path) ? treeSelected : {path};
        clipboardPaths = selected
            .where(
              (entry) => !selected.any(
                (parent) => parent != entry && p.isWithin(parent, entry),
              ),
            )
            .map((s) => p.join(root!, s))
            .toList();
        clipboardPath = clipboardPaths.first;
        clipboardCut = action == 'x';
      });
    }
  }

  Future<void> createEntry(String parent, bool folder) async {
    final name = await prompt(folder ? '创建文件夹' : '创建文件', hint: '名称');
    if (name == null || name.trim().isEmpty) return;
    await perform('正在创建…', () async {
      if (name.contains(RegExp(r'[/\\]')) || name == '.' || name == '..') {
        throw GitFailure(FailureKind.other, '请输入单个名称。');
      }
      final target = await git!.destination(root!, p.join(parent, name));
      if (await FileSystemEntity.type(target, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw GitFailure(FailureKind.other, '同名项目已存在。');
      }
      if (folder) {
        await Directory(target).create();
      } else {
        await File(target).writeAsString('');
      }
      await refresh();
    });
  }

  Future<void> renameEntry(String path) async {
    final name = await prompt('重命名', value: p.basename(path));
    if (name == null || name == p.basename(path) || name.trim().isEmpty) return;
    await perform('正在重命名…', () async {
      if (name.contains(RegExp(r'[/\\]')) || name == '.' || name == '..') {
        throw GitFailure(FailureKind.other, '请输入单个名称。');
      }
      final source = await git!.destination(root!, path),
          target = await git!.destination(root!, p.join(p.dirname(path), name));
      if (await FileSystemEntity.type(target, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw GitFailure(FailureKind.other, '目标名称已存在。');
      }
      await moveEntry(source, target);
      await refresh();
    });
  }

  Future<void> moveEntry(String source, String target) async {
    final type = await FileSystemEntity.type(source, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      await Directory(source).rename(target);
    } else if (type == FileSystemEntityType.link) {
      await Link(source).rename(target);
    } else {
      await File(source).rename(target);
    }
    for (final d in documents) {
      final full = p.join(root!, d.path);
      if (p.equals(source, full) || p.isWithin(source, full)) {
        d.path = repositoryRelative(
          p.equals(source, full)
              ? target
              : p.join(target, repositoryRelative(full, from: source)),
          from: root!,
        );
        d.controller.language = sourceLanguage(d.path);
      }
    }
  }

  Future<void> pasteEntry(String directory) async {
    if (clipboardPath == null) return;
    await perform('正在粘贴…', () async {
      final pending = clipboardPaths.isEmpty
          ? [clipboardPath!]
          : List<String>.from(clipboardPaths);
      for (final source in pending) {
        final parent = await git!.destination(root!, directory);
        final type = await FileSystemEntity.type(source, followLinks: false);
        if (type == FileSystemEntityType.notFound) {
          throw GitFailure(FailureKind.other, '源文件已不存在。');
        }
        if (p.equals(parent, source) || p.isWithin(source, parent)) {
          throw GitFailure(FailureKind.other, '不能把文件夹粘贴到自身内部。');
        }
        var target = p.join(parent, p.basename(source));
        if (clipboardCut && p.equals(source, target)) {
          clipboardPaths.remove(source);
          continue;
        }
        var n = 1;
        while (await FileSystemEntity.type(target, followLinks: false) !=
            FileSystemEntityType.notFound) {
          final ext = type == FileSystemEntityType.directory
              ? ''
              : p.extension(source);
          final stem = type == FileSystemEntityType.directory
              ? p.basename(source)
              : p.basenameWithoutExtension(source);
          target = p.join(parent, '$stem 副本${n == 1 ? '' : ' $n'}$ext');
          n++;
        }
        Future<void> copy(String from, String to) async {
          final t = await FileSystemEntity.type(from, followLinks: false);
          if (t == FileSystemEntityType.directory) {
            await Directory(to).create();
            await for (final item in Directory(from).list(followLinks: false)) {
              if (p.basename(item.path) == '.git') continue;
              await copy(item.path, p.join(to, p.basename(item.path)));
            }
          } else if (t == FileSystemEntityType.link) {
            await Link(to).create(await Link(from).target());
          } else {
            await File(from).copy(to);
          }
        }

        if (clipboardCut) {
          await moveEntry(source, target);
          clipboardPaths.remove(source);
        } else {
          await copy(source, target);
        }
      }
      if (clipboardCut) {
        clipboardPath = clipboardPaths.isEmpty ? null : clipboardPaths.first;
        clipboardCut = clipboardPaths.isNotEmpty;
      }
      await refresh();
    });
  }
}

class ExplorerTree extends StatefulWidget {
  final String root;
  final GitService git;
  final int revision;
  final String filter;
  final String? selected;
  final void Function(String) onOpen;
  final void Function(String) onPin;
  final void Function(String) onSelect;
  final void Function(String?, bool, Offset) onContext;
  final void Function(String, String?) onClipboard;
  final List<Change> changes;
  final String? cut;
  final Set<String> cutPaths;
  final void Function(Set<String>) onMultiSelect;
  const ExplorerTree({
    super.key,
    required this.root,
    required this.git,
    required this.revision,
    required this.filter,
    this.selected,
    required this.onOpen,
    required this.onPin,
    required this.onSelect,
    required this.onContext,
    required this.onClipboard,
    required this.changes,
    this.cut,
    this.cutPaths = const {},
    required this.onMultiSelect,
  });
  @override
  State<ExplorerTree> createState() => _ExplorerTreeState();
}

class _ExplorerTreeState extends State<ExplorerTree> {
  Timer? debounce;
  List<String> searchPaths = [];
  final focus = FocusNode();
  String? selection;
  final selectedPaths = <String>{};
  final expanded = <String>{};
  final children = <String, List<FileSystemEntity>>{};
  final ignored = <String>{};
  String? error;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    load('');
  }

  @override
  void didUpdateWidget(ExplorerTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filter != widget.filter) {
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 160), searchProject);
    }
    if (oldWidget.revision != widget.revision) {
      generation++;

      // Keep current decoration until each refreshed batch arrives; avoid a black flash.
      load('');
      for (final dir in expanded) {
        load(dir);
      }
      if (widget.filter.isNotEmpty) searchProject();
    }
  }

  Future<void> searchProject() async {
    final query = widget.filter.toLowerCase();
    final request = generation;
    if (query.isEmpty) {
      if (mounted) setState(() => searchPaths = []);
      return;
    }
    try {
      final result = await widget.git.run(widget.root, [
        'ls-files',
        '--cached',
        '--others',
        '-z',
      ]);
      final paths =
          {
                ...result.out.split('\x00'),
                ...children.values
                    .expand((items) => items)
                    .whereType<File>()
                    .map((f) => repositoryRelative(f.path, from: widget.root)),
              }
              .where((s) => s.isNotEmpty && s.toLowerCase().contains(query))
              .toList()
            ..sort();
      final ignoredResults = await widget.git.ignoredPaths(widget.root, paths);
      if (mounted &&
          request == generation &&
          widget.filter.toLowerCase() == query) {
        setState(() {
          searchPaths = paths;
          ignored.removeAll(paths);
          ignored.addAll(ignoredResults);
          error = null;
        });
      }
    } catch (_) {
      if (mounted &&
          request == generation &&
          widget.filter.toLowerCase() == query) {
        setState(() => error = '文件搜索失败，请重试。');
      }
    }
  }

  Future<void> load(String relative) async {
    final request = generation;
    try {
      final items = await Directory(p.join(widget.root, relative))
          .list(followLinks: false)
          .where((e) => p.basename(e.path) != '.git')
          .toList();
      items.sort(
        (a, b) => (a is Directory) == (b is Directory)
            ? p
                  .basename(a.path)
                  .toLowerCase()
                  .compareTo(p.basename(b.path).toLowerCase())
            : a is Directory
            ? -1
            : 1,
      );
      final names = items
          .map((e) => repositoryRelative(e.path, from: widget.root))
          .toList();
      final ignoredResults = await widget.git.ignoredPaths(widget.root, names);
      if (!mounted || request != generation) return;
      setState(() {
        children[relative] = items;
        ignored.removeAll(names);
        ignored.addAll(ignoredResults);
        error = null;
      });
    } catch (_) {
      if (mounted && request == generation) {
        setState(() => error = '目录读取失败，请检查权限后刷新。');
      }
    }
  }

  @override
  void dispose() {
    debounce?.cancel();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = <(FileSystemEntity, int)>[];
    void visit(String dir, int depth) {
      for (final item in children[dir] ?? <FileSystemEntity>[]) {
        final relative = repositoryRelative(item.path, from: widget.root);
        if (widget.filter.isNotEmpty &&
            !p
                .basename(item.path)
                .toLowerCase()
                .contains(widget.filter.toLowerCase()) &&
            item is! Directory) {
          continue;
        }
        rows.add((item, depth));
        if (expanded.contains(relative)) visit(relative, depth + 1);
      }
    }

    if (widget.filter.isEmpty) {
      visit('', 0);
    } else {
      rows.addAll(searchPaths.map((s) => (File(p.join(widget.root, s)), 0)));
    }
    if (error != null) return Center(child: T(error!));
    return Focus(
      focusNode: focus,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent ||
            !(Platform.isMacOS
                ? HardwareKeyboard.instance.isMetaPressed
                : HardwareKeyboard.instance.isControlPressed)) {
          return KeyEventResult.ignored;
        }
        for (final item in [
          (LogicalKeyboardKey.keyX, 'x'),
          (LogicalKeyboardKey.keyC, 'c'),
          (LogicalKeyboardKey.keyV, 'v'),
        ]) {
          if (event.logicalKey == item.$1) {
            widget.onClipboard(item.$2, selection);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: (d) =>
            widget.onContext(null, true, d.globalPosition),
        child: ListView.builder(
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final (item, depth) = rows[index];
            final relative = repositoryRelative(item.path, from: widget.root);
            final directory = item is Directory;
            final matches = widget.changes
                .where(
                  (c) =>
                      c.path == relative ||
                      directory && c.path.startsWith('$relative/'),
                )
                .toList();
            const priority = {'!': 0, 'D': 1, 'R': 2, 'M': 3, 'A': 4, 'U': 5};
            matches.sort(
              (a, b) =>
                  priority[a.badgeFor()]!.compareTo(priority[b.badgeFor()]!),
            );
            final isIgnored =
                ignored.contains(relative) &&
                !matches.any((change) => !change.untracked);
            final statusColor = isIgnored
                ? Colors.grey
                : matches.isEmpty
                ? inkColor(context)
                : changeBadgeColor(matches.first.badgeFor());
            return Opacity(
              opacity:
                  widget.cutPaths.contains(p.join(widget.root, relative)) ||
                      widget.cut == p.join(widget.root, relative)
                  ? .45
                  : 1,
              child: GestureDetector(
                onSecondaryTapDown: (d) {
                  if (!selectedPaths.contains(relative)) {
                    selectedPaths
                      ..clear()
                      ..add(relative);
                  }
                  widget.onMultiSelect(Set.from(selectedPaths));
                  selection = relative;
                  focus.requestFocus();
                  widget.onContext(relative, directory, d.globalPosition);
                },
                child: Material(
                  borderRadius: BorderRadius.circular(3),
                  clipBehavior: Clip.antiAlias,
                  color:
                      selectedPaths.contains(relative) ||
                          (selection ?? widget.selected) == relative
                      ? brand.withValues(alpha: .09)
                      : Colors.transparent,
                  child: InkWell(
                    mouseCursor: SystemMouseCursors.click,
                    hoverColor: inkColor(context).withValues(alpha: .035),
                    splashFactory: NoSplash.splashFactory,
                    onDoubleTap: directory
                        ? null
                        : () => widget.onPin(relative),
                    onTap: () {
                      final modifier = Platform.isMacOS
                          ? HardwareKeyboard.instance.isMetaPressed
                          : HardwareKeyboard.instance.isControlPressed;
                      if (HardwareKeyboard.instance.isShiftPressed &&
                          selection != null) {
                        final a = rows.indexWhere(
                              (r) =>
                                  repositoryRelative(
                                    r.$1.path,
                                    from: widget.root,
                                  ) ==
                                  selection,
                            ),
                            b = index;
                        if (a >= 0) {
                          selectedPaths.addAll(
                            rows
                                .sublist(a < b ? a : b, (a > b ? a : b) + 1)
                                .map(
                                  (r) => repositoryRelative(
                                    r.$1.path,
                                    from: widget.root,
                                  ),
                                ),
                          );
                        }
                      } else if (modifier) {
                        if (!selectedPaths.add(relative)) {
                          selectedPaths.remove(relative);
                        }
                      } else {
                        selectedPaths
                          ..clear()
                          ..add(relative);
                      }
                      widget.onMultiSelect(Set.from(selectedPaths));
                      selection = relative;
                      focus.requestFocus();
                      widget.onSelect(relative);
                      if (directory) {
                        setState(() {
                          if (!expanded.add(relative)) {
                            expanded.remove(relative);
                          }
                        });
                        if (expanded.contains(relative)) load(relative);
                      } else {
                        widget.onOpen(relative);
                      }
                    },
                    child: Container(
                      height: 24,
                      foregroundDecoration: _IndentGuides(depth),
                      padding: EdgeInsets.fromLTRB(6 + depth * 14, 0, 6, 0),
                      child: Row(
                        children: [
                          if (directory)
                            Icon(
                              expanded.contains(relative)
                                  ? Icons.keyboard_arrow_down
                                  : Icons.chevron_right,
                              size: 14,
                              color: Colors.grey,
                            )
                          else
                            Opacity(
                              opacity: isIgnored ? .55 : 1,
                              child: ColorFiltered(
                                colorFilter: isIgnored
                                    ? const ColorFilter.mode(
                                        Colors.grey,
                                        BlendMode.srcIn,
                                      )
                                    : const ColorFilter.mode(
                                        Colors.transparent,
                                        BlendMode.dst,
                                      ),
                                child: FileSymbol(relative),
                              ),
                            ),
                          SizedBox(width: 5),
                          Expanded(
                            child: MiddleText(
                              widget.filter.isEmpty
                                  ? p.basename(item.path)
                                  : relative,
                              style: TextStyle(
                                color: statusColor,
                                decoration:
                                    !directory &&
                                        matches.isNotEmpty &&
                                        matches.first.badgeFor() == 'D'
                                    ? TextDecoration.lineThrough
                                    : null,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          if (!isIgnored && matches.isNotEmpty)
                            directory
                                ? SizedBox(
                                    width: 14,
                                    child: Center(
                                      child: Container(
                                        width: 5,
                                        height: 5,
                                        decoration: BoxDecoration(
                                          color: statusColor,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                  )
                                : ChangeBadge(matches.first.badgeFor()),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _IndentGuides extends Decoration {
  final int depth;
  const _IndentGuides(this.depth);
  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _IndentGuidePainter(depth);
}

class _IndentGuidePainter extends BoxPainter {
  final int depth;
  _IndentGuidePainter(this.depth);
  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final height = configuration.size?.height ?? 24;
    final paint = Paint()
      ..color = Colors.grey.withValues(alpha: .16)
      ..strokeWidth = 1;
    for (var i = 0; i < depth; i++) {
      final x = offset.dx + 13 + i * 14;
      canvas.drawLine(
        Offset(x, offset.dy),
        Offset(x, offset.dy + height),
        paint,
      );
    }
  }
}
