import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

class SearchMapPickerScreen extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;
  final double radiusKm;

  const SearchMapPickerScreen({
    super.key,
    this.initialLat,
    this.initialLng,
    this.radiusKm = 5.0,
  });

  @override
  State<SearchMapPickerScreen> createState() => _SearchMapPickerScreenState();
}

class _SearchMapPickerScreenState extends State<SearchMapPickerScreen> {
  GoogleMapController? _mapController;
  late LatLng _selectedLocation;
  late double _radiusKm;
  Marker? _selectedMarker;
  Circle? _radiusCircle;
  bool _isLoadingLocation = false;
  String _locationName = '';
  bool _isLoadingAddress = false;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _selectedLocation = LatLng(
      widget.initialLat ?? 13.0827, // Default Chennai
      widget.initialLng ?? 80.2707,
    );
    _radiusKm = widget.radiusKm;
    _updateMarkerAndCircle();
    _getAddressFromLatLng(_selectedLocation);
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  void _onTap(LatLng location) {
    setState(() {
      _selectedLocation = location;
      _updateMarkerAndCircle();
    });
    _getAddressFromLatLng(location);
  }

  void _updateMarkerAndCircle() {
    setState(() {
      _selectedMarker = Marker(
        markerId: const MarkerId('selectedLocation'),
        position: _selectedLocation,
        infoWindow: InfoWindow(
          title: _locationName.isEmpty ? 'Selected Location' : _locationName,
          snippet: '${_radiusKm.toStringAsFixed(1)} km radius',
        ),
      );

      _radiusCircle = Circle(
        circleId: const CircleId('searchRadius'),
        center: _selectedLocation,
        radius: _radiusKm * 1000, // Convert km to meters
        fillColor: Colors.blue.withValues(alpha: 0.2),
        strokeColor: Colors.blue,
        strokeWidth: 2,
      );
    });
  }

  Future<void> _searchPlace() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    setState(() => _isSearching = true);
    try {
      final results = await locationFromAddress(query);
      if (results.isNotEmpty) {
        final loc = results.first;
        final target = LatLng(loc.latitude, loc.longitude);
        _onTap(target);
        await _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(target, 14),
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No results for that place')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Search failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _getAddressFromLatLng(LatLng location) async {
    setState(() => _isLoadingAddress = true);
    try {
      final placemarks = await placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      );

      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        final name = placemark.name ?? '';
        final locality = placemark.locality ?? '';
        final area = placemark.subLocality ?? '';

        setState(() {
          _locationName = [
            name,
            area,
            locality,
          ].where((s) => s.isNotEmpty).take(2).join(', ');
        });
        _updateMarkerAndCircle();
      }
    } catch (e) {
      setState(() => _locationName = 'Unknown location');
    } finally {
      setState(() => _isLoadingAddress = false);
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLoadingLocation = true);

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permissions denied')),
          );
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      final currentLocation = LatLng(position.latitude, position.longitude);
      _onTap(currentLocation);
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(currentLocation, 14),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      setState(() => _isLoadingLocation = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Location & Radius'),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Cancel',
            onPressed: () => Navigator.pop(context, null),
          ),
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _confirmSelection,
            tooltip: 'Confirm',
          ),
        ],
      ),
      body: Stack(
        children: [
          // Google Map
          GoogleMap(
            onMapCreated: _onMapCreated,
            initialCameraPosition: CameraPosition(
              target: _selectedLocation,
              zoom: 13,
            ),
            onTap: _onTap,
            markers: _selectedMarker != null ? {_selectedMarker!} : {},
            circles: _radiusCircle != null ? {_radiusCircle!} : {},
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: true,
          ),

          // Top-center search bar and place name
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Search Bar
                Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  color: cs.surface,
                  child: TextField(
                    controller: _searchController,
                    onSubmitted: (_) => _searchPlace(),
                    textInputAction: TextInputAction.search,
                    maxLines: 1,
                    textAlignVertical: TextAlignVertical.center,
                    decoration: InputDecoration(
                      hintText: 'Search places…',
                      prefixIcon: Icon(
                        Icons.search,
                        color: cs.onSurfaceVariant,
                      ),
                      suffixIcon: IconButton(
                        icon:
                            _isSearching
                                ? SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation(
                                      cs.primary,
                                    ),
                                  ),
                                )
                                : Icon(Icons.arrow_forward, color: cs.primary),
                        onPressed: _isSearching ? null : _searchPlace,
                      ),
                      filled: true,
                      fillColor: cs.surfaceContainerHighest,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: cs.outlineVariant),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: cs.primary, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Place name chip
                Align(
                  alignment: Alignment.center,
                  child: Container(
                    constraints: BoxConstraints(
                      // Keep chip from growing too wide; leave margins
                      maxWidth: MediaQuery.of(context).size.width - 64,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.location_on, color: cs.primary, size: 18),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _isLoadingAddress
                                ? 'Finding place…'
                                : (_locationName.isEmpty
                                    ? 'Tap on map to select'
                                    : _locationName),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom horizontal radius bar with left km pill
          Positioned(
            left: 12,
            right: 72, // leave space for zoom controls
            bottom: 16,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_radiusKm.toStringAsFixed(1)} km',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Material(
                    elevation: 2,
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Slider(
                        min: 1,
                        max: 50,
                        divisions: 49,
                        value: _radiusKm.clamp(1, 50).toDouble(),
                        onChanged: (v) {
                          setState(() {
                            _radiusKm = v;
                            _updateMarkerAndCircle();
                          });
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom-right action buttons stacked above zoom controls
          Positioned(
            right: 12,
            bottom: 120, // keep just above zoom controls and bottom slider
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Material(
                  color: cs.primary,
                  shape: const CircleBorder(),
                  elevation: 3,
                  child: IconButton(
                    icon: Icon(Icons.streetview, color: cs.onPrimary),
                    onPressed: _openStreetView,
                    tooltip: 'Street View',
                  ),
                ),
                const SizedBox(height: 12),
                Material(
                  color: cs.primary,
                  shape: const CircleBorder(),
                  elevation: 3,
                  child: IconButton(
                    icon:
                        _isLoadingLocation
                            ? SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  cs.onPrimary,
                                ),
                              ),
                            )
                            : Icon(Icons.my_location, color: cs.onPrimary),
                    onPressed: _isLoadingLocation ? null : _getCurrentLocation,
                    tooltip: 'Current location',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openStreetView() async {
    final lat = _selectedLocation.latitude;
    final lng = _selectedLocation.longitude;
    final streetViewAppUri = Uri.parse('google.streetview:cbll=$lat,$lng');
    final mapsPanoWebUri = Uri.parse(
      'https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=$lat,$lng',
    );
    final mapsPlaceWebUri = Uri.parse(
      'https://maps.google.com/?q=&layer=c&cbll=$lat,$lng',
    );

    try {
      // Try Street View App deep link first
      if (await canLaunchUrl(streetViewAppUri)) {
        await launchUrl(streetViewAppUri, mode: LaunchMode.externalApplication);
      } else {
        // Try web pano URL
        if (await canLaunchUrl(mapsPanoWebUri)) {
          await launchUrl(mapsPanoWebUri, mode: LaunchMode.externalApplication);
        }
        // As a last resort, open maps with Street View layer
        else if (await canLaunchUrl(mapsPlaceWebUri)) {
          await launchUrl(
            mapsPlaceWebUri,
            mode: LaunchMode.externalApplication,
          );
        }
        // If nothing can be launched, show a message
        else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not launch Street View')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _confirmSelection() {
    Navigator.pop(context, {
      'lat': _selectedLocation.latitude,
      'lng': _selectedLocation.longitude,
      'radius': _radiusKm,
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
