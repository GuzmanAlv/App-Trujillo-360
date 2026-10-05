import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import '../models/report_photo.dart';

Future<File> photoFile(String name) async {
  if (!RegExp(r'^[0-9a-f-]{36}\.photo$').hasMatch(name)) {
    throw const FormatException('Nombre de foto inválido');
  }
  final root = await getApplicationDocumentsDirectory();
  final directory = Directory('${root.path}/report_photos');
  await directory.create(recursive: true);
  return File('${directory.path}/$name');
}

Future<ReportPhoto> save(String id, Uint8List bytes) async {
  final photo = ReportPhoto(id: id, fileName: '$id.photo');
  final file = await photoFile(photo.fileName);
  try {
    await file.writeAsBytes(bytes, flush: true);
    return photo;
  } catch (_) {
    if (await file.exists()) await file.delete();
    rethrow;
  }
}

Future<Uint8List> read(ReportPhoto photo) async =>
    (await photoFile(photo.fileName)).readAsBytes();
Future<void> remove(ReportPhoto photo) async {
  final file = await photoFile(photo.fileName);
  if (await file.exists()) await file.delete();
}
