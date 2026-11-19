import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'report_style.dart';

/// Fixed anchor and canvas keep the location still while the warning breathes.
Future<Uint8List> renderPendingSosMarker(
  double pulse, {
  bool waitingCall = false,
  bool patrol = false,
  IconData? symbol,
  Color color = const Color(0xffcf2634),
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(2);
  const center = Offset(32, 32);
  canvas.drawCircle(
    center,
    23 + pulse * 5,
    Paint()..color = Colors.orange.withValues(alpha: .16 + pulse * .20),
  );
  canvas.drawCircle(
    center,
    24 + pulse * 5,
    Paint()
      ..color = Colors.orange.withValues(alpha: .6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2,
  );
  canvas.drawPath(
    Path()
      ..moveTo(25, 48)
      ..lineTo(32, 74)
      ..lineTo(39, 48)
      ..close(),
    Paint()..color = color,
  );
  canvas.drawCircle(center, 19 + pulse * 2, Paint()..color = Colors.white);
  canvas.drawCircle(center, 17 + pulse * 2, Paint()..color = color);
  final icon =
      (patrol ? Icons.directions_car_filled : symbol) ??
      (waitingCall ? Icons.phone_in_talk_rounded : Icons.warning_rounded);
  final text = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        fontSize: 25 + pulse * 2,
        color: Colors.white,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  text.paint(canvas, Offset(32 - text.width / 2, 32 - text.height / 2));
  text.dispose();
  if (patrol) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(24, 13, 8, 4),
        const Radius.circular(1),
      ),
      Paint()..color = Colors.white,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(32, 13, 8, 4),
        const Radius.circular(1),
      ),
      Paint()..color = const Color(0xff1d4ed8),
    );
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(128, 152);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('No se pudo dibujar SOS');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<Uint8List> renderActorMarker(IconData icon, Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(2);
  final paint = Paint()..color = color;
  canvas.drawCircle(const Offset(24, 24), 22, Paint()..color = Colors.white);
  canvas.drawCircle(const Offset(24, 24), 19, paint);
  canvas.drawPath(
    Path()
      ..moveTo(17, 42)
      ..lineTo(24, 55)
      ..lineTo(31, 42)
      ..close(),
    paint,
  );
  final text = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        fontSize: 25,
        color: Colors.white,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  text.paint(canvas, Offset(24 - text.width / 2, 24 - text.height / 2));
  text.dispose();
  final picture = recorder.endRecording();
  final image = await picture.toImage(96, 112);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('No se pudo dibujar la ubicación');
    return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

/// A label attached to the exact coordinate by its bottom tip.
/// Render at 2x for sharp text; Maps receives the logical display dimensions.
Future<Uint8List> renderReportMarker(
  String category,
  String time, {
  bool onScene = false,
}) async {
  const width = 174.0;
  const height = 82.0;
  const scale = 2.0;
  final style = ReportStyle.forCategory(category);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(scale);
  final body = RRect.fromRectAndRadius(
    const Rect.fromLTWH(5, 4, 164, 62),
    const Radius.circular(18),
  );
  final silhouette = Path()
    ..addRRect(body)
    ..moveTo(79, 65)
    ..lineTo(87, 78)
    ..lineTo(95, 65)
    ..close();
  canvas.drawShadow(silhouette, const Color(0xff172e26), 4, true);
  canvas.drawPath(silhouette, Paint()..color = Colors.white);
  canvas.drawRRect(
    body,
    Paint()
      ..color = style.color.withValues(alpha: 0.24)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2,
  );
  canvas.drawCircle(const Offset(33, 35), 18, Paint()..color = style.color);

  void text(String value, TextStyle textStyle, Offset offset, double maxWidth) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: textStyle.copyWith(fontFamily: 'Roboto'),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, offset);
    painter.dispose();
  }

  if (onScene) {
    // Beacon silhouette: dome, base and light rays, instead of the category icon.
    final paint = Paint()..color = Colors.white;
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        const Rect.fromLTWH(24, 29, 18, 16),
        topLeft: const Radius.circular(9),
        topRight: const Radius.circular(9),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(21, 45, 24, 4),
        const Radius.circular(2),
      ),
      paint,
    );
    paint.strokeWidth = 2.5;
    canvas.drawLine(const Offset(33, 20), const Offset(33, 25), paint);
    canvas.drawLine(const Offset(19, 25), const Offset(23, 28), paint);
    canvas.drawLine(const Offset(43, 28), const Offset(47, 25), paint);
  } else {
    final iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(style.icon.codePoint),
        style: TextStyle(
          fontFamily: style.icon.fontFamily,
          package: style.icon.fontPackage,
          fontSize: 23,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    iconPainter.paint(
      canvas,
      Offset(33 - iconPainter.width / 2, 35 - iconPainter.height / 2),
    );
    iconPainter.dispose();
  }
  text(
    category,
    TextStyle(color: style.color, fontWeight: FontWeight.w700, fontSize: 15),
    const Offset(59, 15),
    101,
  );
  text(
    onScene ? 'Unidad en la zona' : 'Reportado $time',
    const TextStyle(color: Color(0xff475569), fontSize: 10),
    const Offset(59, 39),
    101,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (width * scale).round(),
    (height * scale).round(),
  );
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('No se pudo dibujar el marcador');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

/// Centered location dot, independent of map zoom.
Future<Uint8List> renderLocationDot({
  Color color = const Color(0xff4285f4),
}) async {
  const size = 32.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(2);
  const center = Offset(size / 2, size / 2);
  canvas.drawCircle(center, 15, Paint()..color = color.withValues(alpha: 0.18));
  canvas.drawCircle(center, 10, Paint()..color = Colors.white);
  canvas.drawCircle(center, 7, Paint()..color = color);
  final picture = recorder.endRecording();
  final image = await picture.toImage(64, 64);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw StateError('No se pudo dibujar la ubicación');
    }
    return data.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}
