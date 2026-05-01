import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';

/// Small LRU-style cache so background cards share their loaded image
/// with the foreground card that follows, eliminating the reload flash.
class _CardImageCache {
  static const int _maxSize = 6;
  static final Map<String, MemoryImage> _store = {};

  static MemoryImage? get(String id) => _store[id];

  static void put(String id, MemoryImage image) {
    if (_store.containsKey(id)) return;
    if (_store.length >= _maxSize) _store.remove(_store.keys.first);
    _store[id] = image;
  }
}

class _AssetSizeCache {
  static const int _maxSize = 24;
  static final Map<String, String> _store = {};

  static String? get(String id) => _store[id];

  static void put(String id, String value) {
    if (_store.containsKey(id)) return;
    if (_store.length >= _maxSize) {
      _store.remove(_store.keys.first);
    }
    _store[id] = value;
  }
}

class SwipeCard extends StatefulWidget {
  final AssetEntity asset;
  final bool isBackground;
  final void Function(bool isKeep)? onSwiped;

  /// When set, the card will not render larger than this size (aspect-ratio preserved).
  final Size? maxCardSize;

  const SwipeCard({
    required this.asset,
    this.isBackground = false,
    this.onSwiped,
    this.maxCardSize,
    super.key,
  });

  @override
  SwipeCardState createState() => SwipeCardState();
}

class SwipeCardState extends State<SwipeCard> {
  Offset _dragOffset = Offset.zero;
  bool _isFlying = false;
  bool _isDragging = false;
  bool _animateSnapBack = false;
  bool _didHitCommitThreshold = false;
  MemoryImage? _image;
  int _imageLoadToken = 0;
  String? _assetSizeLabel;

  static const double _commitThreshold = 120.0;

  double get _swipeProgress =>
      (_dragOffset.dx / _commitThreshold).clamp(-1.0, 1.0);

  bool get _isKeep => _swipeProgress > 0;

  @override
  void initState() {
    super.initState();
    _image = _CardImageCache.get(widget.asset.id);
    _assetSizeLabel = _AssetSizeCache.get(widget.asset.id);
    if (_image == null) _loadImage();
    if (_assetSizeLabel == null) _loadAssetSize();
  }

  @override
  void didUpdateWidget(covariant SwipeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset.id != widget.asset.id) {
      _dragOffset = Offset.zero;
      _isFlying = false;
      _isDragging = false;
      _animateSnapBack = false;
      _didHitCommitThreshold = false;
      _assetSizeLabel = _AssetSizeCache.get(widget.asset.id);
      final cached = _CardImageCache.get(widget.asset.id);
      if (cached != null) {
        _image = cached;
      } else {
        _image = null;
        _loadImage();
      }
      if (_assetSizeLabel == null) {
        _loadAssetSize();
      }
    }
  }

  Future<void> _loadImage() async {
    final loadToken = ++_imageLoadToken;
    final data = await widget.asset.thumbnailDataWithSize(
      const ThumbnailSize(1080, 1080),
      quality: 95,
    );
    if (data == null || !mounted || loadToken != _imageLoadToken) return;
    final image = MemoryImage(data);
    _CardImageCache.put(widget.asset.id, image);
    setState(() => _image = image);
  }

  Future<void> _loadAssetSize() async {
    String label = '--';
    try {
      final local = await widget.asset.isLocallyAvailable(isOrigin: true);
      if (!local) {
        label = 'iCloud';
      } else {
        final file = await widget.asset.originFile;
        if (file != null && file.path.isNotEmpty) {
          final bytes = await file.length();
          const bytesPerMb = 1024 * 1024;
          if (bytes >= bytesPerMb) {
            label = '${(bytes / bytesPerMb).toStringAsFixed(1)} MB';
          } else {
            label = '${(bytes / 1024).toStringAsFixed(0)} KB';
          }
        }
      }
    } catch (_) {
      // iCloud-backed or inaccessible assets can throw platform exceptions.
      label = 'iCloud';
    }

    _AssetSizeCache.put(widget.asset.id, label);
    if (!mounted) return;
    setState(() => _assetSizeLabel = label);
  }

  void _onDragStart(DragStartDetails _) {
    if (widget.isBackground || _isFlying) return;
    if (!_isDragging || _animateSnapBack) {
      setState(() {
        _isDragging = true;
        _animateSnapBack = false;
      });
    }
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (widget.isBackground || _isFlying) return;
    final previousDx = _dragOffset.dx;
    final nextDx = previousDx + details.delta.dx;
    if (!_didHitCommitThreshold &&
        previousDx.abs() < _commitThreshold &&
        nextDx.abs() >= _commitThreshold) {
      _didHitCommitThreshold = true;
      HapticFeedback.mediumImpact();
    }
    setState(() {
      _animateSnapBack = false;
      _dragOffset += details.delta;
    });
  }

  void _onDragEnd(DragEndDetails _) {
    if (widget.isBackground || _isFlying) return;
    _isDragging = false;
    _didHitCommitThreshold = false;
    if (_dragOffset.dx.abs() >= _commitThreshold) {
      _animateSnapBack = false;
      _flyOff(_dragOffset.dx > 0);
    } else {
      setState(() {
        _animateSnapBack = true;
        _dragOffset = Offset.zero;
      });
    }
  }

  Future<void> _flyOff(bool isKeep) async {
    if (_isFlying) return;
    setState(() => _isFlying = true);

    final screenWidth = MediaQuery.of(context).size.width;
    final targetX = isKeep ? screenWidth * 1.5 : -screenWidth * 1.5;

    while (mounted && (_dragOffset.dx - targetX).abs() > 8) {
      await Future.delayed(const Duration(milliseconds: 16));
      if (!mounted) return;
      setState(() {
        _dragOffset = Offset(
          _dragOffset.dx + (targetX - _dragOffset.dx) * 0.25,
          _dragOffset.dy,
        );
      });
    }

    widget.onSwiped?.call(isKeep);
  }

  Future<void> triggerSwipe(bool isKeep) async {
    if (_isFlying) return;
    setState(() => _dragOffset = Offset(isKeep ? 20 : -20, 0));
    await Future.delayed(const Duration(milliseconds: 50));
    if (mounted) await _flyOff(isKeep);
  }

  @override
  Widget build(BuildContext context) {
    final availableSize = MediaQuery.of(context).size;
    final maxWidth = availableSize.width - 32; // horizontal padding
    final maxHeight = availableSize.height * 0.65;

    // Use asset dimensions to compute card size that preserves aspect ratio
    final assetWidth = widget.asset.width.toDouble();
    final assetHeight = widget.asset.height.toDouble();
    final aspectRatio = (assetWidth > 0 && assetHeight > 0)
        ? assetWidth / assetHeight
        : 1.0;

    double cardWidth, cardHeight;
    if (aspectRatio > maxWidth / maxHeight) {
      // Landscape — constrain by width
      cardWidth = maxWidth;
      cardHeight = maxWidth / aspectRatio;
    } else {
      // Portrait — constrain by height
      cardHeight = maxHeight;
      cardWidth = maxHeight * aspectRatio;
    }

    // Cap background card so it never protrudes beyond the foreground card.
    final constraint = widget.maxCardSize;
    if (constraint != null) {
      final scaleW = constraint.width / cardWidth;
      final scaleH = constraint.height / cardHeight;
      final cap = min(scaleW, scaleH);
      if (cap < 1.0) {
        cardWidth *= cap;
        cardHeight *= cap;
      }
    }

    final progress = _swipeProgress.abs();
    const outerRadius = 20.0;
    const borderWidth = 4.0;
    final stampColor = _isKeep
        ? const Color(0xFF34C759)
        : const Color(0xFFFF3B30);
    const fadeStart = 0.58;
    final accentOpacity = ((progress - fadeStart) / (1.0 - fadeStart)).clamp(
      0.0,
      1.0,
    );

    Widget card = Container(
      width: cardWidth,
      height: cardHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(outerRadius),
        boxShadow: const [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 40,
            spreadRadius: 2,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(outerRadius),
        child: Stack(
          children: [
            // Dark base
            Positioned.fill(child: Container(color: Colors.black)),

            // Sharp image
            if (_image != null)
              Positioned.fill(
                child: Image(image: _image!, fit: BoxFit.cover),
              ),

            // Border overlay rendered on top of the image.
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(outerRadius),
                    border: Border.all(
                      color: progress > fadeStart
                          ? stampColor.withOpacity(accentOpacity)
                          : Colors.transparent,
                      width: borderWidth,
                    ),
                  ),
                ),
              ),
            ),

            // Corner pill badge — App Store style
            if (progress > fadeStart)
              Positioned(
                top: 0,
                left: _isKeep ? 0 : null,
                right: _isKeep ? null : 0,
                child: Opacity(
                  opacity: accentOpacity,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: stampColor,
                      borderRadius: BorderRadius.only(
                        topLeft: _isKeep
                            ? const Radius.circular(outerRadius)
                            : Radius.zero,
                        topRight: _isKeep
                            ? Radius.zero
                            : const Radius.circular(outerRadius),
                        bottomLeft: _isKeep
                            ? Radius.zero
                            : const Radius.circular(outerRadius),
                        bottomRight: _isKeep
                            ? const Radius.circular(outerRadius)
                            : Radius.zero,
                      ),
                    ),
                    child: Text(
                      _isKeep ? 'KEEP' : 'DELETE',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (widget.isBackground) {
      return Transform.scale(scale: 0.93, child: card);
    }

    final metaStrip = _buildMetaStrip(cardWidth);

    return GestureDetector(
      onPanStart: _onDragStart,
      onPanUpdate: _onDragUpdate,
      onPanEnd: _onDragEnd,
      child: AnimatedContainer(
        duration: _animateSnapBack
            ? const Duration(milliseconds: 320)
            : Duration.zero,
        curve: Curves.easeOutBack,
        transform: Matrix4.identity()
          ..translate(_dragOffset.dx, _dragOffset.dy)
          ..rotateZ(_dragOffset.dx / 800),
        transformAlignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [card, const SizedBox(height: 10), metaStrip],
        ),
      ),
    );
  }

  Widget _buildMetaStrip(double width) {
    final ts = widget.asset.createDateSecond;
    final date = ts != null
        ? _formatDate(DateTime.fromMillisecondsSinceEpoch(ts * 1000))
        : '';
    final resolution = widget.asset.width > 0
        ? '${widget.asset.width} × ${widget.asset.height}'
        : '';
    final fileType = _resolveFileType();
    final assetSize = _assetSizeLabel ?? '';

    return SizedBox(
      width: width,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                date,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  letterSpacing: -0.1,
                ),
              ),
              Text(
                resolution,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                fileType,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  letterSpacing: -0.1,
                ),
              ),
              Text(
                assetSize,
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _resolveFileType() {
    final mime = widget.asset.mimeType;
    if (mime != null && mime.contains('/')) {
      final subtype = mime.split('/').last.trim();
      if (subtype.isNotEmpty) return subtype.toUpperCase();
    }
    return 'IMAGE';
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}
