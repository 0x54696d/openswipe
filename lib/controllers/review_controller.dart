import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

enum SwipeAction { keep, delete }

class ReviewController extends ChangeNotifier {
  final List<AssetEntity> _assets;
  int _currentIndex = 0;
  final List<(AssetEntity, SwipeAction)> _decisions = [];
  final List<(AssetEntity, SwipeAction)> _redoStack = [];

  ReviewController(this._assets);

  AssetEntity? get current =>
      _currentIndex < _assets.length ? _assets[_currentIndex] : null;

  AssetEntity? get next =>
      _currentIndex + 1 < _assets.length ? _assets[_currentIndex + 1] : null;

  int get currentIndex => _currentIndex;
  int get total => _assets.length;
  bool get isDone => _currentIndex >= _assets.length;
  bool get canUndo => _decisions.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  List<(AssetEntity, SwipeAction)> get decisions =>
      List.unmodifiable(_decisions);

  void decide(SwipeAction action) {
    if (current == null) return;
    _decisions.add((_assets[_currentIndex], action));
    _redoStack.clear();
    _currentIndex++;
    notifyListeners();
  }

  (AssetEntity, SwipeAction)? undo() {
    if (_decisions.isEmpty) return null;
    final last = _decisions.removeLast();
    _redoStack.add(last);
    _currentIndex = (_currentIndex - 1).clamp(0, _assets.length);
    notifyListeners();
    return last;
  }

  (AssetEntity, SwipeAction)? redo() {
    if (_redoStack.isEmpty || _currentIndex >= _assets.length) return null;
    final restored = _redoStack.removeLast();
    _decisions.add(restored);
    _currentIndex = (_currentIndex + 1).clamp(0, _assets.length);
    notifyListeners();
    return restored;
  }
}
