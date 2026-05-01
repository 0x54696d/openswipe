import 'dart:ui';
import 'package:animated_digit/animated_digit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openswipe/controllers/review_controller.dart';
import 'package:openswipe/widgets/card_stack.dart';
import 'package:photo_manager/photo_manager.dart';

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  ReviewController? _controller;
  final GlobalKey<CardStackState> _stackKey = GlobalKey();
  bool _loading = true;
  MemoryImage? _bgImage;
  String? _bgAssetId;
  int _bgLoadToken = 0;
  int _savedBytes = 0;
  final Map<String, int> _assetBytesCache = {};

  @override
  void initState() {
    super.initState();
    _loadAssets();
  }

  Future<void> _loadAssets() async {
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
    );

    if (albums.isEmpty) {
      setState(() => _loading = false);
      return;
    }

    final assets = await albums.first.getAssetListRange(start: 0, end: 500);

    setState(() {
      _controller = ReviewController(assets);
      _loading = false;
    });

    if (assets.isNotEmpty) {
      _loadBgImage(assets.first);
    }
  }

  Future<void> _loadBgImage(AssetEntity asset) async {
    final loadToken = ++_bgLoadToken;
    final data = await asset.thumbnailDataWithSize(
      const ThumbnailSize(512, 512),
      quality: 80,
    );
    if (data == null || !mounted || loadToken != _bgLoadToken) return;
    setState(() {
      _bgImage = MemoryImage(data);
      _bgAssetId = asset.id;
    });
  }

  void _onSwiped(bool isKeep) {
    final swipedAsset = _controller?.current;
    if (!isKeep && swipedAsset != null) {
      _accumulateSavedBytes(swipedAsset);
    }

    _controller?.decide(isKeep ? SwipeAction.keep : SwipeAction.delete);
    setState(() {});

    // Preload next background image
    final next = _controller?.current;
    if (next != null) _loadBgImage(next);
  }

  Future<void> _accumulateSavedBytes(AssetEntity asset) async {
    final bytes = await _getAssetBytes(asset);
    if (bytes == null) return;

    if (!mounted) return;
    setState(() => _savedBytes += bytes);
  }

  Future<int?> _getAssetBytes(AssetEntity asset) async {
    final cached = _assetBytesCache[asset.id];
    if (cached != null) return cached;

    try {
      final local = await asset.isLocallyAvailable(isOrigin: true);
      if (!local) return null;

      final file = await asset.originFile;
      if (file == null || file.path.isEmpty) return null;
      final bytes = await file.length();
      _assetBytesCache[asset.id] = bytes;
      return bytes;
    } catch (_) {
      // iCloud-backed or inaccessible assets can throw platform exceptions.
      return null;
    }
  }

  Future<void> _onUndo() async {
    final controller = _controller;
    if (controller == null) return;

    final undone = controller.undo();
    if (undone == null) return;

    final action = undone.$2;
    if (action == SwipeAction.delete) {
      final bytes = await _getAssetBytes(undone.$1);
      if (bytes != null && mounted) {
        setState(() => _savedBytes = (_savedBytes - bytes).clamp(0, 1 << 62));
      }
    }

    final current = controller.current;
    if (current != null) {
      _loadBgImage(current);
    }
    if (mounted) setState(() {});
  }

  Future<void> _onRedo() async {
    final controller = _controller;
    if (controller == null) return;

    final redone = controller.redo();
    if (redone == null) return;

    if (redone.$2 == SwipeAction.delete) {
      final bytes = await _getAssetBytes(redone.$1);
      if (bytes != null && mounted) {
        setState(() => _savedBytes += bytes);
      }
    }

    if (!mounted) return;
    final current = controller.current;
    if (current != null) {
      _loadBgImage(current);
    }
    setState(() {});
  }

  (num value, String unit, int fractionDigits) _savedDisplayData(int bytes) {
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;

    if (bytes >= gb) {
      return (bytes / gb, 'GB', 2);
    }
    if (bytes >= mb) {
      return (bytes / mb, 'MB', 1);
    }
    if (bytes >= kb) {
      return (bytes / kb, 'KB', 0);
    }
    return (bytes, 'B', 0);
  }

  String _savedDisplayLabel() {
    final data = _savedDisplayData(_savedBytes);
    return '${data.$1.toStringAsFixed(data.$3)} ${data.$2}';
  }

  void _onTopClose() {
    Navigator.of(context).maybePop();
  }

  void _onTopNext() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _NextReviewScreen(savedLabel: _savedDisplayLabel()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final controller = _controller;

    if (controller == null || controller.isDone) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'All done.',
            style: TextStyle(color: Colors.white, fontSize: 24),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Full screen blurred ambient background
          if (_bgImage != null)
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 950),
                reverseDuration: const Duration(milliseconds: 700),
                switchInCurve: Curves.easeInOutCubicEmphasized,
                switchOutCurve: Curves.easeInOutCubic,
                transitionBuilder: (child, animation) {
                  final scale = Tween<double>(begin: 1.03, end: 1.0).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeInOutCubic,
                    ),
                  );
                  return FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(scale: scale, child: child),
                  );
                },
                child: ImageFiltered(
                  key: ValueKey(_bgAssetId ?? 'ambient_empty'),
                  imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
                  child: Image(
                    image: _bgImage!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ),

          if (_bgImage != null)
            // Dark veil to keep foreground controls prominent.
            Container(color: Colors.black.withOpacity(0.42)),

          // Foreground UI
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _TopIconButton(
                            icon: LucideIcons.x,
                            onTap: _onTopClose,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 15),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(999),
                                    child: LinearProgressIndicator(
                                      value:
                                          controller.currentIndex /
                                          controller.total,
                                      minHeight: 6,
                                      backgroundColor: Colors.white12,
                                      valueColor: const AlwaysStoppedAnimation(
                                        Colors.white30,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${controller.currentIndex + 1} of ${controller.total}',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          _TopIconButton(
                            icon: LucideIcons.check,
                            onTap: _onTopNext,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Card stack
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: CardStack(
                      stackKey: _stackKey,
                      current: controller.current!,
                      next: controller.next,
                      onSwiped: _onSwiped,
                    ),
                  ),
                ),

                // Buttons
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 24,
                    horizontal: 16,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ActionButton(
                        icon: LucideIcons.undo,
                        color: Colors.white70,
                        size: 42,
                        iconSize: 18,
                        onTap: controller.canUndo ? _onUndo : null,
                      ),
                      const SizedBox(width: 10),
                      _ActionButton(
                        icon: LucideIcons.x,
                        color: Colors.red,
                        onTap: () =>
                            _stackKey.currentState?.triggerSwipe(false),
                      ),
                      const SizedBox(width: 10),
                      _SavedSpacePill(data: _savedDisplayData(_savedBytes)),
                      const SizedBox(width: 10),
                      _ActionButton(
                        icon: LucideIcons.check,
                        color: Colors.green,
                        onTap: () => _stackKey.currentState?.triggerSwipe(true),
                      ),
                      const SizedBox(width: 10),
                      _ActionButton(
                        icon: LucideIcons.redo,
                        color: Colors.white70,
                        size: 42,
                        iconSize: 18,
                        onTap: controller.canRedo ? _onRedo : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedSpacePill extends StatelessWidget {
  final (num value, String unit, int fractionDigits) data;

  const _SavedSpacePill({required this.data});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.14),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white24, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.archive, size: 16, color: Colors.white70),
              const SizedBox(width: 8),
              AnimatedDigitWidget(
                value: data.$1,
                fractionDigits: data.$3,
                textStyle: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                data.$2,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.size = 62,
    this.iconSize = 26,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!mounted || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap == null
          ? null
          : () {
              HapticFeedback.lightImpact();
              widget.onTap?.call();
            },
      onTapDown: widget.onTap == null ? null : (_) => _setPressed(true),
      onTapUp: widget.onTap == null ? null : (_) => _setPressed(false),
      onTapCancel: widget.onTap == null ? null : () => _setPressed(false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        scale: _pressed ? 0.9 : 1,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.onTap == null
                      ? Colors.white.withOpacity(0.06)
                      : Colors.white.withOpacity(0.14),
                ),
                child: Icon(
                  widget.icon,
                  color: widget.onTap == null ? Colors.white24 : widget.color,
                  size: widget.iconSize,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _TopIconButton({required this.icon, required this.onTap});

  @override
  State<_TopIconButton> createState() => _TopIconButtonState();
}

class _TopIconButtonState extends State<_TopIconButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!mounted || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        scale: _pressed ? 0.9 : 1,
        child: SizedBox(
          width: 36,
          height: 36,
          child: ClipOval(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 110),
              curve: Curves.easeOutCubic,
              color: _pressed
                  ? Colors.white.withOpacity(0.16)
                  : Colors.transparent,
              child: Icon(widget.icon, color: Colors.white70, size: 20),
            ),
          ),
        ),
      ),
    );
  }
}

class _NextReviewScreen extends StatelessWidget {
  final String savedLabel;

  const _NextReviewScreen({required this.savedLabel});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  LucideIcons.sparkles,
                  color: Colors.white70,
                  size: 42,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Next Screen',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Saved so far: $savedLabel',
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Back'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
