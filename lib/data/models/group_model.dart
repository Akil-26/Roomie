import 'package:geocoding/geocoding.dart';

// Supporting data classes
class LocationData {
  final String address;
  final String city;
  final String state;
  final String pincode;
  final CoordinatesData coordinates;

  LocationData({
    required this.address,
    required this.city,
    required this.state,
    required this.pincode,
    required this.coordinates,
  });

  factory LocationData.fromMap(Map<String, dynamic> map) {
    return LocationData(
      address: map['address'] ?? '',
      city: map['city'] ?? '',
      state: map['state'] ?? '',
      pincode: map['pincode'] ?? '',
      coordinates: CoordinatesData.fromMap(map['coordinates'] ?? {}),
    );
  }

  /// Create LocationData from coordinates using reverse geocoding
  static Future<LocationData> fromCoordinates(double lat, double lng) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;

        // Build address from placemark components
        String address = '';
        if (place.name != null && place.name!.isNotEmpty) {
          address += place.name!;
        }
        if (place.street != null && place.street!.isNotEmpty) {
          if (address.isNotEmpty) address += ', ';
          address += place.street!;
        }
        if (place.subLocality != null && place.subLocality!.isNotEmpty) {
          if (address.isNotEmpty) address += ', ';
          address += place.subLocality!;
        }

        return LocationData(
          address: address.isNotEmpty ? address : 'Unknown Address',
          city: place.locality ?? place.subAdministrativeArea ?? 'Unknown City',
          state: place.administrativeArea ?? 'Unknown State',
          pincode: place.postalCode ?? '000000',
          coordinates: CoordinatesData(lat: lat, lng: lng),
        );
      }
    } catch (e) {
      print('Error in reverse geocoding: $e');
    }

    // Fallback if geocoding fails
    return LocationData(
      address: 'Location: ${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
      city: 'Unknown City',
      state: 'Unknown State',
      pincode: '000000',
      coordinates: CoordinatesData(lat: lat, lng: lng),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'address': address,
      'city': city,
      'state': state,
      'pincode': pincode,
      'coordinates': coordinates.toMap(),
    };
  }

  /// Update location data with new coordinates and reverse geocode to get address
  Future<LocationData> updateFromCoordinates(double lat, double lng) async {
    return await LocationData.fromCoordinates(lat, lng);
  }

  String get fullAddress => '$address, $city, $state $pincode';

  /// Get a short display address (city, state)
  String get shortAddress => '$city, $state';

  /// Check if coordinates are valid (not 0,0)
  bool get hasValidCoordinates =>
      coordinates.lat != 0.0 || coordinates.lng != 0.0;
}

class CoordinatesData {
  final double lat;
  final double lng;

  CoordinatesData({required this.lat, required this.lng});

  factory CoordinatesData.fromMap(Map<String, dynamic> map) {
    return CoordinatesData(
      lat: (map['lat'] ?? 0.0).toDouble(),
      lng: (map['lng'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {'lat': lat, 'lng': lng};
  }

  /// Convert coordinates to human-readable address
  Future<String> toAddress() async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        return '${place.locality}, ${place.administrativeArea}, ${place.country}';
      }
    } catch (e) {
      print('Error converting coordinates to address: $e');
    }
    return 'Lat: ${lat.toStringAsFixed(6)}, Lng: ${lng.toStringAsFixed(6)}';
  }

  /// Check if coordinates are valid
  bool get isValid => lat != 0.0 || lng != 0.0;

  /// Get formatted coordinate string
  String get formatted =>
      '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';
}

class RentData {
  final double amount;
  final String currency;
  final double advanceAmount;

  const RentData({
    required this.amount,
    required this.currency,
    required this.advanceAmount,
  });

  factory RentData.fromMap(Map<String, dynamic> map) {
    return RentData(
      amount: (map['amount'] ?? 0.0).toDouble(),
      currency: map['currency'] ?? 'INR',
      advanceAmount: (map['advanceAmount'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'amount': amount,
      'currency': currency,
      'advanceAmount': advanceAmount,
    };
  }

  String get _currencySymbol {
    switch (currency.toUpperCase()) {
      case 'USD':
        return r'$';
      case 'EUR':
        return '€';
      case 'INR':
      default:
        return '₹';
    }
  }

  String get displayRent =>
      '$_currencySymbol${amount.toStringAsFixed(0)}/month';

  String get displayAdvance =>
      advanceAmount > 0
          ? '$_currencySymbol${advanceAmount.toStringAsFixed(0)} advance'
          : 'No advance';
}

class MemberData {
  final String userId;
  final String role; // admin | member
  final DateTime joinedAt;

  MemberData({
    required this.userId,
    required this.role,
    required this.joinedAt,
  });

  factory MemberData.fromMap(Map<String, dynamic> map) {
    return MemberData(
      userId: map['userId'] ?? '',
      role: map['role'] ?? 'member',
      joinedAt: map['joinedAt']?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {'userId': userId, 'role': role, 'joinedAt': joinedAt};
  }

  bool get isAdmin => role == 'admin';
}

class JoinRequestData {
  final String userId;
  final String message;
  final String status; // pending | accepted | rejected
  final DateTime requestedAt;

  JoinRequestData({
    required this.userId,
    required this.message,
    required this.status,
    required this.requestedAt,
  });

  factory JoinRequestData.fromMap(Map<String, dynamic> map) {
    return JoinRequestData(
      userId: map['userId'] ?? '',
      message: map['message'] ?? '',
      status: map['status'] ?? 'pending',
      requestedAt: map['requestedAt']?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'message': message,
      'status': status,
      'requestedAt': requestedAt,
    };
  }

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isRejected => status == 'rejected';
}

/// Room status enum for persistence
/// - active: Room is active and can be joined
/// - inactive: Room is deactivated (soft deleted)
enum RoomStatus {
  active,
  inactive;

  String get value {
    switch (this) {
      case RoomStatus.active:
        return 'active';
      case RoomStatus.inactive:
        return 'inactive';
    }
  }

  static RoomStatus fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'inactive':
        return RoomStatus.inactive;
      case 'active':
      default:
        return RoomStatus.active;
    }
  }
}

/// Room creation type enum
/// - userCreated: Room created by a regular user (roommate)
/// - ownerCreated: Room created by property owner (future feature)
enum RoomCreationType {
  userCreated,
  ownerCreated;

  String get value {
    switch (this) {
      case RoomCreationType.userCreated:
        return 'user_created';
      case RoomCreationType.ownerCreated:
        return 'owner_created';
    }
  }

  static RoomCreationType fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'owner_created':
        return RoomCreationType.ownerCreated;
      case 'user_created':
      default:
        return RoomCreationType.userCreated;
    }
  }
}

class GroupModel {
  final String id;
  final String name;
  final String description;
  final String? imageId; // MongoDB image reference ID
  final LocationData location;
  final String roomType; // e.g., '1BHK', '2BHK', 'Shared', 'PG'
  final int capacity; // Max roommates allowed (renamed from maxMembers)
  final int currentMembers; // Current joined members (renamed from memberCount)
  final RentData rent;
  final List<String> amenities; // Facilities available
  final List<String> images; // Cloudinary/Firebase image URLs
  final String createdBy; // Admin/Creator ID
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<MemberData> members; // All members with roles
  final List<JoinRequestData> joinRequests; // Pending join requests
  
  // === NEW FIELDS FOR ROOM PERSISTENCE ===
  // These fields ensure rooms exist independently of members
  
  /// Room status: 'active' or 'inactive'. 
  /// IMPORTANT: Rooms should NEVER be auto-deleted. Only status changes.
  final RoomStatus status;
  
  /// Whether this room is publicly visible in available rooms list
  final bool isPublic;
  
  /// Type of room creation: 'user_created' or 'owner_created'
  final RoomCreationType creationType;
  
  /// Owner ID (nullable for now, will be used for owner-merge feature later)
  final String? ownerId;

  GroupModel({
    required this.id,
    required this.name,
    required this.description,
    this.imageId,
    required this.location,
    required this.roomType,
    required this.capacity,
    required this.currentMembers,
    required this.rent,
    required this.amenities,
    required this.images,
    required this.createdBy,
    required this.createdAt,
    this.updatedAt,
    required this.members,
    required this.joinRequests,
    // New fields with defaults for backward compatibility
    this.status = RoomStatus.active,
    this.isPublic = true,
    this.creationType = RoomCreationType.userCreated,
    this.ownerId,
  });

  factory GroupModel.fromMap(Map<String, dynamic> map, String id) {
    final dynamic rentRaw = map['rent'];
    double rentAmount = 0.0;
    String rentCurrency = (map['rentCurrency'] ?? 'INR').toString();
    double advanceAmount = (map['advanceAmount'] ?? 0.0).toDouble();

    if (rentRaw is Map<String, dynamic>) {
      rentAmount = (rentRaw['amount'] ?? rentAmount).toDouble();
      rentCurrency = (rentRaw['currency'] ?? rentCurrency).toString();
      advanceAmount = (rentRaw['advanceAmount'] ?? advanceAmount).toDouble();
    } else if (rentRaw is num) {
      rentAmount = rentRaw.toDouble();
    }

    if (map['rentAmount'] != null) {
      rentAmount = (map['rentAmount'] as num).toDouble();
    }

    if (map['rentCurrency'] != null) {
      rentCurrency = map['rentCurrency'].toString();
    }

    if (map['advanceAmount'] != null) {
      advanceAmount = (map['advanceAmount'] as num).toDouble();
    }

    return GroupModel(
      id: id,
      name: map['roomName'] ?? map['name'] ?? '',
      description: map['description'] ?? '',
      imageId: map['imageId'],
      location: LocationData.fromMap(map['location'] ?? {}),
      roomType: map['roomType'] ?? 'Shared',
      capacity: map['capacity'] ?? map['maxMembers'] ?? 4,
      currentMembers: map['currentMembers'] ?? map['memberCount'] ?? 0,
      rent: RentData(
        amount: rentAmount,
        currency: rentCurrency,
        advanceAmount: advanceAmount,
      ),
      amenities: List<String>.from(map['amenities'] ?? []),
      images: List<String>.from(map['images'] ?? []),
      createdBy: map['adminId'] ?? map['createdBy'] ?? '',
      createdAt: map['createdAt']?.toDate() ?? DateTime.now(),
      updatedAt: map['updatedAt']?.toDate(),
      members:
          (map['members'] as List<dynamic>? ?? [])
              .map((m) => MemberData.fromMap(m))
              .toList(),
      joinRequests:
          (map['joinRequests'] as List<dynamic>? ?? [])
              .map((r) => JoinRequestData.fromMap(r))
              .toList(),
      // New fields for room persistence
      status: RoomStatus.fromString(map['status']),
      isPublic: map['isPublic'] ?? true,
      creationType: RoomCreationType.fromString(map['creationType']),
      ownerId: map['ownerId'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'roomName': name,
      'name': name, // Keep both for compatibility
      'description': description,
      'imageId': imageId,
      'location': location.toMap(),
      'roomType': roomType,
      'capacity': capacity,
      'currentMembers': currentMembers,
      'rent': rent.toMap(),
      'rentAmount': rent.amount,
      'rentCurrency': rent.currency,
      'advanceAmount': rent.advanceAmount,
      'amenities': amenities,
      'images': images,
      'adminId': createdBy,
      'createdBy': createdBy, // Keep both for compatibility
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'members': members.map((m) => m.toMap()).toList(),
      'joinRequests': joinRequests.map((r) => r.toMap()).toList(),
      // New fields for room persistence
      'status': status.value,
      'isPublic': isPublic,
      'creationType': creationType.value,
      'ownerId': ownerId,
    };
  }

  GroupModel copyWith({
    String? id,
    String? name,
    String? description,
    String? imageId,
    LocationData? location,
    String? roomType,
    int? capacity,
    int? currentMembers,
    RentData? rent,
    List<String>? amenities,
    List<String>? images,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<MemberData>? members,
    List<JoinRequestData>? joinRequests,
    // New fields
    RoomStatus? status,
    bool? isPublic,
    RoomCreationType? creationType,
    String? ownerId,
  }) {
    return GroupModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      imageId: imageId ?? this.imageId,
      location: location ?? this.location,
      roomType: roomType ?? this.roomType,
      capacity: capacity ?? this.capacity,
      currentMembers: currentMembers ?? this.currentMembers,
      rent: rent ?? this.rent,
      amenities: amenities ?? this.amenities,
      images: images ?? this.images,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      members: members ?? this.members,
      joinRequests: joinRequests ?? this.joinRequests,
      // New fields
      status: status ?? this.status,
      isPublic: isPublic ?? this.isPublic,
      creationType: creationType ?? this.creationType,
      ownerId: ownerId ?? this.ownerId,
    );
  }

  // Helper getters
  bool get hasAvailableSlots => currentMembers < capacity;

  int get availableSlots => capacity - currentMembers;

  bool get isFull => currentMembers >= capacity;

  String get memberCountText => '$currentMembers/$capacity members';

  String get displayName => name.isNotEmpty ? name : 'Unnamed Group';

  String get displayDescription =>
      description.isNotEmpty ? description : 'No description available';

  String get displayRent => rent.displayRent;

  String get displayAdvance => rent.displayAdvance;

  String get displayLocation => location.fullAddress;

  bool get hasPendingRequests => joinRequests.any((r) => r.isPending);

  int get pendingRequestsCount => joinRequests.where((r) => r.isPending).length;

  List<MemberData> get adminMembers => members.where((m) => m.isAdmin).toList();

  /// Check if room is active and visible
  bool get isActive => status == RoomStatus.active;
  
  /// Check if room is visible in available rooms list
  bool get isVisible => isActive && isPublic;
  
  /// Check if room was created by a property owner
  bool get isOwnerCreated => creationType == RoomCreationType.ownerCreated;
  
  /// Check if room has an assigned owner
  bool get hasOwner => ownerId != null && ownerId!.isNotEmpty;

  MemberData? get primaryAdmin => members.firstWhere(
    (m) => m.isAdmin && m.userId == createdBy,
    orElse:
        () => members.firstWhere(
          (m) => m.isAdmin,
          orElse: () => throw StateError('No admin found'),
        ),
  );

  @override
  String toString() {
    return 'GroupModel(id: $id, name: $name, location: ${location.fullAddress}, currentMembers: $currentMembers)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GroupModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  // Hybrid Storage Methods

  /// Returns data for Firebase Firestore (text data only)
  Map<String, dynamic> toFirestoreMap() {
    return {
      'roomName': name,
      'name': name, // Keep both for compatibility
      'description': description,
      'location': location.toMap(),
      'roomType': roomType,
      'capacity': capacity,
      'currentMembers': currentMembers,
      'rent': rent.toMap(),
      'rentAmount': rent.amount,
      'rentCurrency': rent.currency,
      'advanceAmount': rent.advanceAmount,
      'amenities': amenities,
      'images': images,
      'adminId': createdBy,
      'createdBy': createdBy, // Keep both for compatibility
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'imageId': imageId, // Store MongoDB image reference in Firestore
      'members': members.map((m) => m.toMap()).toList(),
      'joinRequests': joinRequests.map((r) => r.toMap()).toList(),
      // New fields for room persistence
      'status': status.value,
      'isPublic': isPublic,
      'creationType': creationType.value,
      'ownerId': ownerId,
    };
  }

  /// Creates GroupModel from Firestore data
  factory GroupModel.fromFirestore(Map<String, dynamic> data, String id) {
    final dynamic rentRaw = data['rent'];
    double rentAmount = 0.0;
    String rentCurrency = (data['rentCurrency'] ?? 'INR').toString();
    double advanceAmount = (data['advanceAmount'] ?? 0.0).toDouble();

    if (rentRaw is Map<String, dynamic>) {
      rentAmount = (rentRaw['amount'] ?? rentAmount).toDouble();
      rentCurrency = (rentRaw['currency'] ?? rentCurrency).toString();
      advanceAmount = (rentRaw['advanceAmount'] ?? advanceAmount).toDouble();
    } else if (rentRaw is num) {
      rentAmount = rentRaw.toDouble();
    }

    if (data['rentAmount'] != null) {
      rentAmount = (data['rentAmount'] as num).toDouble();
    }

    if (data['rentCurrency'] != null) {
      rentCurrency = data['rentCurrency'].toString();
    }

    if (data['advanceAmount'] != null) {
      advanceAmount = (data['advanceAmount'] as num).toDouble();
    }

    return GroupModel(
      id: id,
      name: data['roomName'] ?? data['name'] ?? '',
      description: data['description'] ?? '',
      imageId: data['imageId'], // MongoDB image reference
      location: LocationData.fromMap(data['location'] ?? {}),
      roomType: data['roomType'] ?? 'Shared',
      capacity: data['capacity'] ?? data['maxMembers'] ?? 4,
      currentMembers: data['currentMembers'] ?? data['memberCount'] ?? 0,
      rent: RentData(
        amount: rentAmount,
        currency: rentCurrency,
        advanceAmount: advanceAmount,
      ),
      amenities: List<String>.from(data['amenities'] ?? []),
      images: List<String>.from(data['images'] ?? []),
      createdBy: data['adminId'] ?? data['createdBy'] ?? '',
      createdAt: data['createdAt']?.toDate() ?? DateTime.now(),
      updatedAt: data['updatedAt']?.toDate(),
      members:
          (data['members'] as List<dynamic>? ?? [])
              .map((m) => MemberData.fromMap(m))
              .toList(),
      joinRequests:
          (data['joinRequests'] as List<dynamic>? ?? [])
              .map((r) => JoinRequestData.fromMap(r))
              .toList(),
      // New fields for room persistence
      status: RoomStatus.fromString(data['status']),
      isPublic: data['isPublic'] ?? true,
      creationType: RoomCreationType.fromString(data['creationType']),
      ownerId: data['ownerId'],
    );
  }

  /// Returns data for MongoDB (image data handling)
  Map<String, dynamic> toMongoMap() {
    return {
      'groupId': id, // Reference to Firestore group
      'imageId': imageId,
      'uploadedAt': DateTime.now().toIso8601String(),
    };
  }
}
