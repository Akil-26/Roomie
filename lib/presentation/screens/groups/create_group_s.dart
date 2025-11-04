import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:roomie/presentation/screens/location/map_picker_s.dart';
import 'package:roomie/data/datasources/enhanced_geocoding_service.dart';
import 'package:roomie/data/datasources/groups_service.dart';

import 'dart:io';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class DashedBorderPainter extends CustomPainter {
  final Color color;

  DashedBorderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke;

    const dashWidth = 5.0;
    const dashSpace = 3.0;
    double startX = 0;

    final path = Path();

    // Top border
    while (startX < size.width) {
      path.moveTo(startX, 0);
      path.lineTo(startX + dashWidth, 0);
      startX += dashWidth + dashSpace;
    }

    // Right border
    double startY = 0;
    while (startY < size.height) {
      path.moveTo(size.width, startY);
      path.lineTo(size.width, startY + dashWidth);
      startY += dashWidth + dashSpace;
    }

    // Bottom border
    startX = size.width;
    while (startX > 0) {
      path.moveTo(startX, size.height);
      path.lineTo(startX - dashWidth, size.height);
      startX -= dashWidth + dashSpace;
    }

    // Left border
    startY = size.height;
    while (startY > 0) {
      path.moveTo(0, startY);
      path.lineTo(0, startY - dashWidth);
      startY -= dashWidth + dashSpace;
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _groupNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _pincodeController = TextEditingController();
  final _rentAmountController = TextEditingController();
  final _advanceAmountController = TextEditingController();
  final _capacityController = TextEditingController();
  final _descriptionController = TextEditingController();

  final ImagePicker _picker = ImagePicker();
  final List<File> _selectedImages = [];
  final List<XFile> _webImageFiles = [];
  final List<Uint8List> _webImageBytes = [];
  bool _isLoading = false;
  final GroupsService _groupsService = GroupsService();
  final EnhancedGeocodingService _geocodingService = EnhancedGeocodingService();

  // New fields for enhanced room model
  String _selectedRoomType = '1BHK';
  String _selectedCurrency = 'INR';
  int _selectedCapacity = 4;
  final List<String> _selectedAmenities = [];
  double? _latitude;
  double? _longitude;

  final List<String> _roomTypes = ['1BHK', '2BHK', '3BHK', 'Shared', 'PG'];
  final List<String> _currencies = ['INR', 'USD', 'EUR'];
  final List<int> _capacityOptions = List<int>.generate(
    10,
    (index) => index + 1,
  );
  final List<String> _availableAmenities = [
    'WiFi',
    'Parking',
    'AC',
    'Washing Machine',
    'Refrigerator',
    'Microwave',
    'Gym',
    'Swimming Pool',
    'Security',
    'Power Backup',
    'Lift',
    'Balcony',
  ];

  @override
  void initState() {
    super.initState();
    _capacityController.text = _selectedCapacity.toString();
  }

  Future<void> _pickImages() async {
    try {
      List<XFile> pickedImages = [];

      try {
        pickedImages = await _picker.pickMultiImage(
          maxWidth: 800,
          maxHeight: 600,
          imageQuality: 85,
        );
      } catch (error) {
        if (error is UnimplementedError || error is UnsupportedError) {
          final XFile? singleImage = await _picker.pickImage(
            source: ImageSource.gallery,
            maxWidth: 800,
            maxHeight: 600,
            imageQuality: 85,
          );
          if (singleImage != null) {
            pickedImages = [singleImage];
          }
        } else {
          rethrow;
        }
      }

      if (pickedImages.isEmpty) {
        return;
      }

      const int maxImagesAllowed = 6;
      final bool exceededLimit = pickedImages.length > maxImagesAllowed;
      final List<XFile> limitedImages =
          pickedImages.take(maxImagesAllowed).toList();

      if (kIsWeb) {
        final List<Uint8List> bytesList = [];
        for (final image in limitedImages) {
          bytesList.add(await image.readAsBytes());
        }

        setState(() {
          _webImageFiles
            ..clear()
            ..addAll(limitedImages);
          _webImageBytes
            ..clear()
            ..addAll(bytesList);
          _selectedImages.clear();
        });
      } else {
        setState(() {
          _selectedImages
            ..clear()
            ..addAll(limitedImages.map((image) => File(image.path)));
          _webImageFiles.clear();
          _webImageBytes.clear();
        });
      }

      if (exceededLimit && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You can upload up to 6 images only.')),
        );
      }

      print('Images selected: ${limitedImages.length}');
    } catch (e) {
      print('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error picking image: $e')));
      }
    }
  }

  bool get _hasSelectedImages =>
      _selectedImages.isNotEmpty || _webImageFiles.isNotEmpty;

  File? get _primaryLocalImage =>
      _selectedImages.isNotEmpty ? _selectedImages.first : null;

  Uint8List? get _primaryWebImageBytes =>
      _webImageBytes.isNotEmpty ? _webImageBytes.first : null;

  Widget _buildPrimaryImagePreview() {
    final colorScheme = Theme.of(context).colorScheme;
    if (kIsWeb && _primaryWebImageBytes != null) {
      return Image.memory(
        _primaryWebImageBytes!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }

    if (_primaryLocalImage != null) {
      return Image.file(
        _primaryLocalImage!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }

    return Container(
      color: colorScheme.surfaceContainerHighest,
      child: Icon(Icons.error, color: colorScheme.onSurfaceVariant),
    );
  }

  Widget _buildImagePreviews() {
    if (!_hasSelectedImages) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 120,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: kIsWeb ? _webImageBytes.length : _selectedImages.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Stack(
              children: [
                GestureDetector(
                  onTap: () => _showImagePreview(index),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8.0),
                    child: SizedBox(
                      width: 120,
                      height: 120,
                      child:
                          kIsWeb
                              ? Image.memory(
                                _webImageBytes[index],
                                fit: BoxFit.cover,
                              )
                              : Image.file(
                                _selectedImages[index],
                                fit: BoxFit.cover,
                              ),
                    ),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: GestureDetector(
                    onTap: () => _removeImage(index),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.scrim.withValues(alpha: 0.54),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.close,
                        color: Theme.of(context).colorScheme.onInverseSurface,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _removeImage(int index) {
    setState(() {
      if (kIsWeb) {
        _webImageBytes.removeAt(index);
        _webImageFiles.removeAt(index);
      } else {
        _selectedImages.removeAt(index);
      }
    });
  }

  void _showImagePreview(int index) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          child: SizedBox(
            width: MediaQuery.of(context).size.width * 0.9,
            height: MediaQuery.of(context).size.height * 0.7,
            child:
                kIsWeb
                    ? Image.memory(_webImageBytes[index], fit: BoxFit.contain)
                    : Image.file(_selectedImages[index], fit: BoxFit.contain),
          ),
        );
      },
    );
  }

  // ignore: unused_element
  Future<void> _showCapacityPicker() async {
    final initialIndex = _capacityOptions.indexOf(_selectedCapacity);
    final initialItem = initialIndex >= 0 ? initialIndex : 0;
    int tempSelection = _selectedCapacity;

    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: 280,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: 16.0),
                  child: Text(
                    'Select Roommates Count',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: CupertinoPicker(
                    scrollController: FixedExtentScrollController(
                      initialItem: initialItem,
                    ),
                    magnification: 1.05,
                    squeeze: 1.1,
                    itemExtent: 38,
                    useMagnifier: true,
                    onSelectedItemChanged: (index) {
                      tempSelection = _capacityOptions[index];
                    },
                    children:
                        _capacityOptions
                            .map(
                              (value) => Center(
                                child: Text(
                                  value.toString(),
                                  style: const TextStyle(fontSize: 18),
                                ),
                              ),
                            )
                            .toList(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          style: OutlinedButton.styleFrom(
                            foregroundColor:
                                Theme.of(context).colorScheme.onSurface,
                            side: BorderSide(
                              color:
                                  Theme.of(context).colorScheme.outlineVariant,
                            ),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _selectedCapacity = tempSelection;
                              _capacityController.text =
                                  _selectedCapacity.toString();
                            });
                            Navigator.pop(sheetContext);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                Theme.of(context).colorScheme.primary,
                            foregroundColor:
                                Theme.of(context).colorScheme.onPrimary,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Done'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _updateAddressFromCoordinates(double lat, double lng) async {
    try {
      print('Starting address conversion for: $lat, $lng');

      // Update coordinates first
      setState(() {
        _latitude = lat;
        _longitude = lng;
      });

      // Show loading state
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Converting coordinates to address...'),
            duration: Duration(seconds: 1),
          ),
        );
      }

      final address = await _geocodingService.coordinatesToAddress(lat, lng);
      final locationData = await _geocodingService.coordinatesToLocationData(
        lat,
        lng,
      );

      print('Converted address: $address');
      print(
        'LocationData: ${locationData.city}, ${locationData.state}, ${locationData.pincode}',
      );

      final street =
          locationData.address.isNotEmpty ? locationData.address : address;

      setState(() {
        _addressController.text = street;
        _cityController.text = locationData.city;
        _stateController.text = locationData.state;
        _pincodeController.text = locationData.pincode;
      });

      // Show success message with actual data
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Address: ${locationData.city}, ${locationData.state}',
            ),
            backgroundColor: Theme.of(context).colorScheme.primary,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('Error converting coordinates to address: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Geocoding failed: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _openLocationPicker() async {
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (context) => MapPickerScreen(
                onLocationSelected: (address, lat, lng) {
                  _updateAddressFromCoordinates(lat, lng);
                },
              ),
        ),
      );
    } catch (e) {
      print('Error opening location picker: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening location picker: $e')),
        );
      }
    }
  }

  void _createGroup() async {
    if (_groupNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter a room name')));
      return;
    }

    final streetText = _addressController.text.trim();
    if (streetText.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a location')));
      return;
    }

    if (_rentAmountController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter rent amount')));
      return;
    }

    if (_capacityController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select room capacity')),
      );
      return;
    }

    if (_advanceAmountController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter advance amount')),
      );
      return;
    }

    if (_selectedImages.isEmpty && _webImageFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload at least one image')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Prepare the enhanced room data
      final rentAmount =
          double.tryParse(_rentAmountController.text.trim()) ?? 0.0;
      final advanceAmount =
          double.tryParse(_advanceAmountController.text.trim()) ?? 0.0;
      final locationParts =
          <String>[
            streetText,
            _cityController.text.trim(),
            _stateController.text.trim(),
            _pincodeController.text.trim(),
          ].where((part) => part.isNotEmpty).toList();
      final combinedLocation = locationParts.join(', ');

      final groupId = await _groupsService.createGroup(
        name: _groupNameController.text.trim(),
        description: _descriptionController.text.trim(),
        location: combinedLocation.isNotEmpty ? combinedLocation : streetText,
        lat: _latitude,
        lng: _longitude,
        memberCount: 1,
        maxMembers: _selectedCapacity,
        rentAmount: rentAmount,
        rentCurrency: _selectedCurrency,
        advanceAmount: advanceAmount,
        roomType: _selectedRoomType,
        amenities: _selectedAmenities,
        imageFiles: _selectedImages,
        webPickedFiles: _webImageFiles,
      );

      if (groupId != null) {
        print('Room created successfully with ID: $groupId');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Room created successfully!'),
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
          );
          Navigator.pop(context);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Database connection failed. Please check your internet and try again.',
              ),
              backgroundColor: Theme.of(context).colorScheme.error,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      print('Error creating room: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('An unexpected error occurred: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _pincodeController.dispose();
    _rentAmountController.dispose();
    _advanceAmountController.dispose();
    _capacityController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Widget _buildCleanTextField({
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
    TextInputType? keyboardType,
    Widget? suffixIcon,
    bool readOnly = false,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant, width: 1),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        readOnly: readOnly,
        onTap: readOnly ? onTap : null,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 16,
            fontWeight: FontWeight.w400,
          ),
          border: InputBorder.none,
          suffixIcon: suffixIcon,
          contentPadding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: maxLines > 1 ? 16 : 18,
          ),
        ),
        style: TextStyle(color: colorScheme.onSurface, fontSize: 16),
      ),
    );
  }

  Widget _buildCleanDropdown<T>({
    required T value,
    required String hint,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant, width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: DropdownButton<T>(
        value: value,
        hint: Text(
          hint,
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 16,
            fontWeight: FontWeight.w400,
          ),
        ),
        isExpanded: true,
        underline: const SizedBox(),
        icon: Icon(
          Icons.keyboard_arrow_down,
          color: colorScheme.onSurfaceVariant,
        ),
        dropdownColor: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        items: items,
        onChanged: onChanged,
        style: TextStyle(color: colorScheme.onSurface, fontSize: 16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.06, vertical: screenHeight * 0.03),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Page Title
              Text(
                'Create Group',
                style: textTheme.headlineSmall?.copyWith(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              SizedBox(height: screenHeight * 0.03),

              // Enhanced Image Picker
              GestureDetector(
                onTap: _pickImages,
                child: CustomPaint(
                  painter: DashedBorderPainter(
                    color: colorScheme.outlineVariant,
                  ),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      child:
                          _hasSelectedImages
                              ? ClipRRect(
                                borderRadius: BorderRadius.circular(11.0),
                                child: _buildPrimaryImagePreview(),
                              )
                              : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.cloud_upload_outlined,
                                    size: screenWidth * 0.12,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  SizedBox(height: screenHeight * 0.01),
                                  Text(
                                    'Upload Room Images',
                                    style: textTheme.bodyMedium?.copyWith(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  SizedBox(height: screenHeight * 0.005),
                                  Text(
                                    'Supports: JPG, PNG, JPEG (max 6)',
                                    style: textTheme.bodySmall?.copyWith(
                                      fontSize: 12,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: screenHeight * 0.02),

              // Image Previews
              _buildImagePreviews(),

              SizedBox(height: screenHeight * 0.03),

              // Group Name
              Text(
                'Group Name',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              SizedBox(height: screenHeight * 0.01),
              _buildCleanTextField(
                controller: _groupNameController,
                hint: 'Enter a name for your group',
              ),
              SizedBox(height: screenHeight * 0.02),

              // Description
              Text(
                'Description',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              SizedBox(height: screenHeight * 0.01),
              _buildCleanTextField(
                controller: _descriptionController,
                hint: 'Enter a brief description',
                maxLines: 3,
              ),
              SizedBox(height: screenHeight * 0.02),

              // Room Type
              Text(
                'Room Type',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              SizedBox(height: screenHeight * 0.01),
              _buildCleanDropdown<String>(
                value: _selectedRoomType,
                hint: 'Select Room Type',
                items:
                    _roomTypes.map((String type) {
                      return DropdownMenuItem<String>(
                        value: type,
                        child: Text(type),
                      );
                    }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedRoomType = newValue!;
                  });
                },
              ),
              SizedBox(height: screenHeight * 0.02),

              // Location
              Text(
                'Location',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              SizedBox(height: screenHeight * 0.01),
              _buildCleanTextField(
                controller: _addressController,
                hint: 'Enter address or pick from map',
                readOnly: false,
                suffixIcon: InkWell(
                  onTap: _openLocationPicker,
                  child: Icon(
                    Icons.location_on_outlined,
                    color: colorScheme.primary,
                    size: screenWidth * 0.055,
                  ),
                ),
              ),
              SizedBox(height: screenHeight * 0.02),

              // Location Details Row
              Row(
                children: [
                  Expanded(
                    child: _buildCleanTextField(
                      controller: _cityController,
                      hint: 'City',
                    ),
                  ),
                  SizedBox(width: screenWidth * 0.03),
                  Expanded(
                    child: _buildCleanTextField(
                      controller: _stateController,
                      hint: 'State',
                    ),
                  ),
                ],
              ),
              SizedBox(height: screenHeight * 0.02),

              _buildCleanTextField(
                controller: _pincodeController,
                hint: 'Pincode',
                keyboardType: TextInputType.number,
              ),
              SizedBox(height: screenHeight * 0.02),

              // Rent, Currency, and Roommates Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Rent Amount',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        SizedBox(height: screenHeight * 0.01),
                        _buildCleanTextField(
                          controller: _rentAmountController,
                          hint: 'Enter monthly...',
                          keyboardType: TextInputType.number,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: screenWidth * 0.03),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Advance Amount',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        SizedBox(height: screenHeight * 0.01),
                        _buildCleanTextField(
                          controller: _advanceAmountController,
                          hint: 'Enter refundable dep',
                          keyboardType: TextInputType.number,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: screenHeight * 0.02),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Currency',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        SizedBox(height: screenHeight * 0.01),
                        _buildCleanDropdown<String>(
                          value: _selectedCurrency,
                          hint: 'Currency',
                          items:
                              _currencies.map((String currency) {
                                return DropdownMenuItem<String>(
                                  value: currency,
                                  child: Text(currency),
                                );
                              }).toList(),
                          onChanged: (String? newValue) {
                            setState(() {
                              _selectedCurrency = newValue!;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: screenWidth * 0.03),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Roommates',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        SizedBox(height: screenHeight * 0.01),
                        _buildCleanTextField(
                          controller: _capacityController,
                          hint: 'Enter count',
                          keyboardType: TextInputType.number,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: screenHeight * 0.02),

              // Amenities Section
              Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.outlineVariant,
                    width: 1,
                  ),
                ),
                padding: EdgeInsets.all(screenWidth * 0.04),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Amenities',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.015),
                    Wrap(
                      spacing: screenWidth * 0.02,
                      runSpacing: screenHeight * 0.01,
                      children:
                          _availableAmenities.map((amenity) {
                            final isSelected = _selectedAmenities.contains(
                              amenity,
                            );
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  if (isSelected) {
                                    _selectedAmenities.remove(amenity);
                                  } else {
                                    _selectedAmenities.add(amenity);
                                  }
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      isSelected
                                          ? colorScheme.primary
                                          : colorScheme.surface,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color:
                                        isSelected
                                            ? colorScheme.primary
                                            : colorScheme.outlineVariant,
                                  ),
                                ),
                                child: Text(
                                  amenity,
                                  style: TextStyle(
                                    color:
                                        isSelected
                                            ? colorScheme.onPrimary
                                            : colorScheme.onSurfaceVariant,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),

              // Create Group Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _createGroup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    disabledBackgroundColor: colorScheme.onSurface.withValues(
                      alpha: 0.12,
                    ),
                  ),
                  child:
                      _isLoading
                          ? SizedBox(
                            height: screenWidth * 0.05,
                            width: screenWidth * 0.05,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                colorScheme.onPrimary,
                              ),
                            ),
                          )
                          : const Text(
                            'Create Room',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
