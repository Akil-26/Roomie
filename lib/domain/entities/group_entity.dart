/// Group Entity
/// Represents a group in the domain layer
class GroupEntity {
  final String id;
  final String name;
  final String description;
  final String location;
  final String creatorId;
  final List<String> members;
  final int maxMembers;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? imageUrl;
  final bool isActive;

  const GroupEntity({
    required this.id,
    required this.name,
    required this.description,
    required this.location,
    required this.creatorId,
    required this.members,
    required this.maxMembers,
    required this.createdAt,
    required this.updatedAt,
    this.imageUrl,
    this.isActive = true,
  });

  GroupEntity copyWith({
    String? id,
    String? name,
    String? description,
    String? location,
    String? creatorId,
    List<String>? members,
    int? maxMembers,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? imageUrl,
    bool? isActive,
  }) {
    return GroupEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      location: location ?? this.location,
      creatorId: creatorId ?? this.creatorId,
      members: members ?? this.members,
      maxMembers: maxMembers ?? this.maxMembers,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      imageUrl: imageUrl ?? this.imageUrl,
      isActive: isActive ?? this.isActive,
    );
  }

  bool get isFull => members.length >= maxMembers;
  bool get hasMembers => members.isNotEmpty;
  int get availableSlots => maxMembers - members.length;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupEntity &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'GroupEntity(id: $id, name: $name, members: ${members.length})';
}
