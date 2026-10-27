part of '../main.dart';

extension _WorkspaceDialogs on _WorkspacePageState {
  Future<void> branchMenu() async {
    if (root == null || busy) return;
    List<BranchInfo> items = [];
    await perform('正在读取分支…', () async {
      items = await git!.branches(root!);
    });
    if (!mounted) return;
    final box = branchAnchor.currentContext?.findRenderObject() as RenderBox?;
    final anchor = box?.localToGlobal(Offset.zero) ?? const Offset(700, 45);
    final size = MediaQuery.sizeOf(context);
    final left = anchor.dx.clamp(12.0, size.width - 312);
    final top = anchor.dy + (box?.size.height ?? 30) + 8;
    var filter = '';
    var branchLimit = 50;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) => Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: EdgeInsets.only(top: top, left: left),
            child: Material(
              color: panelColor(dialog),
              borderRadius: BorderRadius.circular(12),
              elevation: 10,
              child: SizedBox(
                width: 300,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(dialog).height * .65,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (items.length > 10)
                        Padding(
                          padding: EdgeInsets.all(10),
                          child: TextField(
                            style: TextStyle(fontSize: 12),
                            decoration: InputDecoration(
                              hintText: tr('搜索分支…'),
                              prefixIcon: Icon(Icons.search, size: 14),
                            ),
                            onChanged: (s) => update(() {
                              filter = s;
                              branchLimit = 50;
                            }),
                          ),
                        ),
                      Flexible(
                        child: NotificationListener<ScrollNotification>(
                          onNotification: (n) {
                            if (n.metrics.extentAfter < 50 &&
                                branchLimit < items.length) {
                              update(() => branchLimit += 50);
                            }
                            return false;
                          },
                          child: ListView(
                            shrinkWrap: true,
                            padding: EdgeInsets.all(8),
                            children: [
                              for (final remote in [false, true]) ...[
                                Padding(
                                  padding: EdgeInsets.fromLTRB(8, 10, 8, 6),
                                  child: small(
                                    '${remote ? '远程分支 · 创建本地跟踪分支' : '本地分支'} · ${items.where((b) => b.remote == remote && b.name.toLowerCase().contains(filter.toLowerCase())).length}',
                                  ),
                                ),
                                for (final b
                                    in items
                                        .where(
                                          (b) =>
                                              b.remote == remote &&
                                              b.name.toLowerCase().contains(
                                                filter.toLowerCase(),
                                              ),
                                        )
                                        .take(branchLimit))
                                  HoverRow(
                                    selected: b.current,
                                    onTap: () {
                                      Navigator.pop(dialog);
                                      switchTo(b);
                                    },
                                    onSecondaryTapDown: (d) => contextMenu(
                                      dialog,
                                      d.globalPosition,
                                      [
                                        MenuAction('重命名分支…', () async {
                                          Navigator.pop(dialog);
                                          final name = await prompt(
                                            '重命名分支',
                                            value: b.remote
                                                ? b.name.substring(
                                                    b.name.indexOf('/') + 1,
                                                  )
                                                : b.name,
                                          );
                                          if (name == null || name.isEmpty) {
                                            return;
                                          }
                                          await perform('正在重命名…', () async {
                                            await git!.renameBranch(
                                              root!,
                                              b,
                                              name,
                                            );
                                            await refresh();
                                          });
                                        }, icon: Icons.edit_outlined),
                                        MenuAction(
                                          '删除分支…',
                                          () async {
                                            Navigator.pop(dialog);
                                            if (await confirm(
                                              '删除分支？',
                                              b.remote
                                                  ? '将从远程删除 ${b.name}，其他协作者也会受到影响。'
                                                  : '删除本地分支 ${b.name}，未合并提交会受到保护。',
                                              action: '删除',
                                              danger: true,
                                            )) {
                                              await perform(
                                                '正在删除分支…',
                                                () async {
                                                  await git!.deleteBranch(
                                                    root!,
                                                    b,
                                                  );
                                                  await refresh();
                                                },
                                              );
                                            }
                                          },
                                          enabled:
                                              !b.current && b.name != upstream,
                                          icon: Icons.delete_outline,
                                          destructive: true,
                                        ),
                                        MenuAction(
                                          '合并到当前分支',
                                          () async {
                                            Navigator.pop(dialog);
                                            final expectedHead = await git!
                                                .head(root!);
                                            final targetOID = await git!.oid(
                                              root!,
                                              b.ref,
                                            );
                                            if (await confirm(
                                              '合并分支？',
                                              '将 ${b.name} 合并到当前分支 $branch。',
                                              action: '合并',
                                            )) {
                                              await perform('正在合并…', () async {
                                                await git!.integrate(
                                                  root!,
                                                  targetOID,
                                                  expectedHead: expectedHead,
                                                );
                                                await refresh();
                                              });
                                            }
                                          },
                                          enabled: !b.current,
                                          icon: Icons.merge,
                                        ),
                                        MenuAction(
                                          '与当前分支对比',
                                          () {
                                            Navigator.pop(dialog);
                                            reviewDialog(b.ref, compare: true);
                                          },
                                          enabled: !b.current,
                                          icon: Icons.compare_arrows,
                                        ),
                                      ],
                                    ),
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 9,
                                      ),
                                      child: Row(
                                        children: [
                                          if (remote)
                                            Icon(
                                              Icons.cloud_outlined,
                                              size: 14,
                                              color: Colors.grey,
                                            )
                                          else
                                            BranchSymbol(),
                                          SizedBox(width: 8),
                                          Expanded(
                                            child: T(
                                              b.name,
                                              style: TextStyle(fontSize: 12),
                                            ),
                                          ),
                                          if (b.current)
                                            Icon(
                                              Icons.check,
                                              size: 15,
                                              color: brand,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.all(8),
                        child: ZButton(
                          text: '创建新分支…',
                          icon: Icons.add,
                          height: 28,
                          onTap: () async {
                            Navigator.pop(dialog);
                            final name = await prompt(
                              '创建新分支',
                              hint: '分支名称',
                              action: '创建',
                            );
                            if (name == null || name.isEmpty) return;
                            await perform('正在创建分支…', () async {
                              await git!.createBranch(root!, name);
                              await refresh();
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> switchTo(BranchInfo target) async {
    if (!await allowLeave()) return;
    await perform('正在切换分支…', () async {
      try {
        await git!.switchBranch(root!, target);
      } on GitFailure catch (e) {
        if (e.kind != FailureKind.worktreeConflict ||
            (await git!.changes(root!)).isEmpty) {
          rethrow;
        }
        if (!mounted) return;
        final choice = await showDialog<int>(
          context: context,
          builder: (c) => ZDialog(
            title: '切换分支会覆盖当前修改',
            width: 500,
            actions: [
              ZButton(text: '取消', quiet: false, onTap: () => Navigator.pop(c)),
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                T('目标分支：${target.name}', style: TextStyle(fontSize: 12)),
                SizedBox(height: 12),
                T(
                  '请选择如何处理当前修改，或关闭弹窗留在当前分支。',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                SizedBox(height: 14),
                for (final item in [
                  (1, '临时收起修改并切换', '保存修改备份，切换后可手动恢复。'),
                  (2, '携带修改切换', '将修改应用到目标分支；可能产生冲突，备份会保留。'),
                  (3, '放弃修改并切换', '丢弃当前修改，再切换到目标分支。'),
                ])
                  Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: HoverRow(
                      onTap: () => Navigator.pop(c, item.$1),
                      child: Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: subtleColor(c),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            T(
                              item.$2,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: item.$1 == 3 ? Colors.red : null,
                              ),
                            ),
                            SizedBox(height: 5),
                            T(
                              item.$3,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
        if (choice == null) return;
        if (choice == 3 &&
            !await confirm(
              '确认放弃修改？',
              '已暂存和未暂存修改都会撤销，新增文件移到废纸篓。',
              action: '放弃修改并切换',
              danger: true,
            )) {
          return;
        }
        if (choice == 3) {
          await discardFiles(
            await git!.changes(root!),
            confirmed: true,
            insideOperation: true,
          );
          await git!.switchBranch(root!, target);
        } else {
          final backup = await git!.stash(
            root!,
            message: '切换到 ${target.name} 前的修改',
          );
          await git!.switchBranch(root!, target);
          if (choice == 2) {
            final applied = await git!.run(root!, [
              'stash',
              'apply',
              backup,
            ], check: false);
            if (applied.code != 0 &&
                !(await git!.changes(root!)).any((c) => c.conflict)) {
              throw GitFailure(
                FailureKind.other,
                '已切换分支，携带修改未能完成。备份仍保留，可在临时修改列表恢复。',
              );
            }
          }
        }
        // e is deliberately not shown: Git may include credentials in diagnostics.
        if (e.kind == FailureKind.authentication) rethrow;
      }
      for (final d in documents) {
        d.controller.dispose();
      }
      documents.clear();
      document = null;
      await refresh(initial: true);
    });
  }

  void historyMenu(CommitInfo entry, Offset offset) =>
      contextMenu(context, offset, [
        MenuAction(
          '查看提交详情',
          () => reviewDialog(entry.oid),
          icon: Icons.description_outlined,
        ),
        MenuAction(
          '复制提交编号',
          () => Clipboard.setData(ClipboardData(text: entry.oid)),
          icon: Icons.copy,
        ),
        MenuAction(
          '撤销最新未推送提交',
          () async {
            if (await confirm(
              '撤销本地提交？',
              '文件内容和暂存区保留，分支指针回到上一次提交。已获取的远程提交不允许撤销。',
              action: '撤销',
            )) {
              await perform('正在撤销提交…', () async {
                await git!.undoCommit(root!, entry.oid);
                await refresh();
              });
            }
          },
          enabled:
              historyPage == 0 &&
              commits.isNotEmpty &&
              entry.oid == commits.first.oid &&
              pendingPush.contains(entry.oid),
          icon: Icons.undo,
        ),
        MenuAction(
          '修改提交说明…',
          () async {
            final msg = await prompt('修改最新未推送提交的说明', value: entry.subject);
            if (msg != null && msg.isNotEmpty) {
              await perform('正在修改提交说明…', () async {
                await git!.undoCommit(root!, entry.oid, message: msg);
                await refresh();
              });
            }
          },
          enabled:
              historyPage == 0 &&
              commits.isNotEmpty &&
              entry.oid == commits.first.oid &&
              pendingPush.contains(entry.oid),
          icon: Icons.edit,
        ),
        MenuAction('生成反向提交…', () async {
          final expectedHead = await git!.head(root!);
          if (await confirm(
            '生成反向提交？',
            '保留原历史，新增提交撤回这次更改。工作区需要干净。',
            action: '生成反向提交',
          )) {
            await perform('正在生成反向提交…', () async {
              await git!.integrate(
                root!,
                entry.oid,
                revert: true,
                expectedHead: expectedHead,
              );
              await refresh();
            });
          }
        }, icon: Icons.history),
      ]);
  Future<void> reviewDialog(String ref, {bool compare = false}) async {
    List<ReviewFile> files = [];
    String patch = '', id = '', summary = '';
    ReviewFile? selected;
    await perform('正在读取提交详情…', () async {
      id = await git!.oid(root!, ref);
      files = await git!.reviewFiles(root!, id, compare: compare);
      summary = (await git!.run(
        root!,
        compare
            ? ['log', '--left-right', '--oneline', 'HEAD...$id']
            : ['show', '-s', '--format=%h · %s%n%an <%ae>%n%aI', id],
      )).out;
      if (files.isNotEmpty) {
        selected = files.first;
        patch = await git!.reviewPatch(
          root!,
          id,
          selected!.path,
          compare: compare,
        );
      }
    });
    if (!mounted || id.isEmpty) return;
    bool loading = false;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => ZDialog(
          title: compare ? '分支对比 · $ref' : '提交详情',
          width: 1250,
          height: MediaQuery.sizeOf(c).height * .85,
          scroll: false,
          actions: [
            if (!compare && selected != null)
              ZButton(
                text: '恢复此文件到该版本…',
                quiet: false,
                onTap: () async {
                  final path = selected!.path;
                  Navigator.pop(c);
                  if (await confirm(
                    '恢复文件版本？',
                    '只修改工作区中的 $path，提交历史保持不变。当前文件会被此版本替换。',
                    action: '恢复',
                  )) {
                    await restoreVersion(id, path);
                  }
                },
              ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(8, 4, 8, 10),
                child: T(
                  summary.trim(),
                  maxLines: compare ? 5 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, height: 1.6),
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    SizedBox(
                      width: 200,
                      child: files.isEmpty
                          ? Center(child: T('没有文件差异'))
                          : ListView(
                              children: [
                                for (final f in files)
                                  HoverRow(
                                    selected: f == selected,
                                    onTap: loading
                                        ? null
                                        : () async {
                                            update(() => loading = true);
                                            final next = await git!.reviewPatch(
                                              root!,
                                              id,
                                              f.path,
                                              compare: compare,
                                            );
                                            if (c.mounted) {
                                              update(() {
                                                selected = f;
                                                patch = next;
                                                loading = false;
                                              });
                                            }
                                          },
                                    child: Padding(
                                      padding: EdgeInsets.all(10),
                                      child: Row(
                                        children: [
                                          T(
                                            f.status,
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: brand,
                                            ),
                                          ),
                                          SizedBox(width: 8),
                                          Expanded(
                                            child: Tooltip(
                                              message: f.path,
                                              child: Row(
                                                children: [
                                                  FileSymbol(f.path),
                                                  const SizedBox(width: 5),
                                                  Expanded(
                                                    child: MiddleText(
                                                      f.path,
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: loading
                          ? Center(child: CircularProgressIndicator())
                          : selected != null && isPreviewImage(selected!.path)
                          ? GitImageComparison(
                              git: git!,
                              root: root!,
                              path: selected!.path,
                              before: compare ? 'HEAD' : '$id^1',
                              after: id,
                            )
                          : DiffView(patch, path: selected?.path ?? ''),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> fileHistory(String path) async {
    List<CommitInfo> entries = [];
    await perform('正在读取文件历史…', () async {
      entries = await git!.history(root!, path: path);
    });
    if (!mounted) return;
    bool more = entries.length == 80, loading = false;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => ZDialog(
          title: '文件历史 · ${p.basename(path)}',
          width: 600,
          height: 540,
          scroll: false,
          child: entries.isEmpty
              ? Center(child: T('此文件暂无历史'))
              : ListView(
                  children: [
                    for (final e in entries)
                      HoverRow(
                        onTap: () {
                          Navigator.pop(c);
                          reviewDialog(e.oid);
                        },
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    T(e.subject),
                                    SizedBox(height: 6),
                                    small(
                                      '${e.author} · ${e.date.substring(0, 10)} · ${e.oid.substring(0, 7)}',
                                    ),
                                  ],
                                ),
                              ),
                              ZButton(
                                text: '恢复此版本',
                                height: 24,
                                onTap: () async {
                                  Navigator.pop(c);
                                  if (await confirm(
                                    '恢复历史版本？',
                                    '将替换工作区中的 $path，历史保持不变。',
                                    action: '恢复',
                                  )) {
                                    await restoreVersion(
                                      e.oid,
                                      path,
                                      followRenames: true,
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (more)
                      ZButton(
                        text: loading ? '正在加载…' : '加载更多',
                        onTap: loading
                            ? null
                            : () async {
                                update(() => loading = true);
                                final next = await git!.history(
                                  root!,
                                  path: path,
                                  skip: entries.length,
                                );
                                if (c.mounted) {
                                  update(() {
                                    entries.addAll(next);
                                    more = next.length == 80;
                                    loading = false;
                                  });
                                }
                              },
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> restoreVersion(
    String id,
    String path, {
    bool followRenames = false,
  }) async {
    if (!await allowLeave()) return;
    await perform('正在恢复文件…', () async {
      final source = followRenames
          ? await git!.historicalPath(root!, id, path)
          : path;
      final plan = await git!.prepareFileVersion(
        root!,
        id,
        path,
        source: source,
      );
      try {
        await git!.applyRestore(root!, plan, {});
      } finally {
        await plan.dispose();
      }
      for (final d in documents.where((d) => d.path == path).toList()) {
        documents.remove(d);
        if (document == d) document = null;
        d.controller.dispose();
      }
      await refresh();
    });
  }

  Future<void> stashChanges() async {
    if (!await allowLeave()) return;
    final msg = await prompt('临时收起修改', hint: '说明（可选）', action: '收起');
    if (msg == null) return;
    await perform('正在临时收起修改…', () async {
      await git!.stash(root!, message: msg.isEmpty ? '枝序 · 临时收起修改' : msg);
      for (final d in documents) {
        d.controller.dispose();
      }
      documents.clear();
      document = null;
      await refresh();
    });
  }

  Future<void> backupsDialog() async {
    List<BackupInfo> records = [];
    List<(String, bool)> files = [];
    BackupInfo? selected;
    (String, bool)? chosen;
    String patch = '';
    await perform('正在读取临时修改…', () async {
      records = await git!.backups(root!);
    });
    if (!mounted) return;
    Future<void> select(BackupInfo b) async {
      selected = b;
      files = await git!.backupFiles(root!, b.oid);
      chosen = files.isEmpty ? null : files.first;
      patch = chosen == null ? '' : await backupPatch(b.oid, chosen!);
    }

    if (records.isNotEmpty) await select(records.first);
    if (!mounted) return;
    bool loading = false;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) {
          Future<void> act(Future<void> Function() action) async {
            if (loading) return;
            update(() => loading = true);
            try {
              await action();
            } catch (e) {
              if (mounted) {
                await notice(
                  '操作未完成',
                  e is GitFailure ? e.message : '备份读取失败，请刷新。',
                );
              }
            } finally {
              if (c.mounted) update(() => loading = false);
            }
          }

          return ZDialog(
            title: '临时收起的修改',
            headerActions: [
              ZButton(
                icon: Icons.refresh,
                tooltip: '刷新记录',
                onTap: loading
                    ? null
                    : () => act(() async {
                        final previous = selected?.oid;
                        records = await git!.backups(root!);
                        if (records.isEmpty) {
                          selected = null;
                          files = [];
                          patch = '';
                        } else {
                          await select(
                            records
                                    .where((b) => b.oid == previous)
                                    .firstOrNull ??
                                records.first,
                          );
                        }
                      }),
              ),
            ],
            width: 1280,
            height: MediaQuery.sizeOf(c).height * .85,
            scroll: false,
            actions: [
              if (selected != null)
                ZButton(
                  text: '删除备份…',
                  danger: true,
                  quiet: false,
                  onTap: loading
                      ? null
                      : () => act(() async {
                          if (await confirm(
                            '删除整条备份？',
                            '删除后不能从此列表恢复。',
                            action: '删除',
                            danger: true,
                          )) {
                            await git!.dropBackup(root!, selected!.oid);
                            records = await git!.backups(root!);
                            if (records.isNotEmpty) {
                              await select(records.first);
                            } else {
                              selected = null;
                              files = [];
                              patch = '';
                            }
                          }
                        }),
                ),
              if (selected != null)
                ZButton(
                  text: '恢复此条修改',
                  primary: true,
                  onTap: loading
                      ? null
                      : () {
                          final id = selected!.oid;
                          Navigator.pop(c);
                          restoreBackup(id);
                        },
                ),
            ],
            child: records.isEmpty
                ? Center(
                    child: T('没有临时收起的修改', style: TextStyle(color: Colors.grey)),
                  )
                : Row(
                    children: [
                      SizedBox(
                        width: 215,
                        child: ListView(
                          children: [
                            for (final b in records)
                              HoverRow(
                                selected: selected?.oid == b.oid,
                                onTap: () => act(() => select(b)),
                                onSecondaryTapDown: (d) =>
                                    contextMenu(c, d.globalPosition, [
                                      MenuAction(
                                        '删除整条备份…',
                                        () => act(() async {
                                          if (await confirm(
                                            '删除整条备份？',
                                            '将永久移除这条临时备份，工作区文件不变。',
                                            action: '删除',
                                            danger: true,
                                          )) {
                                            await git!.dropBackup(root!, b.oid);
                                            records = await git!.backups(root!);
                                            if (records.isNotEmpty) {
                                              await select(records.first);
                                            } else {
                                              selected = null;
                                              files = [];
                                              chosen = null;
                                              patch = '';
                                            }
                                          }
                                        }),
                                        icon: Icons.delete_outline,
                                        destructive: true,
                                      ),
                                    ]),
                                child: Padding(
                                  padding: EdgeInsets.all(10),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      T(
                                        b.branch,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      SizedBox(height: 6),
                                      small(
                                        b.date
                                            .replaceFirst('T', ' ')
                                            .substring(0, 16),
                                      ),
                                      SizedBox(height: 4),
                                      T(
                                        b.subject,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      SizedBox(width: 10),
                      SizedBox(
                        width: 205,
                        child: ListView(
                          children: [
                            for (final f in files)
                              HoverRow(
                                selected: chosen == f,
                                onTap: () => act(() async {
                                  chosen = f;
                                  patch = await backupPatch(selected!.oid, f);
                                }),
                                onSecondaryTapDown: (d) =>
                                    contextMenu(c, d.globalPosition, [
                                      MenuAction(
                                        '从备份删除此文件…',
                                        () => act(() async {
                                          if (await confirm(
                                            '删除备份中的文件？',
                                            '仅从这条备份中移除 ${f.$1}，工作区文件不变。',
                                            action: '删除',
                                            danger: true,
                                          )) {
                                            await git!.deleteBackupFile(
                                              root!,
                                              selected!.oid,
                                              f.$1,
                                              f.$2,
                                            );
                                            records = await git!.backups(root!);
                                            await select(records.first);
                                          }
                                        }),
                                        icon: Icons.delete_outline,
                                        destructive: true,
                                      ),
                                    ]),
                                child: Padding(
                                  padding: EdgeInsets.all(9),
                                  child: Row(
                                    children: [
                                      FileSymbol(f.$1),
                                      SizedBox(width: 7),
                                      Expanded(
                                        child: T(
                                          f.$1,
                                          style: TextStyle(fontSize: 11),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: loading
                            ? Center(child: CircularProgressIndicator())
                            : chosen != null &&
                                  selected != null &&
                                  isPreviewImage(chosen!.$1)
                            ? GitImageComparison(
                                git: git!,
                                root: root!,
                                path: chosen!.$1,
                                before: '${selected!.oid}^1',
                                after: chosen!.$2
                                    ? '${selected!.oid}^3'
                                    : selected!.oid,
                              )
                            : DiffView(patch),
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }

  Future<String> backupPatch(String id, (String, bool) file) async =>
      isPreviewImage(file.$1)
      ? ''
      : file.$2
      ? '新增文件：${file.$1}\n${(await git!.run(root!, ['show', '$id^3:${file.$1}'])).out.split('\n').map((s) => '+$s').join('\n')}'
      : (await git!.run(root!, [
          'diff',
          '--no-ext-diff',
          '--no-textconv',
          '--unified=10000',
          '$id^1',
          id,
          '--',
          file.$1,
        ])).out;
  Future<void> restoreBackup(String id) async {
    if (!await allowLeave()) return;
    await perform('正在比较备份…', () async {
      final plan = await git!.prepareRestore(root!, id);
      final keep = <String>{};
      try {
        for (final item in plan.items) {
          final snapshot = await git!.snapshot(item.source);
          if (item.snapshot == 'missing' || snapshot == item.snapshot) continue;
          final currentPath = await git!.destination(root!, item.path);
          final current = await previewText(currentPath),
              backup = await previewText(item.source);
          final image =
              isPreviewImage(item.path) && item.snapshot != 'directory';
          final imageRef =
              image && await git!.imageAt(root!, item.path, id) == null
              ? '$id^3'
              : id;
          if (!mounted) return;
          final choice = await showDialog<bool>(
            context: context,
            builder: (c) => ZDialog(
              title: '对比并恢复文件 · ${item.path}',
              width: 1200,
              height: MediaQuery.sizeOf(c).height * .8,
              scroll: false,
              actions: [
                ZButton(
                  text: '取消恢复',
                  quiet: false,
                  onTap: () => Navigator.pop(c),
                ),
                Spacer(),
                ZButton(
                  text: '保留当前文件',
                  quiet: false,
                  onTap: () => Navigator.pop(c, false),
                ),
                Spacer(),
                ZButton(
                  text: '恢复备份',
                  primary: true,
                  onTap: item.snapshot == 'directory'
                      ? null
                      : () => Navigator.pop(c, true),
                ),
              ],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: small('左右对照 · 同步滚动 · 原备份会保留'),
                  ),
                  Expanded(
                    child: image
                        ? GitImageComparison(
                            git: git!,
                            root: root!,
                            path: item.path,
                            before: null,
                            after: imageRef,
                          )
                        : SplitTextView(left: current, right: backup),
                  ),
                ],
              ),
            ),
          );
          if (choice == null) {
            status = '已取消恢复';
            return;
          }
          if (!choice) keep.add(item.path);
        }
        await git!.applyRestore(root!, plan, keep);
        for (final d in documents) {
          d.controller.dispose();
        }
        documents.clear();
        document = null;
        await refresh();
        status = '修改已恢复 · 相同文件跳过 · 原备份保留';
      } finally {
        await plan.dispose();
      }
    });
  }

  Future<String> previewText(String path) async {
    try {
      final type = await FileSystemEntity.type(path, followLinks: false);
      if (type == FileSystemEntityType.notFound) return '（文件不存在 / 已删除）';
      if (type == FileSystemEntityType.directory) return '（文件夹，不能覆盖）';
      if (type == FileSystemEntityType.link) {
        return '符号链接 → ${await Link(path).target()}';
      }
      final f = File(path);
      if (await f.length() > 2 * 1024 * 1024) return '（文件超过 2 MB，无法显示文本）';
      final bytes = await f.readAsBytes();
      if (bytes.contains(0)) return '（二进制文件，${bytes.length} 字节）';
      return utf8.decode(bytes);
    } catch (_) {
      return '（无法读取为 UTF-8 文本）';
    }
  }

  Future<void> conflictDialog(Change change) async {
    final path = change.path;
    String left = '', right = '', initial = '', expected = '';
    var loaded = false, wholeFile = false;
    await perform('正在读取冲突…', () async {
      expected = await git!.snapshot(await git!.destination(root!, path));
      final ours = await git!.run(root!, ['show', ':2:$path'], check: false);
      final theirs = await git!.run(root!, ['show', ':3:$path'], check: false);
      left = ours.out;
      right = theirs.out;
      wholeFile =
          ours.code != 0 ||
          theirs.code != 0 ||
          left.contains('\x00') ||
          right.contains('\x00') ||
          left.contains('\uFFFD') ||
          right.contains('\uFFFD') ||
          expected.startsWith('link:');
      try {
        initial = await git!.readFile(root!, path);
      } on GitFailure {
        wholeFile = true;
      }
      loaded = true;
    });
    if (!mounted || !loaded) return;
    if (wholeFile) {
      final choice = await showDialog<int>(
        context: context,
        builder: (c) => ZDialog(
          title: '选择冲突文件版本',
          width: 520,
          actions: [
            ZButton(text: '取消', onTap: () => Navigator.pop(c)),
            ZButton(text: '采用当前并标记解决', onTap: () => Navigator.pop(c, 2)),
            ZButton(
              text: '采用传入并标记解决',
              primary: true,
              onTap: () => Navigator.pop(c, 3),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(path),
              const SizedBox(height: 12),
              T('此冲突包含二进制、删除、符号链接或无法编辑的内容。请选择保留的完整版本；所选版本不存在时将删除此文件。'),
            ],
          ),
        ),
      );
      if (choice != null) {
        await perform('正在解决冲突…', () async {
          await git!.resolveWholeConflict(root!, path, choice, expected);
          await refresh();
        });
      }
      return;
    }
    final result = CodeController(text: initial);
    bool saving = false;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => ZDialog(
          title: '解决冲突 · $path',
          width: 1320,
          height: MediaQuery.sizeOf(c).height * .88,
          scroll: false,
          actions: [
            ZButton(
              text: '保存并标记已解决',
              primary: true,
              onTap: saving
                  ? null
                  : () async {
                      if (RegExp(
                        r'^(<<<<<<<|=======|>>>>>>>)',
                        multiLine: true,
                      ).hasMatch(result.text)) {
                        await notice('仍有冲突标记', '请处理所有冲突块后再标记已解决。');
                        return;
                      }
                      update(() => saving = true);
                      try {
                        await git!.saveFile(root!, path, initial, result.text);
                        await git!.run(root!, ['add', '--', path]);
                        if (c.mounted) Navigator.pop(c);
                      } catch (e) {
                        await notice(
                          '未能保存',
                          e is GitFailure ? e.message : '文件保存失败。',
                        );
                        if (c.mounted) update(() => saving = false);
                      }
                    },
            ),
          ],
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          T(
                            '当前版本',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Expanded(
                            child: SingleChildScrollView(
                              padding: EdgeInsets.all(10),
                              child: SelectableText(
                                left,
                                style: TextStyle(
                                  fontFamily: codeFontFamily,
                                  fontFamilyFallback: codeFontFallback,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          T(
                            '传入版本',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Expanded(
                            child: SingleChildScrollView(
                              padding: EdgeInsets.all(10),
                              child: SelectableText(
                                right,
                                style: TextStyle(
                                  fontFamily: codeFontFamily,
                                  fontFamilyFallback: codeFontFallback,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          T(
                            '合并结果（可编辑）',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Expanded(child: CodeEditor(controller: result)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 42,
                child: Row(
                  children: [
                    T('下一冲突块：', style: TextStyle(fontSize: 11)),
                    for (final item in [
                      ('ours', '使用当前'),
                      ('theirs', '使用传入'),
                      ('both', '保留双方'),
                    ])
                      ZButton(
                        text: item.$2,
                        onTap: () =>
                            update(() => chooseConflict(result, item.$1)),
                      ),
                    Spacer(),
                    ZButton(
                      text: '全部使用当前',
                      onTap: () => update(() => result.text = left),
                    ),
                    ZButton(
                      text: '全部使用传入',
                      onTap: () => update(() => result.text = right),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await Future<void>.delayed(Duration(milliseconds: 250));
    result.dispose();
    await perform('正在刷新…', refresh);
  }

  void chooseConflict(CodeController result, String choice) {
    final pattern = RegExp(
      r'^<<<<<<<[^\n]*\n([\s\S]*?)^=======[^\n]*\n([\s\S]*?)^>>>>>>>[^\n]*(?:\n|$)',
      multiLine: true,
    );
    final match = pattern.firstMatch(result.text);
    if (match == null) return;
    final ours = match[1]!
        .split(RegExp(r'^\|\|\|\|\|\|\|[^\n]*\n', multiLine: true))
        .first;
    final theirs = match[2]!;
    result.text = result.text.replaceRange(
      match.start,
      match.end,
      choice == 'ours'
          ? ours
          : choice == 'theirs'
          ? theirs
          : ours + theirs,
    );
  }

  Future<void> settings() async {
    if (busy) return;
    final name = TextEditingController(text: author),
        mail = TextEditingController(text: email);
    final urls = <String, TextEditingController>{};
    String version = '', execPath = '', globalName = '', globalEmail = '';
    if (git != null) {
      await perform('正在读取设置…', () async {
        for (final r in remotes) {
          urls[r] = TextEditingController(
            text: (await git!.run(root!, ['remote', 'get-url', r])).out.trim(),
          );
        }
        final directory = root ?? Directory.current.path;
        version = (await git!.run(directory, ['--version'])).out.trim();
        execPath = (await git!.run(directory, ['--exec-path'])).out.trim();
        globalName = (await git!.run(directory, [
          'config',
          '--global',
          '--get',
          'user.name',
        ], check: false)).out.trim();
        globalEmail = (await git!.run(directory, [
          'config',
          '--global',
          '--get',
          'user.email',
        ], check: false)).out.trim();
      });
    }
    if (!mounted) return;
    bool saving = false;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) {
          Future<void> action(Future<void> Function() fn) async {
            if (saving) return;
            update(() => saving = true);
            try {
              await fn();
            } catch (e) {
              await notice(
                '设置未完成',
                e is GitFailure ? e.message : '请检查设置内容和仓库权限。',
              );
            } finally {
              if (c.mounted) update(() => saving = false);
            }
          }

          InputDecoration settingsInput(String hint, {Color? fillColor}) =>
              InputDecoration(hintText: tr(hint), fillColor: fillColor);
          Widget label(String title) => Padding(
            padding: EdgeInsets.only(top: 18, bottom: 10),
            child: T(
              title,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          );
          return ZDialog(
            title: '设置',
            width: 548,
            height: MediaQuery.sizeOf(c).height * .86,
            actions: [
              if (root != null)
                ZButton(
                  text: saving ? '正在保存…' : '保存项目设置',
                  primary: true,
                  onTap: saving
                      ? null
                      : () => action(() async {
                          final draftURLs = {
                            for (final entry in urls.entries)
                              entry.key: entry.value.text.trim(),
                          };
                          for (final entry in draftURLs.entries) {
                            validateRemote(entry.key, entry.value);
                          }
                          if (name.text.trim().isEmpty ||
                              mail.text.trim().isEmpty) {
                            throw GitFailure(FailureKind.other, '请填写有效的姓名和邮箱。');
                          }
                          await git!.saveAuthor(root!, name.text, mail.text);
                          for (final entry in draftURLs.entries) {
                            await git!.run(root!, [
                              'remote',
                              'set-url',
                              entry.key,
                              entry.value,
                            ]);
                          }
                          await refresh();
                          if (c.mounted) Navigator.pop(c);
                        }),
                ),
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                label('语言'),
                Row(
                  children: [
                    for (final value in ['中文', 'English'])
                      Expanded(
                        child: ZButton(
                          text: value,
                          primary: language == value,
                          quiet: false,
                          onTap: () {
                            language = value;
                            uiLanguage = value;
                            remember();
                            update(() {});
                            redraw();
                          },
                        ),
                      ),
                  ],
                ),
                SizedBox(height: 8),
                label('色彩模式'),
                Row(
                  children: [
                    for (final item in [
                      (ThemeMode.system, '跟随系统', Icons.desktop_windows),
                      (ThemeMode.light, '日间', Icons.light_mode_outlined),
                      (ThemeMode.dark, '夜间', Icons.dark_mode_outlined),
                    ])
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: ZButton(
                            text: item.$2,
                            icon: item.$3,
                            selected: appearance.value == item.$1,
                            primary: appearance.value == item.$1,
                            quiet: false,
                            onTap: () {
                              appearance.value = item.$1;
                              remember();
                              update(() {});
                            },
                          ),
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: Row(
                    children: [
                      CompactCheckbox(
                        value: completionEnabled,
                        onChanged: (value) {
                          completionEnabled = value == true;
                          remember();
                          update(() {});
                          redraw();
                        },
                      ),
                      T(
                        '编辑器自动补全',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                T(
                  '括号配对、自动缩进、语言关键字和代码片段。Tab 接受，Esc 关闭；全部在本机完成。',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                label('本机 Git'),
                Container(
                  padding: EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: subtleColor(c),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      T(
                        version.isEmpty ? '使用电脑已有 Git' : version,
                        style: TextStyle(fontSize: 12),
                      ),
                      SizedBox(height: 8),
                      small('${tr('执行文件')}：${git?.executable ?? ''}'),
                      const SizedBox(height: 6),
                      small('${tr('工具目录')}：$execPath'),
                      const SizedBox(height: 6),
                      small('${tr('全局姓名')}：$globalName'),
                      const SizedBox(height: 6),
                      small('${tr('全局邮箱')}：$globalEmail'),
                      SizedBox(height: 8),
                      T(
                        '默认使用电脑已有认证。需要登录时提示，成功后交给系统 Git 凭据助手保存。',
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.6,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                if (root != null) ...[
                  label('本项目提交署名'),
                  small('默认读取电脑 Git 配置，仅影响之后的新提交。'),
                  SizedBox(height: 8),
                  small(tr('提交者姓名')),
                  SizedBox(height: 6),
                  TextField(
                    controller: name,
                    style: TextStyle(fontSize: 12),
                    decoration: settingsInput('提交者姓名'),
                  ),
                  SizedBox(height: 10),
                  small(tr('提交者邮箱')),
                  SizedBox(height: 6),
                  TextField(
                    controller: mail,
                    style: TextStyle(fontSize: 12),
                    decoration: settingsInput('提交者邮箱'),
                  ),
                  label('远程仓库'),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ZButton(
                      text: '新增远程仓库',
                      icon: Icons.add,
                      quiet: false,
                      onTap: saving
                          ? null
                          : () => action(() async {
                              final r = await prompt(
                                '新增远程仓库',
                                hint: '名称，例如 GitHub / Gitee',
                              );
                              if (r == null || r.trim().isEmpty) return;
                              if (urls.containsKey(r)) {
                                throw GitFailure(
                                  FailureKind.other,
                                  '同名远程仓库已存在。',
                                );
                              }
                              final url = await prompt(
                                '仓库地址',
                                hint: 'HTTPS 或 SSH 地址',
                              );
                              if (url == null ||
                                  url.trim().isEmpty ||
                                  !mounted) {
                                return;
                              }
                              validateRemote(r, url);
                              await git!.run(root!, ['remote', 'add', r, url]);
                              urls[r] = TextEditingController(text: url);
                              await refresh();
                            }),
                    ),
                  ),
                  SizedBox(height: 10),
                  for (final r in urls.keys.toList())
                    Container(
                      margin: EdgeInsets.only(bottom: 10),
                      padding: EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: subtleColor(c),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: inkColor(c).withValues(alpha: .07),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.cloud_outlined, size: 14),
                              SizedBox(width: 8),
                              Expanded(
                                child: T(
                                  r,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              ZButton(
                                text: '重命名',
                                height: 24,
                                onTap: saving
                                    ? null
                                    : () => action(() async {
                                        final to = await prompt(
                                          '重命名远程仓库',
                                          value: r,
                                        );
                                        if (to == null || to == r) return;
                                        validateRemote(to, urls[r]!.text);
                                        await git!.run(root!, [
                                          'remote',
                                          'rename',
                                          r,
                                          to,
                                        ]);
                                        urls[to] = urls.remove(r)!;
                                        await refresh();
                                      }),
                              ),
                              ZButton(
                                text: '移除',
                                height: 24,
                                danger: true,
                                onTap: saving
                                    ? null
                                    : () => action(() async {
                                        if (await confirm(
                                          '移除远程仓库？',
                                          '仅移除本项目的 $r 配置，远程服务器上的仓库和文件不会删除。',
                                          action: '移除',
                                          danger: true,
                                        )) {
                                          await git!.run(root!, [
                                            'remote',
                                            'remove',
                                            r,
                                          ]);
                                          urls.remove(r)?.dispose();
                                          await refresh();
                                        }
                                      }),
                              ),
                            ],
                          ),
                          SizedBox(height: 10),
                          TextField(
                            controller: urls[r],
                            style: TextStyle(fontSize: 12),
                            decoration: settingsInput(
                              '仓库地址',
                              fillColor: panelColor(c),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                label('关于'),
                Container(
                  padding: EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: subtleColor(c),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      T(
                        '枝序 · 让 Git 简单一点',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 8),
                      small('版本 $appVersion'),
                      SizedBox(height: 10),
                      T('作者 zoulirise', style: TextStyle(fontSize: 12)),
                      ZButton(
                        text: 'zoulirise@gmail.com',
                        onTap: () => openUrl('mailto:zoulirise@gmail.com'),
                      ),
                      ZButton(
                        text: 'GitHub · 开源项目',
                        onTap: () =>
                            openUrl('https://github.com/zoulirise-dev/zhixu'),
                      ),
                      ZButton(
                        text: 'Gitee · 开源项目',
                        onTap: () =>
                            openUrl('https://gitee.com/zoulirise/zhixu'),
                      ),
                      small('MIT License'),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    await Future<void>.delayed(Duration(milliseconds: 250));
    name.dispose();
    mail.dispose();
    for (final v in urls.values) {
      v.dispose();
    }
  }

  void validateRemote(String name, String url) {
    if (!RegExp(r'^[A-Za-z0-9_\u4e00-\u9fff][A-Za-z0-9_.\-\u4e00-\u9fff]*$')
            .hasMatch(name) ||
        url.trim().isEmpty ||
        url.startsWith('-') ||
        url.contains(RegExp(r'[\r\n\x00]')) ||
        (Uri.tryParse(url)?.userInfo.contains(':') ?? false)) {
      throw GitFailure(FailureKind.other, '请输入有效名称和不含密码的仓库地址。');
    }
  }

  Future<HttpsCredential?> login(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') {
      await notice('需要 Git 认证', 'SSH 仓库使用电脑已有密钥或 SSH Agent，请先完成配置后重试。');
      return null;
    }
    final user = TextEditingController(), password = TextEditingController();
    bool advanced = uri.host != 'github.com';
    final values = await showDialog<List<String>>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => ZDialog(
          title: '登录 ${uri.host}',
          width: 440,
          actions: [
            ZButton(text: '取消', quiet: false, onTap: () => Navigator.pop(c)),
            if (advanced)
              ZButton(
                text: '登录并重试',
                primary: true,
                onTap: () => Navigator.pop(c, [user.text, password.text]),
              ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              T(
                '使用电脑已有 Git 认证。登录成功后继续操作，凭据由系统 Git 凭据助手保存。',
                style: TextStyle(fontSize: 12, height: 1.7, color: Colors.grey),
              ),
              SizedBox(height: 16),
              if (uri.host == 'github.com') ...[
                ZButton(
                  text: '在浏览器登录 GitHub',
                  primary: true,
                  onTap: () async {
                    final token = await githubLogin();
                    if (token != null && c.mounted) Navigator.pop(c, token);
                  },
                ),
                SizedBox(height: 8),
                ZButton(
                  text: advanced ? '收起高级登录' : '高级：使用访问令牌',
                  onTap: () => update(() => advanced = !advanced),
                ),
              ],
              if (advanced) ...[
                SizedBox(height: 10),
                TextField(
                  controller: user,
                  style: TextStyle(fontSize: 12),
                  decoration: InputDecoration(labelText: '账号'),
                ),
                SizedBox(height: 12),
                TextField(
                  controller: password,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  style: TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    labelText: uri.host == 'github.com' ? '访问令牌' : '密码 / 访问令牌',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    password.clear();
    await Future<void>.delayed(Duration(milliseconds: 250));
    user.dispose();
    password.dispose();
    return values == null ? null : HttpsCredential(uri, values[0], values[1]);
  }

  Future<List<String>?> githubLogin() async {
    String? executable;
    for (final candidate in [
      if (Platform.isMacOS)
        p.normalize(
          p.join(p.dirname(Platform.resolvedExecutable), '..', 'Helpers', 'gh'),
        ),
      'gh',
      if (Platform.isMacOS) '/opt/homebrew/bin/gh',
      if (Platform.isMacOS) '/usr/local/bin/gh',
      p.join(
        p.dirname(Platform.resolvedExecutable),
        'gh${Platform.isWindows ? '.exe' : ''}',
      ),
    ]) {
      try {
        if ((await Process.run(candidate, ['--version'])).exitCode == 0) {
          executable = candidate;
          break;
        }
      } catch (_) {}
    }
    if (executable == null) {
      await notice(
        '缺少 GitHub 登录组件',
        '请安装 GitHub CLI（gh），或使用电脑上已有客户端完成认证后重试。也可使用高级访问令牌登录。',
      );
      return null;
    }
    final temp = await Directory.systemTemp.createTemp('zhixu-github-login-');
    if (!Platform.isWindows) await Process.run('chmod', ['700', temp.path]);
    final env = Map<String, String>.from(Platform.environment)
      ..removeWhere(
        (k, v) =>
            k.startsWith('GH_') ||
            k.startsWith('GITHUB_') ||
            k.startsWith('GIT_'),
      );
    env.addAll({
      'GH_CONFIG_DIR': temp.path,
      'GH_NO_UPDATE_NOTIFIER': '1',
      'GH_PROMPT_DISABLED': '1',
      'GIT_CONFIG_GLOBAL': p.join(temp.path, 'gitconfig'),
      'GIT_CONFIG_NOSYSTEM': '1',
      'NO_COLOR': '1',
      'LC_ALL': 'C',
      'GH_BROWSER': Platform.isMacOS ? '/usr/bin/open' : 'explorer.exe',
    });
    Process? process;
    String code = '', info = '正在等待 GitHub 授权…';
    bool cancelled = false;
    List<String>? credentials;
    try {
      if (!mounted) return null;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (c) => StatefulBuilder(
          builder: (c, update) {
            if (process == null && !cancelled) {
              cancelled = true;
              () async {
                try {
                  process = await Process.start(
                    executable!,
                    [
                      'auth',
                      'login',
                      '--hostname',
                      'github.com',
                      '--web',
                      '--git-protocol',
                      'https',
                      '--skip-ssh-key',
                      '--insecure-storage',
                    ],
                    environment: env,
                    includeParentEnvironment: false,
                  );
                  cancelled = false;
                  await process!.stdin.close();
                  final out = process!.stdout.drain<void>();
                  String buffer = '';
                  final err = process!.stderr.transform(utf8.decoder).listen((
                    s,
                  ) {
                    buffer += s;
                    final found = RegExp(r'([A-Z0-9]{4}-[A-Z0-9]{4})')
                        .firstMatch(buffer);
                    if (found != null && c.mounted) {
                      update(() => code = found[1]!);
                    }
                  });
                  final exit = await process!.exitCode.timeout(
                    Duration(minutes: 15),
                  );
                  await out;
                  await err.cancel();
                  if (exit != 0 || cancelled) return;
                  final token = await Process.run(
                    executable!,
                    ['auth', 'token', '--hostname', 'github.com'],
                    environment: env,
                    includeParentEnvironment: false,
                  );
                  final account = await Process.run(
                    executable!,
                    ['api', 'user', '--jq', '.login'],
                    environment: env,
                    includeParentEnvironment: false,
                  );
                  if (token.exitCode == 0 &&
                      account.exitCode == 0 &&
                      !cancelled) {
                    credentials = [
                      '${account.stdout}'.trim(),
                      '${token.stdout}'.trim(),
                    ];
                    if (c.mounted) Navigator.pop(c);
                  } else if (c.mounted) {
                    update(() => info = '登录未完成，请检查网络后重试。');
                  }
                } catch (_) {
                  if (c.mounted) update(() => info = '登录未完成，请检查网络后重试。');
                }
              }();
            }
            return ZDialog(
              title: 'GitHub 网页登录',
              width: 420,
              actions: [
                ZButton(
                  text: '取消',
                  onTap: () {
                    cancelled = true;
                    process?.kill();
                    Navigator.pop(c);
                  },
                ),
              ],
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  T(info, style: TextStyle(fontSize: 12)),
                  SizedBox(height: 16),
                  if (code.isNotEmpty) ...[
                    SelectableText(
                      code,
                      style: TextStyle(fontSize: 24, letterSpacing: 3),
                    ),
                    SizedBox(height: 12),
                    ZButton(
                      text: '复制验证码并打开网页',
                      quiet: false,
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: code));
                        openUrl('https://github.com/login/device');
                      },
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      );
    } finally {
      cancelled = true;
      process?.kill();
      await temp.delete(recursive: true);
    }
    return credentials;
  }

  Future<void> cloneProject() async {
    final url = await prompt(
      '克隆远程项目',
      hint: '输入仓库的 HTTPS 或 SSH 地址',
      action: '继续',
    );
    if (url == null || url.trim().isEmpty || !mounted) return;
    final parent = await chooseDirectory(context, '选择保存位置');
    if (parent == null) return;
    final name = await prompt(
      '项目文件夹名称',
      value: p.basename(url).replaceFirst(RegExp(r'\.git$'), ''),
    );
    if (name == null || name.isEmpty) return;
    String? cloned;
    networkActive = true;
    try {
      await perform('正在克隆…', () async {
        if (name.contains(RegExp(r'[/\\]')) ||
            name == '.' ||
            name == '..' ||
            url.startsWith('-')) {
          throw GitFailure(FailureKind.other, '项目名称或地址无效。');
        }
        final target = p.join(parent, name);
        if (await Directory(target).exists()) {
          throw GitFailure(FailureKind.other, '目标目录已存在。');
        }
        final helperPrefix = await git!.credentialPrefix(parent, url);
        try {
          await git!.run(parent, [
            ...helperPrefix,
            'clone',
            '--',
            url,
            target,
          ], timeout: Duration(minutes: 10));
        } on GitFailure catch (e) {
          if (e.kind != FailureKind.authentication) rethrow;
          final credentials = await login(url);
          if (credentials == null) return;
          if (await Directory(target).exists()) {
            throw GitFailure(FailureKind.other, '克隆目录已经产生内容，请选择新目录后重试，避免覆盖。');
          }
          await git!.run(
            parent,
            ['clone', '--', url, target],
            env: credentials.environment,
            timeout: Duration(minutes: 10),
          );
          final helper = await git!.config(target, 'credential.helper');
          if (helper.isNotEmpty || helperPrefix.isNotEmpty) {
            try {
              await git!.run(target, [
                ...helperPrefix,
                'credential',
                'approve',
              ], input: credentials.input);
            } catch (_) {
              await notice('克隆已完成', '系统凭据助手未能保存登录信息，下次连接时可能需要重新登录。');
            }
          }
        }
        cloned = target;
      });
    } finally {
      mutate(() => networkActive = false);
    }
    if (cloned != null) await openProject(cloned!);
  }

  Widget markdownPreview(String text) {
    final headings = <String, GlobalKey>{};
    final headingBuilder = _HeadingBuilder(headings);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: MarkdownBody(
        builders: {for (var i = 1; i <= 6; i++) 'h$i': headingBuilder},
        data: text,
        selectable: true,
        imageBuilder: (uri, title, alt) {
          if (uri.scheme == 'http' || uri.scheme == 'https') {
            return Image.network(
              uri.toString(),
              errorBuilder: (_, _, _) => T(alt ?? '图片无法加载'),
            );
          }
          if (uri.hasScheme || root == null || document == null) {
            return T(alt ?? '图片无法加载');
          }
          final image = p.normalize(
            p.join(p.dirname(document!.path), Uri.decodeComponent(uri.path)),
          );
          return FutureBuilder<String>(
            future: git!.safePath(root!, image),
            builder: (c, snapshot) => snapshot.hasData
                ? Image.file(
                    File(snapshot.data!),
                    errorBuilder: (_, _, _) => T(alt ?? '图片无法加载'),
                  )
                : T(alt ?? '正在读取图片…'),
          );
        },
        onTapLink: (_, href, _) {
          if (href != null && href.startsWith('#')) {
            final target = headings[Uri.decodeComponent(href.substring(1))]
                ?.currentContext;
            if (target != null) {
              Scrollable.ensureVisible(
                target,
                duration: const Duration(milliseconds: 180),
              );
            }
          } else if (href != null &&
              [
                'https',
                'http',
                'mailto',
              ].contains(Uri.tryParse(href)?.scheme)) {
            openUrl(href);
          } else if (href != null &&
              Uri.tryParse(href)?.hasScheme == false &&
              root != null &&
              document != null &&
              !href.startsWith('#')) {
            final path = p.normalize(
              p.join(
                p.dirname(document!.path),
                Uri.decodeComponent(Uri.parse(href).path),
              ),
            );
            openFile(path, pin: true);
          }
        },
        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
          p: TextStyle(fontSize: 13, height: 1.7, color: inkColor(context)),
          code: TextStyle(
            fontFamily: codeFontFamily,
            fontFamilyFallback: codeFontFallback,
            fontSize: 12,
            color: inkColor(context),
          ),
        ),
      ),
    );
  }
}

class _HeadingBuilder extends MarkdownElementBuilder {
  final Map<String, GlobalKey> headings;
  _HeadingBuilder(this.headings);
  @override
  bool isBlockElement() => true;
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final base = element.textContent
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s\-\u0080-\uFFFF]'), '')
        .replaceAll(RegExp(r'\s'), '-');
    var slug = base;
    var count = 0;
    while (headings.containsKey(slug)) {
      slug = '$base-${++count}';
    }
    final key = GlobalKey();
    headings[slug] = key;
    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SelectableText(element.textContent, style: preferredStyle),
    );
  }
}
