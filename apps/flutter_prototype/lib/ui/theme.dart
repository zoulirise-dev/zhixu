import 'native_close.dart';
import 'localization.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

String get codeFontFamily =>
    defaultTargetPlatform == TargetPlatform.windows ? 'Consolas' : '.SF Mono';
List<String> get codeFontFallback =>
    defaultTargetPlatform == TargetPlatform.windows
    ? const ['Microsoft YaHei UI', 'Microsoft YaHei', 'Courier New']
    : const ['Menlo', 'Consolas', 'PingFang SC', 'Courier New'];

const brand = Color(0xff1f63f0);
Color panelColor(BuildContext c) => Theme.of(c).colorScheme.surface;
Color subtleColor(BuildContext c) => Theme.of(c).brightness == Brightness.dark
    ? Color(0xff2e2e2e)
    : Color(0xfff9f9f9);
Color inkColor(BuildContext c) => Theme.of(c).colorScheme.onSurface;
ThemeData workspaceTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: brand,
    primary: brand,
    brightness: brightness,
    surface: dark ? Color(0xff252525) : Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? Color(0xff1a1a1a) : Color(0xfff2f5f9),
    fontFamily: defaultTargetPlatform == TargetPlatform.windows
        ? 'Segoe UI'
        : '.SF Pro Text',
    fontFamilyFallback: defaultTargetPlatform == TargetPlatform.windows
        ? const ['Microsoft YaHei UI', 'Microsoft YaHei', 'Arial']
        : const ['PingFang SC', 'Helvetica Neue', 'Arial'],
    visualDensity: VisualDensity.compact,
    textTheme: TextTheme(
      bodyLarge: TextStyle(fontSize: 12, color: scheme.onSurface),
      bodyMedium: TextStyle(fontSize: 12, color: scheme.onSurface),
      bodySmall: TextStyle(
        fontSize: 10,
        color: scheme.onSurface.withValues(alpha: .5),
      ),
      titleMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: Duration(milliseconds: 500),
      textStyle: TextStyle(
        fontSize: 11,
        color: dark ? Colors.black : Colors.white,
      ),
      decoration: BoxDecoration(
        color: dark ? const Color(0xffeeeeee) : const Color(0xff303030),
        borderRadius: BorderRadius.circular(5),
      ),
    ),
    splashFactory: NoSplash.splashFactory,
    hoverColor: scheme.onSurface.withValues(alpha: .035),
    highlightColor: Colors.transparent,
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStatePropertyAll(5),
      radius: Radius.circular(5),
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => scheme.onSurface.withValues(
          alpha: s.contains(WidgetState.hovered) ? 0.4 : .15,
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      barrierColor: const Color(0x38000000),
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      textStyle: TextStyle(fontSize: 12, color: scheme.onSurface),
    ),
    inputDecorationTheme: InputDecorationTheme(
      floatingLabelBehavior: FloatingLabelBehavior.never,
      isDense: true,
      filled: true,
      fillColor: dark ? Color(0xff303030) : Color(0xfff9f9f9),
      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      hintStyle: TextStyle(
        fontSize: 12,
        color: scheme.onSurface.withValues(alpha: .35),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: BorderSide(color: scheme.onSurface.withValues(alpha: .10)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: BorderSide(color: scheme.onSurface.withValues(alpha: .10)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: BorderSide(color: brand, width: 1),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity(horizontal: -4, vertical: -4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      side: BorderSide(
        color: scheme.onSurface.withValues(alpha: .25),
        width: 1,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.onSurface,
        textStyle: TextStyle(fontSize: 12),
        minimumSize: Size(32, 30),
        padding: EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: brand,
        foregroundColor: Colors.white,
        textStyle: TextStyle(fontSize: 12),
        minimumSize: Size(50, 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      ),
    ),
  );
}

class ZButton extends StatefulWidget {
  final bool italic;
  final String? text, tooltip;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool primary, selected, quiet, danger, loading;
  final double height;
  final Widget? leading;
  const ZButton({
    this.italic = false,
    super.key,
    this.text,
    this.icon,
    this.onTap,
    this.primary = false,
    this.selected = false,
    this.quiet = true,
    this.danger = false,
    this.loading = false,
    this.height = 30,
    this.tooltip,
    this.leading,
  });
  @override
  State<ZButton> createState() => _ZButtonState();
}

class _ZButtonState extends State<ZButton> {
  bool hover = false, pressed = false, focused = false;
  @override
  Widget build(BuildContext context) {
    final w = widget;
    final enabled = w.onTap != null;
    final ink = inkColor(context);
    final color = !enabled
        ? ink.withValues(alpha: .28)
        : w.primary
        ? Colors.white
        : w.danger
        ? Colors.red
        : ink;
    final bg = w.primary
        ? (enabled
              ? (pressed
                    ? const Color(0xff164ac0)
                    : hover || focused
                    ? const Color(0xff1856dc)
                    : brand)
              : ink.withValues(alpha: .035))
        : w.selected
        ? brand.withValues(alpha: .09)
        : ink.withValues(
            alpha: pressed
                ? 0.08
                : hover || focused
                ? 0.035
                : w.quiet
                ? 0
                : .065,
          );
    Widget child = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() {
        hover = false;
        pressed = false;
      }),
      child: GestureDetector(
        onTap: enabled ? w.onTap : null,
        onTapDown: enabled ? (_) => setState(() => pressed = true) : null,
        onTapUp: (_) => setState(() => pressed = false),
        onTapCancel: () => setState(() => pressed = false),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: Duration(milliseconds: 100),
          height: w.height,
          padding: EdgeInsets.symmetric(horizontal: w.text == null ? 7 : 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: !w.quiet && !w.primary
                ? Border.all(color: ink.withValues(alpha: .10))
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (w.loading)
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: color,
                  ),
                )
              else if (w.leading != null)
                w.leading!
              else if (w.icon != null)
                Icon(w.icon, size: 14, color: color),
              if ((w.icon != null || w.leading != null || w.loading) &&
                  w.text != null)
                SizedBox(width: 6),
              if (w.text != null)
                Flexible(
                  child: T(
                    w.text!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: w.italic ? FontStyle.italic : FontStyle.normal,
                      fontWeight: w.primary || w.selected
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: color,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    child = FocusableActionDetector(
      enabled: enabled,
      onShowFocusHighlight: (value) => setState(() => focused = value),
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            if (enabled) w.onTap!();
            return null;
          },
        ),
      },
      child: child,
    );
    child = Semantics(
      button: true,
      enabled: enabled,
      label: w.text == null && w.tooltip == null
          ? null
          : tr(w.text ?? w.tooltip!),
      child: child,
    );
    return w.tooltip == null
        ? child
        : Tooltip(message: tr(w.tooltip!), child: child);
  }
}

class HoverRow extends StatefulWidget {
  final Widget child;
  final bool selected;
  final VoidCallback? onTap;
  final void Function(TapDownDetails)? onSecondaryTapDown;
  const HoverRow({
    super.key,
    required this.child,
    this.selected = false,
    this.onTap,
    this.onSecondaryTapDown,
  });
  @override
  State<HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<HoverRow> {
  bool hover = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: widget.onTap == null
        ? SystemMouseCursors.basic
        : SystemMouseCursors.click,
    onEnter: (_) => setState(() => hover = true),
    onExit: (_) => setState(() => hover = false),
    child: GestureDetector(
      onTap: widget.onTap,
      onSecondaryTapDown: widget.onSecondaryTapDown,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 100),
        decoration: BoxDecoration(
          color: widget.selected
              ? brand.withValues(alpha: .09)
              : hover
              ? inkColor(context).withValues(alpha: .035)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: widget.child,
      ),
    ),
  );
}

class ZDialog extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget> actions;
  final List<Widget> headerActions;
  final double width;
  final double? height;
  final bool scroll;
  const ZDialog({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.headerActions = const [],
    this.width = 500,
    this.height,
    this.scroll = true,
  });
  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: EdgeInsets.symmetric(horizontal: 32, vertical: 32),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: width,
        maxHeight: MediaQuery.sizeOf(context).height - 64,
      ),
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 40,
              child: Row(
                children: [
                  if (Theme.of(context).platform == TargetPlatform.windows)
                    const SizedBox(width: 20)
                  else ...[
                    const SizedBox(width: 9),
                    NativeDialogClose(onClose: () => Navigator.pop(context)),
                    const SizedBox(width: 5),
                  ],
                  Expanded(
                    child: T(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  ...headerActions,
                  if (Theme.of(context).platform == TargetPlatform.windows) ...[
                    const SizedBox(width: 8),
                    ZButton(
                      key: const Key('windows-dialog-close'),
                      icon: Icons.close,
                      tooltip: '关闭',
                      onTap: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                  ] else
                    const SizedBox(width: 20),
                ],
              ),
            ),
            Flexible(
              child: scroll
                  ? FadingScroll(
                      padding: EdgeInsets.fromLTRB(24, 10, 24, 12),
                      child: child,
                    )
                  : Padding(
                      padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: child,
                    ),
            ),
            if (actions.isNotEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (final a in actions) ...[SizedBox(width: 8), a],
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class MenuAction {
  final String label;
  final IconData? icon;
  final VoidCallback action;
  final bool enabled, destructive;
  MenuAction(
    this.label,
    this.action, {
    this.icon,
    this.enabled = true,
    this.destructive = false,
  });
}

Future<void> contextMenu(
  BuildContext context,
  Offset position,
  List<MenuAction> items,
) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final selected = await showMenu<int>(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromLTWH(position.dx, position.dy, 1, 1),
      Offset.zero & overlay.size,
    ),
    constraints: BoxConstraints(minWidth: 150, maxWidth: 230),
    items: [
      for (var i = 0; i < items.length; i++)
        PopupMenuItem(
          value: i,
          enabled: items[i].enabled,
          height: 30,
          child: Row(
            children: [
              Icon(
                items[i].icon ?? Icons.circle_outlined,
                size: 13,
                color: items[i].destructive ? Colors.red : Colors.grey,
              ),
              SizedBox(width: 9),
              Flexible(
                child: T(
                  items[i].label,
                  style: TextStyle(
                    fontSize: 12,
                    color: items[i].destructive ? Colors.red : null,
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );
  if (selected != null) items[selected].action();
}

class BranchSymbol extends StatelessWidget {
  const BranchSymbol({super.key});
  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(16, 16),
    painter: _BranchPainter(inkColor(context)),
  );
}

class _BranchPainter extends CustomPainter {
  final Color color;
  _BranchPainter(this.color);
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    c.drawCircle(Offset(4, 3), 1.6, p);
    c.drawCircle(Offset(4, 13), 1.6, p);
    c.drawCircle(Offset(12, 5), 1.6, p);
    c.drawPath(
      Path()
        ..moveTo(4, 4.6)
        ..lineTo(4, 11.4)
        ..moveTo(12, 6.6)
        ..lineTo(12, 7.4)
        ..cubicTo(12, 10, 4, 7.4, 4, 10),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant _BranchPainter old) => old.color != color;
}

class FileSymbol extends StatelessWidget {
  final String path;
  const FileSymbol(this.path, {super.key});
  @override
  Widget build(BuildContext context) {
    final name = path.split('/').last.toLowerCase();
    final ext = name.split('.').last;
    const gold = Color(0xffa68205);
    final (label, icon, color) = switch (ext) {
      'js' || 'jsx' || 'mjs' || 'cjs' => ('JS', null, gold),
      'ts' || 'tsx' => ('TS', null, Colors.blue),
      'php' => ('php', null, const Color(0xff9161ba)),
      'py' || 'pyw' => ('PY', null, Colors.blue),
      'css' ||
      'scss' ||
      'sass' ||
      'less' => ('#', null, const Color(0xff2e87ab)),
      'html' ||
      'htm' ||
      'xml' ||
      'vue' ||
      'svelte' => ('</>', null, Colors.orange),
      'json' || 'yaml' || 'yml' || 'toml' => ('{}', null, gold),
      'md' || 'txt' => ('', Icons.description_outlined, Colors.grey),
      'swift' => ('SW', null, Colors.orange),
      'dart' => ('D', null, Colors.blue),
      'png' ||
      'jpg' ||
      'jpeg' ||
      'gif' ||
      'bmp' ||
      'svg' ||
      'ico' ||
      'webp' => ('', Icons.image_outlined, Colors.purple),
      _ => (
        '',
        name.contains('env') || name.contains('config')
            ? Icons.settings_outlined
            : name.startsWith('.git')
            ? Icons.diamond_outlined
            : Icons.insert_drive_file_outlined,
        Colors.grey,
      ),
    };
    return SizedBox(
      width: 16,
      height: 16,
      child: Center(
        child: label.isEmpty
            ? Icon(icon, size: 13, color: color)
            : Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: codeFontFamily,
                  fontSize: ext == 'php'
                      ? 8
                      : label == '</>'
                      ? 10
                      : 9,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
      ),
    );
  }
}

class MiddleText extends StatelessWidget {
  final String text;
  final TextStyle style;
  const MiddleText(this.text, {super.key, required this.style});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final effective = DefaultTextStyle.of(context).style.merge(style);
      final painter = TextPainter(
        textDirection: Directionality.of(context),
        maxLines: 1,
        textScaler: MediaQuery.textScalerOf(context),
      );
      bool fits(String value) {
        painter.text = TextSpan(text: value, style: effective);
        painter.layout();
        return painter.width <= constraints.maxWidth;
      }

      var result = text;
      if (constraints.hasBoundedWidth && !fits(text)) {
        final chars = text.characters.toList();
        var low = 0, high = chars.length;
        while (low < high) {
          final count = (low + high + 1) ~/ 2;
          final candidate =
              '${chars.take((count + 1) ~/ 2).join()}…${chars.skip(chars.length - count ~/ 2).join()}';
          if (fits(candidate)) {
            low = count;
            result = candidate;
          } else {
            high = count - 1;
          }
        }
        if (low == 0) result = '…';
      }
      painter.dispose();
      return Text(
        result,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.clip,
      );
    },
  );
}

class ProjectStackIcon extends StatelessWidget {
  final Color color;
  const ProjectStackIcon({super.key, required this.color});
  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(16, 16),
    painter: _ProjectStackPainter(color),
  );
}

class _ProjectStackPainter extends CustomPainter {
  final Color color;
  _ProjectStackPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(2, 5)
        ..lineTo(8, 1.5)
        ..lineTo(14, 5)
        ..lineTo(8, 8.5)
        ..close(),
      paint,
    );
    for (final y in [8.0, 11.0]) {
      canvas.drawPath(
        Path()
          ..moveTo(2, y)
          ..lineTo(8, y + 3.5)
          ..lineTo(14, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ProjectStackPainter old) => color != old.color;
}

class FadingScroll extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const FadingScroll({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });
  @override
  State<FadingScroll> createState() => _FadingScrollState();
}

class _FadingScrollState extends State<FadingScroll> {
  bool top = true, bottom = true;
  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (n) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted &&
                (top != (n.metrics.pixels <= 0) ||
                    bottom != (n.metrics.extentAfter <= 0))) {
              setState(() {
                top = n.metrics.pixels <= 0;
                bottom = n.metrics.extentAfter <= 0;
              });
            }
          });
          return false;
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            final a = n.metrics.pixels <= 0, b = n.metrics.extentAfter <= 0;
            if (a != top || b != bottom) {
              setState(() {
                top = a;
                bottom = b;
              });
            }
            return false;
          },
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                top ? Colors.white : Colors.transparent,
                Colors.white,
                Colors.white,
                bottom ? Colors.white : Colors.transparent,
              ],
              stops: const [0, .025, .975, 1],
            ).createShader(bounds),
            child: SingleChildScrollView(
              padding: widget.padding,
              child: widget.child,
            ),
          ),
        ),
      );
}

Color changeBadgeColor(String badge) => switch (badge) {
  'U' || 'A' => const Color(0xff007d36),
  'D' || '!' => Colors.red,
  'R' => Colors.blue,
  _ => const Color(0xffa76000),
};

class ChangeBadge extends StatelessWidget {
  final String badge;
  const ChangeBadge(this.badge, {super.key});
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tr(switch (badge) {
      'U' => '未跟踪',
      'A' => '新增',
      'D' => '已删除',
      'R' => '重命名',
      '!' => '合并冲突',
      _ => '已修改',
    }),
    child: SizedBox(
      width: 14,
      height: 24,
      child: Center(
        child: Text(
          badge,
          style: TextStyle(
            fontFamily: codeFontFamily,
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: changeBadgeColor(badge),
          ),
        ),
      ),
    ),
  );
}

/// Keep the original hit target while reducing only the visual checkbox to 14 pt.
class CompactCheckbox extends StatelessWidget {
  final bool? value;
  final ValueChanged<bool?>? onChanged;
  const CompactCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => Transform.scale(
    scale: 14 / 18,
    transformHitTests: false,
    child: Checkbox(value: value, onChanged: onChanged),
  );
}
