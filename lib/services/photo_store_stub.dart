import 'dart:typed_data';
import '../models/report_photo.dart';

Future<ReportPhoto> save(String id, Uint8List bytes) async =>
    throw UnsupportedError('Fotos disponibles en la app Android.');
Future<Uint8List> read(ReportPhoto photo) async =>
    throw UnsupportedError('Fotos disponibles en la app Android.');
Future<void> remove(ReportPhoto photo) async {}
