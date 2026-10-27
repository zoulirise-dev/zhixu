import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';
import '../core/completion.dart';
import '../core/syntax.dart';

class CodeController extends TextEditingController {
  String _language;
  String get language => _language;
  set language(String value) {
    if (_language == value) return;
    _language = value;
    notifyListeners();
  }

  // Keep the public named parameter while using a notifying property setter.
  CodeController({super.text, String language = 'javascript'})
    // ignore: prefer_initializing_formals
    : _language = language;
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (!value.composing.isCollapsed || text.length > 250000) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final spans = <TextSpan>[];
    var end = 0;
    final dark = Theme.of(context).brightness == Brightness.dark;
    for (final match in syntaxTokens(text, language)) {
      if (match.$1 > end) {
        spans.add(TextSpan(text: text.substring(end, match.$1)));
      }
      final color = switch (match.$3) {
        'comment' => dark ? const Color(0xff6a9955) : const Color(0xff608060),
        'string' => dark ? const Color(0xffce9178) : const Color(0xffa31515),
        'number' => dark ? const Color(0xffb5cea8) : const Color(0xff098658),
        'type' => dark ? const Color(0xff4ec9b0) : const Color(0xff267f99),
        'function' => dark ? const Color(0xffdcdcaa) : const Color(0xff795e26),
        'property' => dark ? const Color(0xff9cdcfe) : const Color(0xff001080),
        'insertion' => const Color(0xff2eae57),
        'deletion' => Colors.red,
        _ => dark ? const Color(0xffc586c0) : const Color(0xff005cc5),
      };
      spans.add(
        TextSpan(
          text: text.substring(match.$1, match.$2),
          style: TextStyle(color: color),
        ),
      );
      end = match.$2;
    }
    spans.add(TextSpan(text: text.substring(end)));
    return TextSpan(style: style, children: spans);
  }
}

/// Format only direct ASCII keystrokes. Never modify composing/preedit text,
/// or the event which commits a composition.
class CodeInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!oldValue.composing.isCollapsed ||
        !newValue.composing.isCollapsed ||
        !newValue.selection.isCollapsed ||
        !oldValue.selection.isCollapsed) {
      return newValue;
    }
    final offset = oldValue.selection.baseOffset;
    if (offset < 0 ||
        newValue.text.length != oldValue.text.length + 1 ||
        newValue.selection.baseOffset != offset + 1) {
      return newValue;
    }
    if (newValue.text.substring(0, offset) !=
            oldValue.text.substring(0, offset) ||
        newValue.text.substring(offset + 1) !=
            oldValue.text.substring(offset)) {
      return newValue;
    }
    final char = newValue.text[offset];
    final pairs = {'(': ')', '[': ']', '{': '}', '"': '"', "'": "'"};
    if (pairs.containsKey(char)) {
      final next = offset < oldValue.text.length ? oldValue.text[offset] : '';
      if (next.isEmpty || RegExp(r'[\s)\]}]').hasMatch(next)) {
        return newValue.copyWith(
          text: newValue.text.replaceRange(
            offset + 1,
            offset + 1,
            pairs[char]!,
          ),
          selection: TextSelection.collapsed(offset: offset + 1),
          composing: TextRange.empty,
        );
      }
    }
    if (char == '\n') {
      final previous = oldValue.text.substring(0, offset).split('\n').last;
      final indentation = RegExp(r'^\s*')
          .firstMatch(previous)![0]!
          .replaceAll('\n', '');
      final extra = previous.trimRight().endsWith('{') ? '  ' : '';
      final suffix = oldValue.text.substring(offset);
      final tail = extra.isNotEmpty && suffix.startsWith('}')
          ? '\n$indentation'
          : '';
      return newValue.copyWith(
        text: newValue.text.replaceRange(
          offset + 1,
          offset + 1,
          '$indentation$extra$tail',
        ),
        selection: TextSelection.collapsed(
          offset: offset + 1 + indentation.length + extra.length,
        ),
      );
    }
    return newValue;
  }
}

Map<int, Color> lineMarks(String baseline, String text) {
  // CRLF checkout conversion does not change a line's content.
  List<String> lines(String value) =>
      value.isEmpty ? [] : value.replaceAll('\r\n', '\n').split('\n');
  final old = lines(baseline), next = lines(text), marks = <int, Color>{};
  int a = 0, b = 0;
  while (a < old.length && b < next.length) {
    if (old[a] == next[b]) {
      a++;
      b++;
      continue;
    }
    var da = -1, db = -1;
    for (var n = 1; n <= 40; n++) {
      if (da < 0 && a + n < old.length && old[a + n] == next[b]) da = n;
      if (db < 0 && b + n < next.length && next[b + n] == old[a]) db = n;
      if (da >= 0 || db >= 0) break;
    }
    if (da >= 0 && (db < 0 || da <= db)) {
      marks[b] = Colors.red;
      a += da;
    } else if (db >= 0) {
      for (var n = 0; n < db; n++) {
        marks[b++] = const Color(0xff2eae57);
      }
    } else {
      marks[b++] = const Color(0xff2795ee);
      a++;
    }
  }
  while (b < next.length) {
    marks[b++] = const Color(0xff2eae57);
  }
  if (a < old.length) marks[math.max(0, next.length - 1)] = Colors.red;
  return marks;
}

class CodeEditor extends StatefulWidget {
  final CodeController controller;
  final String baseline;
  final bool assistance;
  const CodeEditor({
    super.key,
    required this.controller,
    this.baseline = '',
    this.assistance = true,
  });
  @override
  State<CodeEditor> createState() => _CodeEditorState();
}

class _CodeEditorState extends State<CodeEditor> {
  final vertical = ScrollController(), horizontal = ScrollController();
  final focus = FocusNode();
  List<(String, String)> candidates = [];
  int candidate = 0;
  bool dismiss = false;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(changed);
    vertical.addListener(scroll);
  }

  void scroll() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(CodeEditor old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(changed);
      widget.controller.addListener(changed);
    }
  }

  void changed() {
    final value = widget.controller.value;
    final offset = value.selection.baseOffset;
    if (!widget.assistance ||
        !value.composing.isCollapsed ||
        offset < 0 ||
        !value.selection.isCollapsed) {
      candidates = [];
    } else {
      final prefix =
          RegExp(r'[A-Za-z_$][A-Za-z0-9_$-]*$')
              .firstMatch(value.text.substring(0, offset))?[0] ??
          '';
      if (prefix.length < 2) {
        candidates = [];
      } else {
        candidates = completeCode(
          value.text,
          prefix,
          widget.controller.language,
        );
      }
      candidate = 0;
    }
    dismiss = false;
    if (mounted) setState(() {});
  }

  void accept() {
    if (candidates.isEmpty || !widget.controller.value.composing.isCollapsed) {
      return;
    }
    final value = widget.controller.value;
    final offset = value.selection.baseOffset;
    final match = RegExp(r'[A-Za-z_$][A-Za-z0-9_$-]*$')
        .firstMatch(value.text.substring(0, offset));
    if (match == null) return;
    final line = value.text.substring(0, match.start).split('\n').last;
    final indent = RegExp(r'^\s*').firstMatch(line)![0]!;
    final insertion = insertSnippet(candidates[candidate].$2, indent);
    final text = insertion.$1;
    widget.controller.value = TextEditingValue(
      text: value.text.replaceRange(match.start, offset, text),
      selection: TextSelection.collapsed(offset: match.start + insertion.$2),
    );
    setState(() => dismiss = true);
  }

  KeyEventResult key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        !widget.controller.value.composing.isCollapsed) {
      return KeyEventResult.ignored;
    }
    if (widget.assistance && candidates.isNotEmpty && !dismiss) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
          event.logicalKey == LogicalKeyboardKey.arrowUp) {
        setState(
          () => candidate =
              (candidate +
                  (event.logicalKey == LogicalKeyboardKey.arrowDown ? 1 : -1)) %
              candidates.length,
        );
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        setState(() => dismiss = true);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.tab ||
          event.logicalKey == LogicalKeyboardKey.enter) {
        accept();
        return KeyEventResult.handled;
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      final value = widget.controller.value;
      if (value.selection.isValid) {
        widget.controller.value = TextEditingValue(
          text: value.text.replaceRange(
            value.selection.start,
            value.selection.end,
            '  ',
          ),
          selection: TextSelection.collapsed(offset: value.selection.start + 2),
        );
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    widget.controller.removeListener(changed);
    vertical.dispose();
    horizontal.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => ValueListenableBuilder<TextEditingValue>(
      valueListenable: widget.controller,
      builder: (context, value, _) {
        final lines = value.text.split('\n');
        final longest = lines.fold<int>(
          0,
          (n, s) => math.max(n, s.runes.length),
        );
        final width = math.max(box.maxWidth - 86, longest * 7.8 + 90);
        final marks = lineMarks(widget.baseline, value.text);
        final offset = value.selection.baseOffset.clamp(0, value.text.length);
        final before = value.text.substring(0, offset);
        final row = before.split('\n').length - 1;
        final column = before.split('\n').last.runes.length;
        final scrollOffset = vertical.hasClients ? vertical.offset : 0.0;
        final style = TextStyle(
          fontFamily: codeFontFamily,
          fontFamilyFallback: codeFontFallback,
          fontSize: 13,
          height: 20 / 13,
          color: inkColor(context),
        );
        final gutter = Container(
          width: 50,
          color: inkColor(context).withValues(alpha: .018),
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            children: [
              for (var i = 0; i < lines.length; i++)
                SizedBox(
                  height: 20,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        right: 13,
                        child: Text(
                          '${i + 1}',
                          textAlign: TextAlign.right,
                          style: style.copyWith(
                            fontSize: 11,
                            height: 20 / 11,
                            color: i == row
                                ? inkColor(context)
                                : inkColor(context).withValues(alpha: .35),
                          ),
                        ),
                      ),
                      if (marks[i] != null)
                        Positioned(
                          right: 4,
                          top: 0,
                          child: marks[i] == Colors.red
                              ? const Icon(
                                  Icons.arrow_right,
                                  size: 10,
                                  color: Colors.red,
                                )
                              : Container(
                                  width: 3,
                                  height: 20,
                                  color: marks[i],
                                ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
        final input = TextField(
          key: const Key('code-input'),
          controller: widget.controller,
          focusNode: focus,
          style: style,
          strutStyle: const StrutStyle(
            fontSize: 13,
            height: 20 / 13,
            forceStrutHeight: true,
          ),
          maxLines: null,
          inputFormatters: widget.assistance ? [CodeInputFormatter()] : [],
          keyboardType: TextInputType.multiline,
          autocorrect: false,
          enableSuggestions: false,
          smartDashesType: SmartDashesType.disabled,
          smartQuotesType: SmartQuotesType.disabled,
          decoration: const InputDecoration(
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            contentPadding: EdgeInsets.fromLTRB(10, 12, 24, 48),
          ),
        );
        final content = Scrollbar(
          controller: vertical,
          child: SingleChildScrollView(
            controller: vertical,
            child: Scrollbar(
              controller: horizontal,
              notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
              child: SingleChildScrollView(
                controller: horizontal,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: width,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      gutter,
                      Expanded(child: input),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        final minimap = CodeMinimap(
          lines: lines,
          marks: marks,
          controller: vertical,
        );
        return Focus(
          onKeyEvent: key,
          child: Stack(
            children: [
              Positioned.fill(right: 80, child: content),
              Positioned(
                top: 0,
                right: 0,
                bottom: 0,
                width: 80,
                child: minimap,
              ),
              if (widget.assistance &&
                  candidates.isNotEmpty &&
                  !dismiss &&
                  focus.hasFocus &&
                  value.composing.isCollapsed)
                Positioned(
                  left:
                      (50 +
                              column * 7.2 -
                              (horizontal.hasClients ? horizontal.offset : 0.0))
                          .clamp(0.0, math.max(0.0, box.maxWidth - 310)),
                  top: (10 + (row + 1) * 20 - scrollOffset).clamp(
                    0.0,
                    math.max(0.0, box.maxHeight - candidates.length * 26 - 8),
                  ),
                  width: 230,
                  child: Material(
                    elevation: 6,
                    color: panelColor(context),
                    borderRadius: BorderRadius.circular(6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < candidates.length; i++)
                          HoverRow(
                            selected: i == candidate,
                            onTap: () {
                              candidate = i;
                              accept();
                              focus.requestFocus();
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.code,
                                    size: 12,
                                    color: brand,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      candidates[i].$1,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontFamily: codeFontFamily,
                                        fontFamilyFallback: codeFontFallback,
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
        );
      },
    ),
  );
}

/// Fixed-scale code with a sliding background and a usable viewport thumb.
class MinimapGeometry {
  final double height, contentHeight, maxScroll, offset;
  MinimapGeometry({
    required this.height,
    required int lines,
    required this.maxScroll,
    required double offset,
  }) : contentHeight = lines * 2.2 + 10,
       offset = offset.clamp(0.0, math.max(0.0, maxScroll));
  double get progress => maxScroll <= 0 ? 0 : offset / maxScroll;
  double get thumbHeight => math.min(
    height,
    math.max(40, height / (maxScroll + height) * contentHeight),
  );
  double get travel => math.max(0, height - thumbHeight);
  double get thumbTop => progress * travel;
  double get backgroundOffset => progress * math.max(0, contentHeight - height);
  double scrollAt(double top) =>
      travel <= 0 ? 0 : (top / travel * maxScroll).clamp(0.0, maxScroll);
}

class CodeMinimap extends StatefulWidget {
  final List<String> lines;
  final Map<int, Color> marks;
  final ScrollController controller;
  const CodeMinimap({
    super.key,
    required this.lines,
    required this.marks,
    required this.controller,
  });
  @override
  State<CodeMinimap> createState() => _CodeMinimapState();
}

class _CodeMinimapState extends State<CodeMinimap> {
  double? grab;
  bool hovered = false;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final geometry = MinimapGeometry(
          height: box.maxHeight,
          lines: widget.lines.length,
          maxScroll:
              controller.hasClients && controller.position.hasContentDimensions
              ? controller.position.maxScrollExtent
              : math.max(0, widget.lines.length * 20.0 - box.maxHeight),
          offset: controller.hasClients ? controller.offset : 0,
        );
        void move(double y) {
          if (controller.hasClients) {
            controller.jumpTo(
              geometry.scrollAt(y - (grab ?? geometry.thumbHeight / 2)),
            );
          }
        }

        return ClipRect(
          child: MouseRegion(
            cursor: grab != null
                ? SystemMouseCursors.grabbing
                : SystemMouseCursors.grab,
            onEnter: (_) => setState(() => hovered = true),
            onExit: (_) => setState(() => hovered = false),
            child: Listener(
              onPointerDown: (event) {
                final y = event.localPosition.dy;
                grab =
                    y >= geometry.thumbTop &&
                        y <= geometry.thumbTop + geometry.thumbHeight
                    ? y - geometry.thumbTop
                    : geometry.thumbHeight / 2;
                move(y);
                setState(() {});
              },
              onPointerMove: (event) {
                if (grab != null) move(event.localPosition.dy);
              },
              onPointerUp: (_) => setState(() => grab = null),
              onPointerCancel: (_) => setState(() => grab = null),
              child: CustomPaint(
                size: Size.infinite,
                painter: CodeMinimapPainter(
                  widget.lines,
                  widget.marks,
                  geometry.offset,
                  box.maxHeight,
                  inkColor(context),
                  maxScroll: geometry.maxScroll,
                  active: hovered || grab != null,
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

class CodeMinimapPainter extends CustomPainter {
  final List<String> lines;
  final Map<int, Color> marks;
  final double offset, viewport;
  final double? maxScroll;
  final Color color;
  final bool active;
  CodeMinimapPainter(
    this.lines,
    this.marks,
    this.offset,
    this.viewport,
    this.color, {
    this.maxScroll,
    this.active = false,
  });
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final geometry = MinimapGeometry(
      height: size.height,
      lines: lines.length,
      maxScroll: maxScroll ?? math.max(0, lines.length * 20.0 + 58 - viewport),
      offset: offset,
    );
    final first = math.max(0, ((geometry.backgroundOffset - 5) / 2.2).floor());
    final last = math.min(
      lines.length,
      ((geometry.backgroundOffset + size.height) / 2.2).ceil(),
    );
    final paint = Paint()..color = color.withValues(alpha: .20);
    for (var i = first; i < last; i++) {
      final line = lines[i];
      final y = 5 + i * 2.2 - geometry.backgroundOffset;
      if (line.trim().isNotEmpty) {
        final x =
            4.0 +
            math.min(30.0, (line.length - line.trimLeft().length).toDouble());
        final width = math.max(
          0.0,
          math.min(size.width - x - 6, line.trim().length.toDouble()),
        );
        canvas.drawRect(Rect.fromLTWH(x, y, width, 1.4), paint);
      }
      if (marks[i] != null) {
        canvas.drawRect(
          Rect.fromLTWH(size.width - 4, y, 3, 2.2),
          Paint()..color = marks[i]!,
        );
      }
    }
    final thumb = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        .5,
        geometry.thumbTop,
        size.width - 1,
        geometry.thumbHeight,
      ),
      const Radius.circular(3),
    );
    canvas.drawRRect(
      thumb,
      Paint()..color = color.withValues(alpha: active ? .16 : .08),
    );
    canvas.drawRRect(
      thumb,
      Paint()
        ..color = color.withValues(alpha: active ? .28 : .16)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CodeMinimapPainter old) => true;
}
