import 'package:flutter/cupertino.dart';

class SkeletonTile extends StatefulWidget {
  final int index;
  final bool isLast;

  const SkeletonTile({super.key, required this.index, required this.isLast});

  @override
  State<SkeletonTile> createState() => _SkeletonTileState();
}

class _SkeletonTileState extends State<SkeletonTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _shimmer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _shimmer = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );

    // Stagger the shimmer start so tiles don't all pulse in sync
    Future.delayed(Duration(milliseconds: widget.index * 80), () {
      if (mounted) _ctrl.repeat();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shimmer,
      builder: (context, _) {
        return Container(
          color: CupertinoColors.systemBackground,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _bone(width: 48, height: 16, radius: 5),
                              const SizedBox(width: 8),
                              _bone(width: 72, height: 12, radius: 4),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _bone(width: double.infinity, height: 14, radius: 4),
                          const SizedBox(height: 5),
                          _bone(width: 220, height: 14, radius: 4),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _bone(width: 80, height: 18, radius: 5),
                              const SizedBox(width: 6),
                              _bone(width: 100, height: 18, radius: 5),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _bone(width: 56, height: 16, radius: 4),
                  ],
                ),
              ),
              if (!widget.isLast)
                Container(
                  height: 0.5,
                  margin: const EdgeInsets.only(left: 16),
                  color: CupertinoColors.separator,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _bone({required double width, required double height, required double radius}) {
    return Container(
      width: width == double.infinity ? null : width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: const Alignment(-1, 0),
          end: const Alignment(1, 0),
          colors: const [
            Color(0xFFE5E5EA),
            Color(0xFFF2F2F7),
            Color(0xFFE5E5EA),
          ],
          stops: [
            (_shimmer.value - 0.6).clamp(0.0, 1.0),
            _shimmer.value.clamp(0.0, 1.0),
            (_shimmer.value + 0.6).clamp(0.0, 1.0),
          ],
        ),
      ),
    );
  }
}
