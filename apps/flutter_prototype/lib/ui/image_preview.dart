import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'theme.dart';
import '../core/git_service.dart';
import 'localization.dart';

bool isPreviewImage(String path) => const {
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.webp',
  '.bmp',
  '.wbmp',
  '.ico',
}.contains(p.extension(path).toLowerCase());

class ImagePreview extends StatefulWidget {
  final Uint8List bytes;
  const ImagePreview({super.key, required this.bytes});
  @override
  State<ImagePreview> createState() => _ImagePreviewState();
}

class _ImagePreviewState extends State<ImagePreview> {
  final transform = TransformationController();
  bool dragging = false;
  @override
  void didUpdateWidget(ImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bytes != widget.bytes) transform.value = Matrix4.identity();
  }

  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  void zoom(double factor) {
    final current = transform.value.getMaxScaleOnAxis();
    final next = (current * factor).clamp(.25, 8.0);
    transform.value = transform.value.clone()
      ..scaleByDouble(next / current, next / current, 1, 1);
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            T(
              '${(widget.bytes.length / 1024).toStringAsFixed(1)} KB',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const Spacer(),
            ZButton(
              icon: Icons.remove,
              tooltip: '缩小',
              onTap: () => zoom(1 / 1.25),
            ),
            ZButton(
              text: '适应窗口',
              onTap: () => transform.value = Matrix4.identity(),
            ),
            ZButton(icon: Icons.add, tooltip: '放大', onTap: () => zoom(1.25)),
          ],
        ),
      ),
      Expanded(
        child: ClipRect(
          child: CustomPaint(
            painter: _TransparencyGrid(
              Theme.of(context).brightness == Brightness.dark,
            ),
            child: MouseRegion(
              cursor: dragging
                  ? SystemMouseCursors.grabbing
                  : SystemMouseCursors.grab,
              child: InteractiveViewer(
                onInteractionStart: (_) => setState(() => dragging = true),
                onInteractionEnd: (_) => setState(() => dragging = false),
                transformationController: transform,
                minScale: .25,
                maxScale: 8,
                child: SizedBox.expand(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Image.memory(
                      widget.bytes,
                      fit: BoxFit.contain,
                      cacheWidth: 4096,
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) => Center(child: T('图片无法加载')),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class _TransparencyGrid extends CustomPainter {
  final bool dark;
  _TransparencyGrid(this.dark);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = dark ? const Color(0xff242424) : const Color(0xfffafafa),
    );
    final paint = Paint()
      ..color = dark ? const Color(0xff2b2b2b) : const Color(0xffeeeeee);
    for (var y = 0.0; y < size.height; y += 12) {
      for (var x = 0.0; x < size.width; x += 12) {
        if (((x / 12).floor() + (y / 12).floor()).isEven) {
          canvas.drawRect(Rect.fromLTWH(x, y, 12, 12), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_TransparencyGrid oldDelegate) => oldDelegate.dark != dark;
}

/// A pair of repository snapshots. A missing side represents an added/deleted file.
class GitImageComparison extends StatefulWidget {
  final GitService git;
  final String root, path;
  final String? before, after, beforePath;
  const GitImageComparison({
    super.key,
    required this.git,
    required this.root,
    required this.path,
    required this.before,
    required this.after,
    this.beforePath,
  });
  @override
  State<GitImageComparison> createState() => _GitImageComparisonState();
}

class _GitImageComparisonState extends State<GitImageComparison> {
  late Future<List<Uint8List?>> images;
  void load() {
    images = Future.wait([
      widget.git.imageAt(
        widget.root,
        widget.beforePath ?? widget.path,
        widget.before,
      ),
      widget.git.imageAt(widget.root, widget.path, widget.after),
    ]);
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(GitImageComparison oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.root != widget.root ||
        oldWidget.before != widget.before ||
        oldWidget.after != widget.after ||
        oldWidget.beforePath != widget.beforePath) {
      load();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Uint8List?>>(
    future: images,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: T(
            snapshot.error is GitFailure
                ? (snapshot.error as GitFailure).message
                : '图片无法加载',
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      return Row(
        children: [
          for (var i = 0; i < 2; i++)
            Expanded(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: T(i == 0 ? '修改前' : '修改后'),
                  ),
                  Expanded(
                    child: snapshot.data![i] == null
                        ? Center(child: T('此版本中没有此文件'))
                        : ImagePreview(bytes: snapshot.data![i]!),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
}
