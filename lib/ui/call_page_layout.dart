import 'package:flutter/material.dart';

/// Centers the citizen's call and reserves a separate scroll area for evaluation.
/// Short windows (keyboard / landscape) scroll as a whole instead of overflowing.
class CallPageLayout extends StatelessWidget {
  const CallPageLayout({super.key, required this.controls, this.evaluation});
  final Widget controls;
  final Widget? evaluation;

  Widget centered(Widget child, double width) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: SizedBox(width: double.infinity, child: child),
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      if (evaluation == null) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: size.maxHeight),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: centered(controls, 460),
            ),
          ),
        );
      }
      if (size.maxHeight < 540 ||
          MediaQuery.textScalerOf(context).scale(16) > 22) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: centered(Column(children: [controls, evaluation!]), 720),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: size.maxHeight * .48),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: centered(controls, 460),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: centered(evaluation!, 720),
            ),
          ),
        ],
      );
    },
  );
}
