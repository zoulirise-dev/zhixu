import 'dart:io';

import 'package:flutter/material.dart';

import '../core/directory_browser.dart';

import 'theme.dart';
import 'localization.dart';

Future<String?> chooseDirectory(BuildContext context, String title) =>
    showDialog<String>(
      context: context,
      builder: (_) => DirectoryPicker(title: title),
    );

class DirectoryPicker extends StatefulWidget {
  final String title;
  final DirectoryBrowser? browser;
  const DirectoryPicker({super.key, required this.title, this.browser});
  @override
  State<DirectoryPicker> createState() => _DirectoryPickerState();
}

class _DirectoryPickerState extends State<DirectoryPicker> {
  late final browser = widget.browser ?? DirectoryBrowser();
  String get home => browser.home;
  bool drivesView = false;
  final path = TextEditingController();
  String current = '', error = '';
  List<String> folders = [];
  bool loading = true;
  int request = 0;
  @override
  void initState() {
    super.initState();
    navigate(home);
  }

  @override
  void dispose() {
    request++;
    path.dispose();
    super.dispose();
  }

  Future<void> navigate(String value) async {
    final id = ++request;
    final next = browser.normalize(value, current);
    setState(() {
      loading = true;
      error = '';
    });
    try {
      final dirs = await browser.folders(next);
      if (!mounted || id != request) return;
      setState(() {
        drivesView = false;
        current = next;
        path.text = next;
        folders = dirs;
        loading = false;
      });
    } catch (e) {
      if (!mounted || id != request) return;
      setState(() {
        loading = false;
        folders = [];
        current = '';
        path.text = next;
        error = e is FileSystemException && e.osError?.errorCode == 21
            ? '磁盘尚未就绪，请插入介质或解锁磁盘后重试。'
            : '无法读取此文件夹，请检查访问权限后重试。';
      });
    }
  }

  Future<void> showDrives() async {
    final id = ++request;
    setState(() {
      loading = true;
      error = '';
      current = '';
      drivesView = true;
      path.clear();
    });
    try {
      final drives = await browser.drives();
      if (!mounted || id != request) return;
      setState(() {
        folders = drives;
        loading = false;
      });
    } catch (_) {
      if (!mounted || id != request) return;
      setState(() {
        folders = [];
        loading = false;
        error = '无法读取磁盘列表，请重试。';
      });
    }
  }

  @override
  Widget build(BuildContext context) => ZDialog(
    title: widget.title,
    width: 760,
    height: 570,
    scroll: false,
    actions: [
      Expanded(
        child: Text(
          current,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11),
        ),
      ),
      ZButton(text: '取消', onTap: () => Navigator.pop(context)),
      ZButton(
        text: '选择文件夹',
        primary: true,
        onTap: loading || error.isNotEmpty || current.isEmpty
            ? null
            : () => Navigator.pop(context, current),
      ),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        T('单击文件夹进入，点击“选择文件夹”确认当前目录。', style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 12),
        Row(
          children: [
            ZButton(
              text: '上一级',
              icon: Icons.arrow_upward,
              onTap: loading || current.isEmpty
                  ? null
                  : () => browser.windows && browser.isRoot(current)
                        ? showDrives()
                        : navigate(browser.paths.dirname(current)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: path,
                onSubmitted: navigate,
                decoration: InputDecoration(
                  hintText: tr(drivesView ? '此电脑 · 输入文件夹路径' : '输入文件夹路径，按回车前往'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ZButton(text: '前往', onTap: () => navigate(path.text)),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Row(
            children: [
              SizedBox(
                width: 140,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(padding: const EdgeInsets.all(8), child: T('常用位置')),
                    for (final item in [
                      ('个人目录', home),
                      ('桌面', browser.paths.join(home, 'Desktop')),
                      ('文稿', browser.paths.join(home, 'Documents')),
                      ('下载', browser.paths.join(home, 'Downloads')),
                      (
                        browser.windows ? '此电脑' : '磁盘',
                        browser.paths.rootPrefix(home),
                      ),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: ZButton(
                          text: item.$1,
                          icon: Icons.folder_outlined,
                          onTap: () => browser.windows && item.$1 == '此电脑'
                              ? showDrives()
                              : navigate(item.$2),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: loading
                    ? const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : error.isNotEmpty
                    ? Center(child: T(error))
                    : folders.isEmpty
                    ? Center(
                        child: T(drivesView ? '没有可用磁盘' : '这里没有子文件夹\n可以选择当前文件夹'),
                      )
                    : ListView.builder(
                        itemCount: folders.length,
                        itemBuilder: (context, index) {
                          final folder = folders[index];
                          return HoverRow(
                            onTap: () => navigate(folder),
                            child: SizedBox(
                              height: 36,
                              child: Row(
                                children: [
                                  const SizedBox(width: 8),
                                  Icon(
                                    drivesView
                                        ? Icons.storage_outlined
                                        : Icons.folder_outlined,
                                    size: 17,
                                    color: Colors.blue,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      drivesView
                                          ? folder
                                          : browser.paths.basename(folder),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  ZButton(
                                    icon: Icons.chevron_right,
                                    onTap: () => navigate(folder),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
