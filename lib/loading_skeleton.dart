import 'package:flutter/material.dart';

class LoadingSkeleton extends StatefulWidget {
  const LoadingSkeleton({super.key, this.width = 48, this.height = 48});
  final double width;
  final double height;
  @override
  State<LoadingSkeleton> createState() => _LoadingSkeletonState();
}

class _LoadingSkeletonState extends State<LoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween<double>(begin: .35, end: .8).animate(controller),
    child: Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(8),
      ),
    ),
  );
}

/// Placeholder rows for a music list while its contents are loading.
class LibraryLoadingSkeleton extends StatefulWidget {
  const LibraryLoadingSkeleton({super.key});

  @override
  State<LibraryLoadingSkeleton> createState() => _LibraryLoadingSkeletonState();
}

class _LibraryLoadingSkeletonState extends State<LibraryLoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface
        .withValues(alpha: .18);
    Widget block(double width, double height, {Key? key}) => Container(
      key: key,
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) => FadeTransition(
        key: const Key('libraryLoadingSkeleton'),
        opacity: Tween<double>(begin: .35, end: .8).animate(controller),
        child: ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          itemExtent: 72,
          itemCount: (constraints.maxHeight / 72).ceil().clamp(1, 100),
          itemBuilder: (context, index) => Padding(
            key: ValueKey('skeleton-row-$index'),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                block(48, 48, key: ValueKey('skeleton-art-$index')),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FractionallySizedBox(
                        widthFactor: .65,
                        child: block(
                          double.infinity,
                          12,
                          key: ValueKey('skeleton-title-$index'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      FractionallySizedBox(
                        widthFactor: .42,
                        child: block(
                          double.infinity,
                          10,
                          key: ValueKey('skeleton-subtitle-$index'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
