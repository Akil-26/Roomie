import 'package:flutter/material.dart';
import 'package:roomie/data/models/search_filters.dart';
import 'package:roomie/presentation/controllers/search_controller.dart' as sc;
import 'package:roomie/presentation/screens/groups/available_group_detail_s.dart';
import 'package:roomie/presentation/screens/search/search_map_picker_s.dart';
import 'package:geocoding/geocoding.dart';
import 'package:intl/intl.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final sc.GroupsSearchController _controller;
  final TextEditingController _searchCtrl = TextEditingController();
  List<String> _history = const [];
  String? _geoPlaceName; // Cached place name for selected geo filter
  String _rentCurrency = 'INR';
  bool _showCurrencyPicker = false;

  String _currencySymbol(String currency) {
    switch (currency.toUpperCase()) {
      case 'INR':
        return '₹';
      case 'USD':
        return '\$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      case 'AED':
        return 'د.إ';
      case 'AUD':
        return 'A\$';
      case 'SGD':
        return 'S\$';
      default:
        return currency.toUpperCase();
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = sc.GroupsSearchController();
    _controller.addListener(_onChanged);
    _controller.init();
    _loadHistory();
  }

  void _onChanged() => setState(() {});

  Future<String?> _resolvePlaceName(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        // Prefer locality + administrative area, fall back gracefully
        final parts = [
          if ((p.locality ?? '').trim().isNotEmpty) p.locality!.trim(),
          if ((p.administrativeArea ?? '').trim().isNotEmpty)
            p.administrativeArea!.trim(),
          if ((p.country ?? '').trim().isNotEmpty) p.country!.trim(),
        ];
        if (parts.isNotEmpty) return parts.take(2).join(', ');
        // fallback to street + subLocality if locality missing
        final alt = [
          if ((p.street ?? '').trim().isNotEmpty) p.street!.trim(),
          if ((p.subLocality ?? '').trim().isNotEmpty) p.subLocality!.trim(),
        ];
        if (alt.isNotEmpty) return alt.join(', ');
      }
    } catch (_) {
      // ignore geocoding errors silently
    }
    return null;
  }

  Future<void> _loadHistory() async {
    final h = await _controller.getHistory();
    if (mounted) setState(() => _history = h);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 1,
        title: Text(
          'Search',
          style:
              theme.textTheme.headlineSmall?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.bold,
              ) ??
              TextStyle(
                color: cs.onSurface,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
        ),
      ),
      body: Column(
        children: [
          // Top Row: Messages-style search bar + one Filter button
          Container(
            color: Colors.transparent,
            padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.028, vertical: 0),
            child: Row(
              children: [
                // Messages-like search bar
                Expanded(
                  flex: 1,
                  child: Container(
                    height: screenHeight * 0.055,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: cs.outlineVariant, width: 1),
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (v) => _controller.setQuery(v),
                      onSubmitted: (_) async {
                        await _controller.commitQueryToHistory();
                        await _loadHistory();
                      },
                      decoration: InputDecoration(
                        hintText: 'Search here',
                        prefixIcon: Icon(
                          Icons.search,
                          color: cs.onSurfaceVariant,
                          size: screenWidth * 0.05,
                        ),
                        filled: true,
                        fillColor: Colors.transparent,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: screenWidth * 0.04),
                // Messages-style Filter button: filled pill with primary color
                SizedBox(
                  height: screenHeight * 0.055,
                  child: ElevatedButton.icon(
                    onPressed: _openFilters,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                      padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.038),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                    icon: Icon(Icons.tune, size: screenWidth * 0.05),
                    label: Text(
                      'Filters',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: cs.onPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // History row (with clear all)
          if (_history.isNotEmpty)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.03, vertical: screenHeight * 0.005),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Recent searches',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      await _controller.clearHistory();
                      await _loadHistory();
                    },
                    child: const Text('Clear all'),
                  ),
                ],
              ),
            ),

          if (_history.isNotEmpty)
            SizedBox(
              height: screenHeight * 0.055,
              child: ListView.separated(
                padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.03),
                scrollDirection: Axis.horizontal,
                itemBuilder: (context, index) {
                  final item = _history[index];
                  return InputChip(
                    label: Text(item),
                    onPressed: () {
                      _searchCtrl.text = item;
                      _controller.setQuery(item);
                    },
                    onDeleted: () async {
                      await _controller.removeHistoryAt(index);
                      await _loadHistory();
                    },
                  );
                },
                separatorBuilder: (context, index) => SizedBox(width: screenWidth * 0.02),
                itemCount: _history.length,
              ),
            ),

          // Results
          Expanded(
            child: Builder(
              builder: (_) {
                final filters = _controller.filters;
                final hasQuery = _searchCtrl.text.trim().isNotEmpty;
                final hasActiveFilters =
                    (filters.minRent != null) ||
                    (filters.maxRent != null) ||
                    ((filters.roomType?.isNotEmpty ?? false)) ||
                    (filters.hasGeo);

                // Until user searches or applies a filter, show a friendly empty state
                if (!hasQuery && !hasActiveFilters) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.search,
                          size: screenWidth * 0.1,
                          color: cs.onSurfaceVariant,
                        ),
                        SizedBox(height: screenHeight * 0.01),
                        Text(
                          'Find rooms',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Search by room name, location, or rent',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                if (_controller.loading) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (_controller.results.isEmpty) {
                  return Center(
                    child: Text(
                      'No rooms found',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: EdgeInsets.fromLTRB(screenWidth * 0.03, screenHeight * 0.01, screenWidth * 0.03, screenHeight * 0.015),
                  itemBuilder: (_, i) {
                    final g = _controller.results[i];
                    return _GroupTile(group: g);
                  },
                  separatorBuilder:
                      (context, index) => SizedBox(height: screenHeight * 0.01),
                  itemCount: _controller.results.length,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openFilters() async {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    final numberFmt = NumberFormat.decimalPattern();
    double? minRent = _controller.filters.minRent;
    double? maxRent = _controller.filters.maxRent;
    double radiusKm = _controller.filters.radiusKm ?? 5.0;
    String? selectedRoomType =
        _controller.filters.roomType?.isNotEmpty == true
            ? _controller.filters.roomType
            : null; // null means "None"
    double sliderMin = 0;
    double sliderMax = 100000; // adjust as needed or derive from data
    RangeValues currentRange = RangeValues(
      (minRent ?? sliderMin).clamp(sliderMin, sliderMax),
      (maxRent ?? sliderMax).clamp(sliderMin, sliderMax),
    );
    final roomTypes = <String>['1BHK', '2BHK', '3BHK', 'PG', 'Studio'];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Filters',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () {
                                setModalState(() {
                                  minRent = null;
                                  maxRent = null;
                                  selectedRoomType = null;
                                  radiusKm = 5.0;
                                  currentRange = const RangeValues(0, 100000);
                                });
                                _controller.setFilters(const SearchFilters());
                                setState(() => _geoPlaceName = null);
                              },
                              child: const Text('Reset'),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                              onPressed: () {
                                // Filters are already applied live; just close the sheet
                                Navigator.of(context).pop();
                              },
                              child: Text(
                                'Done',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: cs.onPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // LOCATION: Map button with inline place name and clear
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        onPressed: () async {
                          await _pickLocationOnMap(setModalState, radiusKm);
                        },
                        child: Row(
                          children: [
                            Icon(Icons.map, color: cs.onPrimary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _controller.filters.hasGeo
                                    ? (_geoPlaceName ??
                                        'Location set • ${(_controller.filters.radiusKm ?? radiusKm).toStringAsFixed(1)} km')
                                    : 'Select location & radius',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: cs.onPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (_controller.filters.hasGeo)
                              IconButton(
                                tooltip: 'Clear location',
                                icon: Icon(Icons.close, color: cs.onPrimary),
                                onPressed: () {
                                  _controller.setFilters(
                                    _controller.filters.copyWith(
                                      lat: null,
                                      lng: null,
                                      radiusKm: null,
                                    ),
                                  );
                                  setState(() => _geoPlaceName = null);
                                  setModalState(() {});
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // RENT RANGE header with values on the right, above slider
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Rent range',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: cs.onSurface,
                          ),
                        ),
                        InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () {
                            setModalState(
                              () => _showCurrencyPicker = !_showCurrencyPicker,
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${_currencySymbol(_rentCurrency)}${numberFmt.format(currentRange.start.round())} - ${_currencySymbol(_rentCurrency)}${numberFmt.format(currentRange.end.round())}',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: cs.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  _showCurrencyPicker
                                      ? Icons.keyboard_arrow_up
                                      : Icons.keyboard_arrow_down,
                                  size: 18,
                                  color: cs.onSurfaceVariant,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      child:
                          _showCurrencyPicker
                              ? Padding(
                                padding: const EdgeInsets.only(
                                  top: 8.0,
                                  bottom: 4.0,
                                ),
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final c in const [
                                      'INR',
                                      'USD',
                                      'EUR',
                                      'GBP',
                                      'AED',
                                      'AUD',
                                      'SGD',
                                    ])
                                      ChoiceChip(
                                        label: Text(
                                          c,
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                        selected: _rentCurrency == c,
                                        shape: const StadiumBorder(),
                                        side: BorderSide(
                                          color: cs.outlineVariant,
                                        ),
                                        onSelected: (_) {
                                          setState(() => _rentCurrency = c);
                                          setModalState(() {
                                            _rentCurrency = c;
                                            _showCurrencyPicker = false;
                                          });
                                        },
                                      ),
                                  ],
                                ),
                              )
                              : const SizedBox.shrink(),
                    ),
                    RangeSlider(
                      min: sliderMin,
                      max: sliderMax,
                      divisions: 100,
                      labels: RangeLabels(
                        currentRange.start.toStringAsFixed(0),
                        currentRange.end.toStringAsFixed(0),
                      ),
                      values: currentRange,
                      onChanged: (values) {
                        setModalState(() {
                          currentRange = values;
                          minRent =
                              values.start == sliderMin ? null : values.start;
                          maxRent = values.end == sliderMax ? null : values.end;
                        });
                        _controller.setFilters(
                          _controller.filters.copyWith(
                            minRent: minRent,
                            maxRent: maxRent,
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 12),

                    // ROOM TYPE: theme-like pills, keep animations/colors
                    Text(
                      'Room type',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: Text(
                            'None',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          selected:
                              selectedRoomType == null ||
                              selectedRoomType!.isEmpty,
                          shape: const StadiumBorder(),
                          side: BorderSide(color: cs.outlineVariant),
                          onSelected: (sel) {
                            setModalState(() => selectedRoomType = null);
                            _controller.setFilters(
                              _controller.filters.copyWith(roomType: ''),
                            );
                          },
                        ),
                        for (final rt in roomTypes)
                          ChoiceChip(
                            label: Text(
                              rt,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            selected: selectedRoomType == rt,
                            shape: const StadiumBorder(),
                            side: BorderSide(color: cs.outlineVariant),
                            onSelected: (sel) {
                              setModalState(
                                () => selectedRoomType = sel ? rt : null,
                              );
                              _controller.setFilters(
                                _controller.filters.copyWith(
                                  roomType: sel ? rt : '',
                                ),
                              );
                            },
                          ),
                      ],
                    ),

                    const SizedBox(height: 8),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _pickLocationOnMap(
    StateSetter setModalState,
    double radiusKm,
  ) async {
    final result = await Navigator.push<Map<String, double>>(
      context,
      MaterialPageRoute(
        builder:
            (context) => SearchMapPickerScreen(
              initialLat: _controller.filters.lat,
              initialLng: _controller.filters.lng,
              radiusKm: radiusKm,
            ),
      ),
    );

    if (result != null && result['lat'] != null && result['lng'] != null) {
      final selectedRadius = result['radius'] ?? radiusKm;
      _controller.setGeo(result['lat']!, result['lng']!, selectedRadius);
      // Resolve and cache a nice place label for the button
      _resolvePlaceName(result['lat']!, result['lng']!).then((name) {
        if (mounted) setState(() => _geoPlaceName = name);
      });

      // Force full widget rebuild to show updated location
      setState(() {});
      setModalState(() {}); // Update modal state

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Location set! Radius: ${selectedRadius.toStringAsFixed(1)} km',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } else {
      // User cancelled selection; do nothing (keep existing filters)
    }
  }
}

class _GroupTile extends StatelessWidget {
  final Map<String, dynamic> group;
  const _GroupTile({required this.group});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = group['name']?.toString() ?? 'Group';
    final location = group['location']?.toString() ?? '';
    final roomType = group['roomType']?.toString();
    final rent =
        group['rentAmount'] is num
            ? (group['rentAmount'] as num).toDouble()
            : null;
    final currency = group['rentCurrency']?.toString() ?? '₹';

    return Card(
      color: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: cs.primary,
          child: Icon(Icons.home_work_outlined, color: cs.onPrimary),
        ),
        title: Text(
          name,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: cs.onSurface),
        ),
        subtitle: Text(
          [
            if (location.isNotEmpty) location,
            if (roomType != null && roomType.isNotEmpty) roomType,
          ].join(' • '),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        trailing:
            rent == null
                ? null
                : Text(
                  '$currency${rent.toStringAsFixed(0)}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AvailableGroupDetailScreen(group: group),
            ),
          );
        },
      ),
    );
  }
}
