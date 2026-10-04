import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'report_style.dart';

/// A label attached to the exact coordinate by its bottom tip.
/// Render at 2x for sharp text; Maps receives the logical display dimensions.
Future<Uint8List> renderReportMarker(String category, String time) async {
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
  text(
    category,
    TextStyle(color: style.color, fontWeight: FontWeight.w700, fontSize: 15),
    const Offset(59, 15),
    101,
  );
  text(
    'Reportado $time',
    const TextStyle(color: Color(0xff475569), fontSize: 11),
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
