class SearchFilters {
  final double? minRent;
  final double? maxRent;
  final String? location;
  final String? roomType;
  final double? lat;
  final double? lng;
  final double? radiusKm; // when set with lat/lng, filter by distance

  const SearchFilters({
    this.minRent,
    this.maxRent,
    this.location,
    this.roomType,
    this.lat,
    this.lng,
    this.radiusKm,
  });

  // Sentinel to differentiate between "not provided" and "explicit null"
  static const Object _unset = Object();

  SearchFilters copyWith({
    Object? minRent = _unset,
    Object? maxRent = _unset,
    Object? location = _unset,
    Object? roomType = _unset,
    Object? lat = _unset,
    Object? lng = _unset,
    Object? radiusKm = _unset,
  }) {
    return SearchFilters(
      minRent: identical(minRent, _unset) ? this.minRent : minRent as double?,
      maxRent: identical(maxRent, _unset) ? this.maxRent : maxRent as double?,
      location:
          identical(location, _unset) ? this.location : location as String?,
      roomType:
          identical(roomType, _unset) ? this.roomType : roomType as String?,
      lat: identical(lat, _unset) ? this.lat : lat as double?,
      lng: identical(lng, _unset) ? this.lng : lng as double?,
      radiusKm:
          identical(radiusKm, _unset) ? this.radiusKm : radiusKm as double?,
    );
  }

  bool get isEmpty =>
      minRent == null &&
      maxRent == null &&
      (location == null || location!.isEmpty) &&
      (roomType == null || roomType!.isEmpty) &&
      (lat == null || lng == null || radiusKm == null);

  bool get hasGeo => lat != null && lng != null && radiusKm != null;
}
