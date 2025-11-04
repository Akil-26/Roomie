import 'package:flutter/foundation.dart';
import 'dart:math' show sin, cos, sqrt, atan2;
import 'package:roomie/data/datasources/groups_service.dart';
import 'package:roomie/data/datasources/search_history_service.dart';
import 'package:roomie/data/models/search_filters.dart';

class GroupsSearchController extends ChangeNotifier {
  final GroupsService _groupsService;
  final SearchHistoryService _historyService;

  String _query = '';
  SearchFilters _filters = const SearchFilters();
  bool _loading = false;
  bool _disposed = false;
  List<Map<String, dynamic>> _all = [];
  List<Map<String, dynamic>> _results = [];

  GroupsSearchController({
    GroupsService? groupsService,
    SearchHistoryService? historyService,
  }) : _groupsService = groupsService ?? GroupsService(),
       _historyService = historyService ?? SearchHistoryService();

  String get query => _query;
  SearchFilters get filters => _filters;
  bool get loading => _loading;
  // Whether we have any input to filter by (query or any filter set)
  bool get hasInput => _query.trim().isNotEmpty || !_filters.isEmpty;
  List<Map<String, dynamic>> get results => _results;

  Future<void> init() async {
    await refreshBase();
  }

  Future<void> refreshBase() async {
    _loading = true;
    _safeNotify();
    try {
      _all = await _groupsService.getAllGroups();
      _apply();
    } finally {
      _loading = false;
      _safeNotify();
    }
  }

  void setQuery(String q) {
    _query = q;
    _apply();
    _safeNotify();
  }

  void setFilters(SearchFilters f) {
    _filters = f;
    _apply();
    _safeNotify();
  }

  Future<void> commitQueryToHistory() async {
    if (_query.trim().isEmpty) return;
    await _historyService.addQuery(_query.trim());
  }

  Future<List<String>> getHistory() => _historyService.getHistory();
  Future<void> removeHistoryAt(int index) => _historyService.removeAt(index);
  Future<void> clearHistory() => _historyService.clear();

  void _apply() {
    // If neither query nor filters provided, show all
    if (!hasInput) {
      _results = List<Map<String, dynamic>>.from(_all);
      return;
    }
    final q = _query.trim().toLowerCase();
    _results =
        _all.where((g) {
          // Apply query on group name and location
          final name = (g['name']?.toString() ?? '').toLowerCase();
          final location = (g['location']?.toString() ?? '').toLowerCase();
          final matchesQuery =
              q.isEmpty || name.contains(q) || location.contains(q);

          // Filters: rent range
          final rentAmount =
              (g['rentAmount'] is num)
                  ? (g['rentAmount'] as num).toDouble()
                  : null;
          final rentOk =
              (_filters.minRent == null ||
                  (rentAmount != null && rentAmount >= _filters.minRent!)) &&
              (_filters.maxRent == null ||
                  (rentAmount != null && rentAmount <= _filters.maxRent!));

          // Filters: location exact/substring
          final locOk =
              _filters.location == null ||
              _filters.location!.isEmpty ||
              location.contains(_filters.location!.toLowerCase());

          // Filters: room type exact match
          final roomType = (g['roomType']?.toString() ?? '').toLowerCase();
          final roomOk =
              _filters.roomType == null ||
              _filters.roomType!.isEmpty ||
              roomType == _filters.roomType!.toLowerCase();

          // Filters: geodistance if group has coordinates (lat,lng)
          bool geoOk = true;
          if (_filters.hasGeo) {
            final gLat =
                (g['lat'] is num) ? (g['lat'] as num).toDouble() : null;
            final gLng =
                (g['lng'] is num) ? (g['lng'] as num).toDouble() : null;
            if (gLat != null && gLng != null) {
              // If room has coordinates, use Haversine distance
              final dKm = _haversineKm(
                _filters.lat!,
                _filters.lng!,
                gLat,
                gLng,
              );
              geoOk = dKm <= (_filters.radiusKm ?? 5.0);
            } else {
              // If a geo-filter is active, rooms without coordinates should not match.
              geoOk = false;
            }
          }

          return matchesQuery && rentOk && locOk && roomOk && geoOk;
        }).toList();
  }

  // Set geo filter helper
  void setGeo(double lat, double lng, double radiusKm) {
    _filters = _filters.copyWith(lat: lat, lng: lng, radiusKm: radiusKm);
    _apply();
    _safeNotify();
  }

  // Haversine distance between two lat/lng points in KM
  double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0; // Earth radius in km
    double toRad(double deg) => deg * 3.141592653589793 / 180.0;
    final dLat = toRad(lat2 - lat1);
    final dLon = toRad(lon2 - lon1);
    final a =
        (sin(dLat / 2) * sin(dLat / 2)) +
        (cos(toRad(lat1)) * cos(toRad(lat2)) * sin(dLon / 2) * sin(dLon / 2));
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
