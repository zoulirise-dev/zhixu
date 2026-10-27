import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zhixu_prototype/ui/code_editor.dart';

void main() {
  test(
    'long minimap has minimum thumb and sliding background at both ends',
    () {
      for (final count in [1, 100, 10000, 1000000]) {
        final maxScroll = (count * 20.0 - 300).clamp(0.0, double.infinity);
        final start = MinimapGeometry(
          height: 300,
          lines: count,
          maxScroll: maxScroll,
          offset: 0,
        );
        final end = MinimapGeometry(
          height: 300,
          lines: count,
          maxScroll: maxScroll,
          offset: maxScroll,
        );
        expect(start.thumbHeight, greaterThanOrEqualTo(40));
        expect(start.thumbHeight, lessThanOrEqualTo(300));
        expect(start.thumbTop, 0);
        if (maxScroll > 0) {
          expect(end.thumbTop + end.thumbHeight, closeTo(300, .001));
          expect(end.scrollAt(end.travel), closeTo(maxScroll, .001));
        }
        if (count > 1000) expect(end.backgroundOffset, greaterThan(0));
      }
    },
  );
  test('minimap painter never draws outside its assigned rectangle', () async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..translate(10, 10);
    CodeMinimapPainter(
      List.filled(200, '                              ${'x' * 300}'),
      {1: Colors.green},
      500,
      80,
      Colors.black,
    ).paint(canvas, const Size(80, 80));
    final picture = recorder.endRecording();
    final image = await picture.toImage(110, 110);
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    for (var y = 0; y < 110; y++) {
      for (var x = 0; x < 110; x++) {
        if (x < 10 || x >= 90 || y < 10 || y >= 90) {
          expect(data.getUint8((y * 110 + x) * 4 + 3), 0);
        }
      }
    }
    image.dispose();
    picture.dispose();
  });
  testWidgets('thumb drag stays put on press and reaches document end', (
    tester,
  ) async {
    final controller = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: Row(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: controller,
                    itemExtent: 20,
                    itemCount: 10000,
                    itemBuilder: (_, i) => Text('$i'),
                  ),
                ),
                SizedBox(
                  width: 80,
                  child: CodeMinimap(
                    lines: List.filled(10000, 'line'),
                    marks: const {},
                    controller: controller,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final origin = tester.getTopLeft(find.byType(CodeMinimap));
    final gesture = await tester.startGesture(origin + const Offset(40, 12));
    await tester.pump();
    expect(controller.offset, 0);
    await gesture.moveTo(origin + const Offset(40, 299));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(controller.position.maxScrollExtent, 1));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
