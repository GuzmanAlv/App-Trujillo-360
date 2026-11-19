import 'package:flutter/material.dart';

/// Centers the citizen's call and reserves a separate scroll area for evaluation.
/// Short windows (keyboard / landscape) scroll as a whole instead of overflowing.
class CallPageLayout extends StatelessWidget {
  const CallPageLayout({
    super.key,
    required this.controls,
    this.evaluation,
    this.compactControls,
  });
  final Widget controls;
  final Widget? evaluation;
  final Widget? compactControls;

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
      if (compactControls != null) {
        final compactHeight = MediaQuery.textScalerOf(context).scale(14) > 20
            ? 138.0
            : 104.0;
        final small = size.maxHeight < 400;
        return NestedScrollView(
          headerSliverBuilder: (context, scrolled) => [
            SliverPersistentHeader(
              pinned: true,
              delegate: _CallHeader(
                expanded: controls,
                compact: compactControls!,
                expandedHeight: small ? compactHeight : 340,
                compactHeight: compactHeight,
                forceCompact: small,
              ),
            ),
          ],
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 12, 24),
            child: centered(evaluation!, 720),
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

class _CallHeader extends SliverPersistentHeaderDelegate {
  _CallHeader({
    required this.expanded,
    required this.compact,
    required this.expandedHeight,
    required this.compactHeight,
    required this.forceCompact,
  });
  final Widget expanded, compact;
  final double expandedHeight, compactHeight;
  final bool forceCompact;
  @override
  double get minExtent => compactHeight;
  @override
  double get maxExtent => expandedHeight;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => ColoredBox(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: ClipRect(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              primary: false,
              child: SizedBox(
                width: double.infinity,
                child: forceCompact || shrinkOffset > 40 ? compact : expanded,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  @override
  bool shouldRebuild(covariant _CallHeader old) =>
      expanded != old.expanded ||
      compact != old.compact ||
      maxExtent != old.maxExtent ||
      minExtent != old.minExtent ||
      forceCompact != old.forceCompact;
}
