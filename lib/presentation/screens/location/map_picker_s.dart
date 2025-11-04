import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

class MapPickerScreen extends StatefulWidget {
  final Function(String, double, double) onLocationSelected;

  const MapPickerScreen({super.key, required this.onLocationSelected});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  GoogleMapController? _mapController;
  LatLng _selectedLocation = const LatLng(20.5937, 78.9629); // Default to India
  Marker? _selectedMarker;
  bool _isLoadingLocation = false;

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  void _onTap(LatLng location) async {
    setState(() {
      _selectedLocation = location;
      _selectedMarker = Marker(
        markerId: const MarkerId('selectedLocation'),
        position: _selectedLocation,
      );
    });
  }

  void _confirmSelection() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final onLocationSelected = widget.onLocationSelected;
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        _selectedLocation.latitude,
        _selectedLocation.longitude,
      );

      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        final address =
            '${placemark.name}, ${placemark.street}, ${placemark.locality}, ${placemark.postalCode}, ${placemark.country}';
        onLocationSelected(
          address,
          _selectedLocation.latitude,
          _selectedLocation.longitude,
        );
        navigator.pop();
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Error getting address: $e')),
      );
    }
  }

  Future<void> _getCurrentLocation() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _isLoadingLocation = true;
    });

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Location permissions are denied.')),
        );
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
        CameraUpdate.newLatLngZoom(currentLocation, 15),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Error getting current location: $e')),
      );
    } finally {
      setState(() {
        _isLoadingLocation = false;
      });
    }
  }

  Future<void> _openStreetView() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_selectedMarker != null) {
      final lat = _selectedLocation.latitude;
      final lng = _selectedLocation.longitude;
      final uri = Uri.parse('google.streetview:cbll=$lat,$lng');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // Fallback to web browser if Google Maps app is not installed
        final webUri = Uri.parse(
          'https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=$lat,$lng',
        );
        if (await canLaunchUrl(webUri)) {
          await launchUrl(webUri, mode: LaunchMode.externalApplication);
        } else {
          messenger.showSnackBar(
            const SnackBar(content: Text('Could not launch Street View')),
          );
        }
      }
    } else {
      messenger.showSnackBar(
        const SnackBar(content: Text('Please select a location first')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Location'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _selectedMarker != null ? _confirmSelection : null,
          ),
        ],
      ),
      body: GoogleMap(
        onMapCreated: _onMapCreated,
        initialCameraPosition: CameraPosition(
          target: _selectedLocation,
          zoom: 5,
        ),
        onTap: _onTap,
        markers: _selectedMarker != null ? {_selectedMarker!} : {},
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 16.0),
            child: FloatingActionButton(
              heroTag: 'streetView',
              onPressed: _openStreetView,
              child: const Icon(Icons.streetview),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(bottom: 80.0),
            child: FloatingActionButton(
              heroTag: 'myLocation',
              onPressed: _isLoadingLocation ? null : _getCurrentLocation,
              child:
                  _isLoadingLocation
                      ? CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).colorScheme.onPrimary,
                        ),
                      )
                      : const Icon(Icons.my_location),
            ),
          ),
        ],
      ),
    );
  }
}
