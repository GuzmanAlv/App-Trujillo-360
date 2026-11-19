import 'package:flutter/material.dart';

typedef SosDiscardDecision = ({String action, String reason});

class SosDiscardDialog extends StatefulWidget {
  const SosDiscardDialog({super.key});
  @override
  State<SosDiscardDialog> createState() => _SosDiscardDialogState();
}

class _SosDiscardDialogState extends State<SosDiscardDialog> {
  final reason = TextEditingController();
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  void choose(String action) => Navigator.pop<SosDiscardDecision>(context, (
    action: action,
    reason: reason.text.trim(),
  ));
  @override
  Widget build(BuildContext context) {
    final valid = reason.text.trim().length >= 5;
    return AlertDialog(
      title: const Text(
        'Descartar SOS',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'El caso se retirará del mapa y se cerrará su llamada. Puedes descartarlo sin bloquear la cuenta.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              minLines: 2,
              maxLines: 3,
              maxLength: 2000,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Motivo de descarte',
                helperText: 'Mínimo 5 caracteres · uso interno',
                hintText: 'Explica lo comprobado o el uso malicioso',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '«Descartar y bloquear» también suspende el acceso de la cuenta ciudadana que solicitó este SOS.',
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: Color(0xff824047),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.tonal(
          onPressed: valid ? () => choose('discard') : null,
          child: const Text('Descartar', style: TextStyle(fontSize: 12)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xffba2938),
            foregroundColor: Colors.white,
          ),
          onPressed: valid ? () => choose('discard_block') : null,
          child: const Text(
            'Descartar y bloquear',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
}
