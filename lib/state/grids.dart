import 'dart:ui';

/// Multi-view layouts. Tiles are rectangles in grid units on a [cols] ×
/// [rows] canvas, laid out in reading order (slot 1 first).
enum GridLayout {
  two('2 side by side', 2, 2, [
    Rect.fromLTWH(0, 0.5, 1, 1),
    Rect.fromLTWH(1, 0.5, 1, 1),
  ]),
  quad('2 × 2', 2, 2, [
    Rect.fromLTWH(0, 0, 1, 1),
    Rect.fromLTWH(1, 0, 1, 1),
    Rect.fromLTWH(0, 1, 1, 1),
    Rect.fromLTWH(1, 1, 1, 1),
  ]),
  onePlusFive('1 + 5', 3, 3, [
    Rect.fromLTWH(0, 0, 2, 2),
    Rect.fromLTWH(2, 0, 1, 1),
    Rect.fromLTWH(2, 1, 1, 1),
    Rect.fromLTWH(0, 2, 1, 1),
    Rect.fromLTWH(1, 2, 1, 1),
    Rect.fromLTWH(2, 2, 1, 1),
  ]),
  nine('3 × 3', 3, 3, [
    Rect.fromLTWH(0, 0, 1, 1),
    Rect.fromLTWH(1, 0, 1, 1),
    Rect.fromLTWH(2, 0, 1, 1),
    Rect.fromLTWH(0, 1, 1, 1),
    Rect.fromLTWH(1, 1, 1, 1),
    Rect.fromLTWH(2, 1, 1, 1),
    Rect.fromLTWH(0, 2, 1, 1),
    Rect.fromLTWH(1, 2, 1, 1),
    Rect.fromLTWH(2, 2, 1, 1),
  ]);

  const GridLayout(this.label, this.cols, this.rows, this.tiles);
  final String label;
  final int cols;
  final int rows;
  final List<Rect> tiles;

  int get slots => tiles.length;

  /// Smallest layout that fits [count] cameras (up to nine).
  static GridLayout fitting(int count) => count <= 2
      ? GridLayout.two
      : count <= 4
          ? GridLayout.quad
          : count <= 6
              ? GridLayout.onePlusFive
              : GridLayout.nine;

  static GridLayout byName(String? name) =>
      GridLayout.values.firstWhere((l) => l.name == name, orElse: () => GridLayout.quad);
}

/// A saved multi-view: a layout and the camera (device id) in each slot.
class GridPreset {
  GridPreset({required this.id, required this.name, required this.layout, required List<String?> slots})
      : slots = List<String?>.generate(layout.slots, (i) => i < slots.length ? slots[i] : null);

  /// Id of the built-in grid that always shows every camera.
  static const allCamerasId = 'all';

  final String id;
  final String name;
  final GridLayout layout;
  final List<String?> slots;

  bool get isAuto => id == allCamerasId;
  int get cameraCount => slots.where((s) => s != null).length;

  GridPreset copyWith({String? name, GridLayout? layout, List<String?>? slots}) => GridPreset(
        id: id,
        name: name ?? this.name,
        layout: layout ?? this.layout,
        slots: slots ?? this.slots,
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'layout': layout.name, 'slots': slots};

  static GridPreset fromJson(Map<String, dynamic> json) => GridPreset(
        id: '${json['id']}',
        name: '${json['name'] ?? 'Grid'}',
        layout: GridLayout.byName(json['layout'] as String?),
        slots: [for (final s in (json['slots'] as List? ?? const [])) s?.toString()],
      );
}
