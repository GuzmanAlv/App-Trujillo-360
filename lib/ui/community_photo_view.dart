import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/community_photos_client.dart';

class CommunityPhotoView extends StatefulWidget {
  const CommunityPhotoView({
    super.key,
    required this.incidentId,
    required this.photoId,
    this.fetch,
  });
  final String incidentId, photoId;
  final Future<Uint8List> Function(String, String)? fetch;
  @override
  State<CommunityPhotoView> createState() => _CommunityPhotoViewState();
}

class _CommunityPhotoViewState extends State<CommunityPhotoView> {
  late Future<Uint8List> image = load();
  Future<Uint8List> load() =>
      (widget.fetch ?? fetchCommunityPhoto)(widget.incidentId, widget.photoId);
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 130,
    height: 110,
    child: FutureBuilder<Uint8List>(
      future: image,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return TextButton(
            onPressed: () {
              final next = load();
              setState(() {
                image = next;
              });
            },
            child: const Text('Reintentar foto'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: InkWell(
            onTap: () => showDialog<void>(
              context: context,
              builder: (context) => Dialog(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: InteractiveViewer(
                        child: Image.memory(
                          snapshot.data!,
                          errorBuilder: (_, _, _) =>
                              const Text('Foto no disponible'),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cerrar'),
                    ),
                  ],
                ),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                snapshot.data!,
                fit: BoxFit.cover,
                cacheWidth: 260,
                errorBuilder: (_, _, _) =>
                    const Center(child: Text('Foto no disponible')),
              ),
            ),
          ),
        );
      },
    ),
  );
}
