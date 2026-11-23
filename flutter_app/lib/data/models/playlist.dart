class Playlist {
  final String id;
  final String name;
  final String description;
  final int createdAtMs;
  final int updatedAtMs;
  final List<String> trackIds;

  const Playlist({
    required this.id,
    required this.name,
    this.description = '',
    required this.createdAtMs,
    required this.updatedAtMs,
    this.trackIds = const [],
  });

  Playlist copyWith({
    String? name,
    String? description,
    int? updatedAtMs,
    List<String>? trackIds,
  }) {
    return Playlist(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      createdAtMs: createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      trackIds: trackIds ?? this.trackIds,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'description': description,
        'created_at_ms': createdAtMs,
        'updated_at_ms': updatedAtMs,
      };

  factory Playlist.fromMap(Map<String, dynamic> map, {List<String> trackIds = const []}) =>
      Playlist(
        id: map['id'] as String,
        name: map['name'] as String,
        description: (map['description'] as String?) ?? '',
        createdAtMs: (map['created_at_ms'] as int?) ?? 0,
        updatedAtMs: (map['updated_at_ms'] as int?) ?? 0,
        trackIds: trackIds,
      );
}
