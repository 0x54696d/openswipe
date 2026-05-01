import 'package:flutter/material.dart';
import 'package:openswipe/widgets/swipe_card.dart';
import 'package:photo_manager/photo_manager.dart';

class CardStack extends StatelessWidget {
  final AssetEntity current;
  final AssetEntity? next;
  final void Function(bool isKeep) onSwiped;
  final GlobalKey<CardStackState> stackKey;

  const CardStack({
    required this.current,
    required this.next,
    required this.onSwiped,
    required this.stackKey,
    super.key,
  });

  Future<void> triggerSwipe(bool isKeep) async {
    await stackKey.currentState?.triggerSwipe(isKeep);
  }

  @override
  Widget build(BuildContext context) {
    return CardStackInner(
      key: stackKey,
      current: current,
      next: next,
      onSwiped: onSwiped,
    );
  }
}

class CardStackState extends State<CardStackInner> {
  final GlobalKey<SwipeCardState> _cardKey = GlobalKey();
  double _incomingStartScale = 0.93;

  Future<void> triggerSwipe(bool isKeep) async {
    await _cardKey.currentState?.triggerSwipe(isKeep);
  }

  Size _cardSize(AssetEntity asset, BuildContext context) {
    final s = MediaQuery.of(context).size;
    final maxW = s.width - 32;
    final maxH = s.height * 0.65;
    final aw = asset.width.toDouble();
    final ah = asset.height.toDouble();
    final ar = (aw > 0 && ah > 0) ? aw / ah : 1.0;
    if (ar > maxW / maxH) {
      return Size(maxW, maxW / ar);
    } else {
      return Size(maxH * ar, maxH);
    }
  }

  @override
  void didUpdateWidget(covariant CardStackInner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.current.id != widget.current.id) {
      final oldForegroundSize = _cardSize(oldWidget.current, context);
      final newForegroundSize = _cardSize(widget.current, context);

      final previewCap = (
        oldForegroundSize.width / newForegroundSize.width,
        oldForegroundSize.height / newForegroundSize.height,
      );
      final previewScale = previewCap.$1 < previewCap.$2
          ? previewCap.$1
          : previewCap.$2;

      // Match the previous background preview, which is additionally scaled.
      _incomingStartScale = (previewScale * 0.93).clamp(0.78, 1.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fgSize = _cardSize(widget.current, context);

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final scale = Tween<double>(begin: 0.97, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            );
            return FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: scale, child: child),
            );
          },
          // Shift the background card up by half the meta strip height so it
          // centres against the image portion of the foreground column.
          child: widget.next == null
              ? const SizedBox(key: ValueKey('no_next'))
              : Padding(
                  padding: const EdgeInsets.only(bottom: 42),
                  child: SwipeCard(
                    key: ValueKey('bg_${widget.next!.id}'),
                    asset: widget.next!,
                    isBackground: true,
                    maxCardSize: fgSize,
                  ),
                ),
        ),
        TweenAnimationBuilder<double>(
          key: ValueKey('fg_transition_${widget.current.id}'),
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            final scale =
                _incomingStartScale + (1 - _incomingStartScale) * value;
            return IgnorePointer(
              ignoring: value < 0.95,
              child: Transform.scale(scale: scale, child: child),
            );
          },
          child: SwipeCard(
            key: _cardKey,
            asset: widget.current,
            onSwiped: widget.onSwiped,
          ),
        ),
      ],
    );
  }
}

class CardStackInner extends StatefulWidget {
  final AssetEntity current;
  final AssetEntity? next;
  final void Function(bool isKeep) onSwiped;

  const CardStackInner({
    required this.current,
    required this.next,
    required this.onSwiped,
    super.key,
  });

  @override
  CardStackState createState() => CardStackState();
}
