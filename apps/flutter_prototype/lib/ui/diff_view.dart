import 'code_editor.dart';
import '../core/line_diff.dart';
import '../core/completion.dart';
import 'localization.dart';

import 'package:flutter/material.dart';

import 'theme.dart';

class DiffRow {
  final String text;
  final int? oldLine, newLine;
  final String kind;
  DiffRow(this.text, this.oldLine, this.newLine, this.kind);
}

List<DiffRow> parseDiff(String patch) {
  final rows = <DiffRow>[];
  int old = 0, next = 0;
  bool hunk = false;
  for (final line in patch.split('\n')) {
    final match = RegExp(r'^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@')
        .firstMatch(line);
    if (match != null) {
      old = int.parse(match[1]!);
      next = int.parse(match[2]!);
      hunk = true;
      continue;
    }
    if (line.startsWith('diff --git') ||
        line.startsWith('index ') ||
        line.startsWith('--- ') ||
        line.startsWith('+++ ') ||
        line.startsWith('new file mode') ||
        line.startsWith('deleted file mode')) {
      continue;
    }
    if (line.startsWith('新增文件：')) {
      hunk = true;
      next = 1;
      continue;
    }
    if (hunk) {
      if (line.startsWith('+')) {
        rows.add(DiffRow(line.substring(1), null, next++, '+'));
      } else if (line.startsWith('-')) {
        rows.add(DiffRow(line.substring(1), old++, null, '-'));
      } else if (line.startsWith(' ')) {
        rows.add(DiffRow(line.substring(1), old++, next++, ' '));
      } else if (line.isNotEmpty) {
        rows.add(DiffRow(line, null, null, ' '));
      }
    } else if (line.isNotEmpty) {
      rows.add(DiffRow(line, null, null, ' '));
    }
  }
  return rows;
}

class DiffView extends StatefulWidget {
  final String patch, path;
  const DiffView(this.patch, {super.key, this.path = ''});
  @override
  State<DiffView> createState() => _DiffViewState();
}

class _DiffViewState extends State<DiffView> {
  final vertical = ScrollController();
  @override
  void initState() {
    super.initState();
    vertical.addListener(redraw);
  }

  void redraw() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    vertical.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = parseDiff(widget.patch);
    if (rows.isEmpty) {
      return Center(
        child: T('没有文本差异', style: const TextStyle(color: Colors.grey)),
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        return Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: rows.fold<double>(
                    box.maxWidth - 80,
                    (w, r) => r.text.length * 7.8 + 110 > w
                        ? r.text.length * 7.8 + 110
                        : w,
                  ),
                  child: SelectionArea(
                    child: ListView.builder(
                      controller: vertical,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      itemCount: rows.length,
                      itemExtent: 20,
                      itemBuilder: (context, i) {
                        final r = rows[i];
                        final tint = r.kind == '+'
                            ? Colors.green
                            : r.kind == '-'
                            ? Colors.red
                            : null;
                        return ColoredBox(
                          color:
                              tint?.withValues(alpha: .12) ??
                              Colors.transparent,
                          child: Row(
                            children: [
                              Container(
                                color: inkColor(context)
                                    .withValues(alpha: .018),
                                width: 40,
                                child: Text(
                                  '${r.oldLine ?? ''}',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontFamily: codeFontFamily,
                                    fontFamilyFallback: codeFontFallback,
                                    color: tint ?? Colors.grey,
                                  ),
                                ),
                              ),
                              Container(
                                color: inkColor(context)
                                    .withValues(alpha: .018),
                                width: 40,
                                child: Text(
                                  '${r.newLine ?? ''}',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontFamily: codeFontFamily,
                                    fontFamilyFallback: codeFontFallback,
                                    color: tint ?? Colors.grey,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 22,
                                child: Text(
                                  r.kind,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: tint),
                                ),
                              ),
                              Expanded(
                                child: syntaxLine(
                                  context,
                                  r.text,
                                  language: widget.path.isEmpty
                                      ? 'javascript'
                                      : sourceLanguage(widget.path),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 80,
              child: CodeMinimap(
                lines: rows.map((r) => r.text).toList(),
                marks: {
                  for (var i = 0; i < rows.length; i++)
                    if (rows[i].kind != ' ')
                      i: rows[i].kind == '+' ? Colors.green : Colors.red,
                },
                controller: vertical,
              ),
            ),
          ],
        );
      },
    );
  }
}

class SplitTextView extends StatefulWidget {
  final String left, right;
  final String leftTitle, rightTitle;
  const SplitTextView({
    super.key,
    required this.left,
    required this.right,
    this.leftTitle = '当前文件',
    this.rightTitle = '备份文件',
  });
  @override
  State<SplitTextView> createState() => _SplitTextViewState();
}

class _SplitTextViewState extends State<SplitTextView> {
  final a = ScrollController(), b = ScrollController();
  bool syncing = false;
  @override
  void initState() {
    super.initState();
    a.addListener(() => sync(a, b));
    b.addListener(() => sync(b, a));
  }

  void sync(ScrollController x, ScrollController y) {
    if (syncing || !y.hasClients) return;
    syncing = true;
    y.jumpTo(x.offset.clamp(0, y.position.maxScrollExtent));
    syncing = false;
  }

  @override
  void dispose() {
    a.dispose();
    b.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = <DiffRow?>[], right = <DiffRow?>[];
    final diff = compareLines(widget.left, widget.right);
    var old = 1, next = 1, i = 0;
    while (i < diff.length) {
      if (diff[i].$1 == ' ') {
        final r = DiffRow(diff[i].$2, old++, next++, ' ');
        left.add(r);
        right.add(r);
        i++;
      } else {
        final removed = <DiffRow>[], added = <DiffRow>[];
        while (i < diff.length && diff[i].$1 != ' ') {
          final row = diff[i++];
          if (row.$1 == '-') {
            removed.add(DiffRow(row.$2, old++, null, '-'));
          } else {
            added.add(DiffRow(row.$2, null, next++, '+'));
          }
        }
        final length = removed.length > added.length
            ? removed.length
            : added.length;
        for (var n = 0; n < length; n++) {
          left.add(n < removed.length ? removed[n] : null);
          right.add(n < added.length ? added[n] : null);
        }
      }
    }
    return Row(
      children: [
        Expanded(child: side(left, widget.leftTitle, a, Colors.red)),
        const SizedBox(width: 10),
        Expanded(child: side(right, widget.rightTitle, b, Colors.green)),
      ],
    );
  }

  Widget side(
    List<DiffRow?> rows,
    String title,
    ScrollController c,
    Color color,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.all(8),
        child: T(
          title,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      Expanded(
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: rows.fold<double>(
                box.maxWidth,
                (width, r) => r != null && r.text.length * 7.3 + 50 > width
                    ? r.text.length * 7.3 + 50
                    : width,
              ),
              child: SelectionArea(
                child: ListView.builder(
                  controller: c,
                  itemCount: rows.length,
                  itemExtent: 20,
                  itemBuilder: (context, i) {
                    final row = rows[i];
                    return ColoredBox(
                      color: row == null || row.kind == ' '
                          ? Colors.transparent
                          : color.withValues(alpha: .12),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 40,
                            child: Text(
                              row == null
                                  ? ''
                                  : '${color == Colors.red ? row.oldLine : row.newLine}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                          Expanded(child: syntaxLine(context, row?.text ?? '')),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

Widget syntaxLine(
  BuildContext context,
  String text, {
  String language = 'javascript',
}) {
  final controller = CodeController(text: text, language: language);
  final span = controller.buildTextSpan(
    context: context,
    style: TextStyle(
      fontFamily: codeFontFamily,
      fontFamilyFallback: codeFontFallback,
      fontSize: 13,
      height: 20 / 13,
      color: inkColor(context),
    ),
    withComposing: false,
  );
  controller.dispose();
  return Text.rich(
    span,
    maxLines: 1,
    softWrap: false,
    overflow: TextOverflow.clip,
  );
}
