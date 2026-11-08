import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:musicgram/generated_artwork.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'generated cover is a 512 pixel PNG using stable track colors',
    () async {
      final first = generatedArtworkColors('/one.mp3');
      expect(generatedArtworkColors('/one.mp3'), first);
      expect(generatedArtworkColors('/another.mp3'), isNot(first));
      final bytes = await renderGeneratedArtwork('/one.mp3');
      expect(bytes.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 512);
      expect(frame.image.height, 512);
      frame.image.dispose();
      codec.dispose();
    },
  );
}
