import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// The same deterministic colors used by the player when cover art is absent.
List<Color> generatedArtworkColors(String path) {
  final seed = path.codeUnits.fold<int>(
    0,
    (value, char) => (value * 31 + char) & 0x7fffffff,
  );
  final hue = (seed % 360).toDouble();
  return [
    HSLColor.fromAHSL(1, hue, .55, .35).toColor(),
    HSLColor.fromAHSL(1, (hue + 75) % 360, .55, .18).toColor(),
  ];
}

/// Renders a sharable version of the player's generated cover.
Future<Uint8List> renderGeneratedArtwork(String path) async {
  const size = 512.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const rect = Rect.fromLTWH(0, 0, size, size);
  canvas.drawRect(
    rect,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: generatedArtworkColors(path),
      ).createShader(rect),
  );
  final icon = Icons.music_note_rounded;
  final text = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        fontSize: 96,
        color: Colors.white70,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  text.paint(canvas, Offset((size - text.width) / 2, (size - text.height) / 2));
  text.dispose();
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(size.toInt(), size.toInt());
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('Could not encode generated artwork');
      return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

Future<String> saveGeneratedArtwork(String path) async {
  final directory = await getTemporaryDirectory();
  // Keep concurrent renders for different tracks from overwriting each other.
  final file = File(
    '${directory.path}/generated_media_artwork_${path.hashCode}.png',
  );
  await file.writeAsBytes(await renderGeneratedArtwork(path), flush: true);
  return file.path;
}
