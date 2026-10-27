import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';
import 'localization.dart';

const _channel = MethodChannel('app.zhixu/desktop');
final _closers = <int, VoidCallback>{};
int _nextID = 0;
bool _handler = false;

class NativeDialogClose extends StatefulWidget {
  final VoidCallback onClose;
  const NativeDialogClose({super.key, required this.onClose});
  @override
  State<NativeDialogClose> createState() => _NativeDialogCloseState();
}

class _NativeDialogCloseState extends State<NativeDialogClose> {
  final id = ++_nextID;
  final anchor = GlobalKey();
  Animation<double>? animation;
  bool available = true;
  @override
  void initState() {
    super.initState();
    _closers[id] = () => widget.onClose();
    if (!_handler) {
      _handler = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'closeDialog') {
          _closers[call.arguments as int]?.call();
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    animation?.removeListener(sync);
    animation = ModalRoute.of(context)?.animation;
    animation?.addListener(sync);
    sync();
  }

  void sync() {
    if (!Platform.isMacOS || !available) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final box = anchor.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) return;
      final point = box.localToGlobal(Offset.zero);
      try {
        await _channel.invokeMethod('dialogClose', {
          'id': id,
          'x': point.dx,
          'y': point.dy,
          'width': box.size.width,
          'height': box.size.height,
        });
      } on MissingPluginException {
        if (mounted) setState(() => available = false);
      } catch (_) {
        if (mounted) setState(() => available = false);
      }
    });
  }

  @override
  void dispose() {
    animation?.removeListener(sync);
    _closers.remove(id);
    if (Platform.isMacOS) {
      _channel.invokeMethod('removeDialogClose', {'id': id}).catchError((_) {
        return null;
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    sync();
    return SizedBox(
      key: anchor,
      width: 22,
      height: 24,
      child: Platform.isMacOS && available
          ? Semantics(
              button: true,
              label: '关闭',
              onTap: widget.onClose,
              child: const SizedBox(),
            )
          : ZButton(
              icon: Icons.close,
              height: 24,
              tooltip: '关闭',
              onTap: widget.onClose,
            ),
    );
  }
}

String? _chromeState;
void syncWindowChrome(bool dark, String title) {
  if (!Platform.isMacOS && !Platform.isWindows) return;
  final state = '$dark:$title:$uiLanguage';
  if (_chromeState == state) return;
  _chromeState = state;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _channel
        .invokeMethod('windowChrome', {
          'dark': dark,
          'title': title,
          'language': uiLanguage,
        })
        .catchError((_) => null);
  });
}

/// Extend Flutter modal barriers over the AppKit title bar, including transitions.
class NativeModalObserver extends NavigatorObserver {
  final _routes = <PopupRoute<dynamic>, VoidCallback>{};
  final _closing = <PopupRoute<dynamic>>{};
  bool _disposed = false;
  void _sync() {
    if (_disposed || (!Platform.isMacOS && !Platform.isWindows)) return;
    var opacity = 0.0;
    for (final route in _routes.keys.toList()) {
      final animation = route.animation;
      if (_closing.contains(route) &&
          (animation == null || animation.isDismissed)) {
        _remove(route);
        continue;
      }
      final alpha =
          (route.barrierColor?.a ?? 0) *
          Curves.ease.transform((animation?.value ?? 1).clamp(0.0, 1.0));
      opacity = 1 - (1 - opacity) * (1 - alpha);
    }
    _channel.invokeMethod('modalBarrier', opacity).catchError((_) => null);
  }

  void _add(Route<dynamic>? route) {
    if (route is! PopupRoute<dynamic> || _routes.containsKey(route)) return;
    _routes[route] = _sync;
    route.animation?.addListener(_sync);
    _sync();
  }

  void _remove(Route<dynamic> route) {
    final listener = _routes.remove(route);
    if (route is PopupRoute<dynamic> && listener != null) {
      route.animation?.removeListener(listener);
    }
    _closing.remove(route);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute<dynamic>) _closing.add(route);
    _sync();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _remove(route);
    _sync();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _remove(oldRoute);
    _add(newRoute);
    _sync();
  }

  void dispose() {
    for (final route in _routes.keys.toList()) {
      _remove(route);
    }
    _disposed = true;
    if (Platform.isMacOS || Platform.isWindows) {
      _channel.invokeMethod('modalBarrier', 0.0).catchError((_) => null);
    }
  }
}
