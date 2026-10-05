import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/report_photo.dart';
import '../services/photo_store.dart';

void openReportPhoto(BuildContext context, Uint8List bytes) {
  Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Foto del reporte'),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 5,
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Text(
                'No se pudo abrir la imagen',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class ReportPhotoView extends StatefulWidget {
  const ReportPhotoView({super.key, required this.photo});
  final ReportPhoto photo;
  @override
  State<ReportPhotoView> createState() => _ReportPhotoViewState();
}

class _ReportPhotoViewState extends State<ReportPhotoView> {
  late Future<Uint8List> bytes;
  @override
  void initState() {
    super.initState();
    bytes = PhotoStore.read(widget.photo);
  }

  @override
  void didUpdateWidget(covariant ReportPhotoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photo.fileName != widget.photo.fileName) {
      bytes = PhotoStore.read(widget.photo);
    }
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: FutureBuilder<Uint8List>(
      future: bytes,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const ColoredBox(
            color: Color(0xffe2e8f0),
            child: Center(child: Icon(Icons.broken_image_outlined)),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return Semantics(
          label: 'Ampliar foto del reporte',
          button: true,
          child: InkWell(
            onTap: () => openReportPhoto(context, snapshot.data!),
            child: Image.memory(
              snapshot.data!,
              fit: BoxFit.cover,
              cacheWidth: 500,
              errorBuilder: (_, _, _) =>
                  const Center(child: Icon(Icons.broken_image_outlined)),
            ),
          ),
        );
      },
    ),
  );
}
