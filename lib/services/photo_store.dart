import 'dart:typed_data';
import '../models/report_photo.dart';
import 'photo_store_stub.dart'
    if (dart.library.io) 'photo_store_io.dart'
    as storage;

/// Keep photo bytes on disk rather than embedding them in SharedPreferences.
class PhotoStore {
  static const maxPhotos = 3;
  static const maxBytes = 2 * 1024 * 1024;
  static Future<ReportPhoto> save(String id, Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException('Cada foto debe pesar como máximo 2 MB.');
    }
    return storage.save(id, bytes);
  }

  static Future<Uint8List> read(ReportPhoto photo) => storage.read(photo);
  static Future<void> remove(ReportPhoto photo) => storage.remove(photo);
}
