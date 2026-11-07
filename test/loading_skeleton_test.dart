import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/loading_skeleton.dart';

void main() {
  for (final height in [320.0, 900.0]) {
    testWidgets('library skeleton fills a $height pixel list', (tester) async {
      tester.view.physicalSize = const Size(500, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                height: height,
                child: const LibraryLoadingSkeleton(),
              ),
            ),
          ),
        ),
      );
      final list = tester.widget<ListView>(find.byType(ListView));
      expect(list.childrenDelegate.estimatedChildCount, (height / 72).ceil());
      expect(list.itemExtent, 72);
      for (var i = 0; i < 3; i++) {
        final row = tester.getRect(find.byKey(ValueKey('skeleton-row-$i')));
        final artwork = tester.getRect(find.byKey(ValueKey('skeleton-art-$i')));
        final title = tester.getRect(find.byKey(ValueKey('skeleton-title-$i')));
        final subtitle = tester.getRect(
          find.byKey(ValueKey('skeleton-subtitle-$i')),
        );
        expect(title.left, greaterThanOrEqualTo(artwork.right));
        expect(title.bottom, lessThan(subtitle.top));
        expect(title.top, greaterThanOrEqualTo(row.top));
        expect(subtitle.bottom, lessThanOrEqualTo(row.bottom));
        expect(
          (title.top + subtitle.bottom) / 2,
          closeTo(artwork.center.dy, 1),
        );
      }
    });
  }
}
