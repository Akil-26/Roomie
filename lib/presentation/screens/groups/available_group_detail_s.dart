import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:roomie/data/datasources/auth_service.dart';
import 'package:roomie/data/datasources/groups_service.dart';

class AvailableGroupDetailScreen extends StatefulWidget {
  final Map<String, dynamic> group;

  const AvailableGroupDetailScreen({super.key, required this.group});

  @override
  State<AvailableGroupDetailScreen> createState() =>
      _AvailableGroupDetailScreenState();
}

class _AvailableGroupDetailScreenState
    extends State<AvailableGroupDetailScreen> {
  final GroupsService _groupsService = GroupsService();
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  final PageController _pageController = PageController();
  int _currentImageIndex = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return 'N/A';
    return DateFormat.yMMMd().format(timestamp.toDate());
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  String _currencySymbol(String currency) {
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

  String _formatRent(double amount, String currency) {
    if (amount <= 0) return 'Not specified';
    final formatter = NumberFormat.compactCurrency(
      symbol: _currencySymbol(currency),
      decimalDigits: 0,
    );
    return '${formatter.format(amount)}/month';
  }

  String _formatAdvance(double amount, String currency) {
    if (amount <= 0) return 'No advance';
    final formatter = NumberFormat.compactCurrency(
      symbol: _currencySymbol(currency),
      decimalDigits: 0,
    );
    return '${formatter.format(amount)} deposit';
  }

  Future<void> _requestToJoin() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final currentUser = _authService.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      final success = await _groupsService.sendJoinRequest(widget.group['id']);

      if (success && mounted) {
        final colorScheme = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Join request sent successfully!'),
            backgroundColor: colorScheme.primary,
          ),
        );
        Navigator.pop(context);
      } else {
        throw Exception('Failed to send join request');
      }
    } catch (e) {
      print('Error sending join request: $e');
      if (mounted) {
        final colorScheme = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: colorScheme.error,
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
  Widget build(BuildContext context) {
    final List<String> images = List<String>.from(widget.group['images'] ?? []);
    final bool hasImages = images.isNotEmpty;
    final dynamic rentRaw = widget.group['rent'];
    double rentAmount = _toDouble(widget.group['rentAmount']);
    String rentCurrency = (widget.group['rentCurrency'] ?? '').toString();
    double advanceAmount = _toDouble(widget.group['advanceAmount']);

    if (rentAmount == 0 && rentRaw != null) {
      if (rentRaw is Map<String, dynamic>) {
        rentAmount = _toDouble(rentRaw['amount']);
      } else if (rentRaw is num || rentRaw is String) {
        rentAmount = _toDouble(rentRaw);
      }
    }

    if (rentCurrency.isEmpty && rentRaw is Map<String, dynamic>) {
      rentCurrency = (rentRaw['currency'] ?? 'INR').toString();
    }
    if (rentCurrency.isEmpty) {
      rentCurrency = 'INR';
    }

    if (advanceAmount == 0 && rentRaw is Map<String, dynamic>) {
      advanceAmount = _toDouble(rentRaw['advanceAmount']);
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: screenHeight * 0.35,  // 35% of screen height
            backgroundColor: colorScheme.surface,
            elevation: 0,
            pinned: true,
            stretch: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Hero(
                tag: 'group-image-${widget.group['id']}',
                child:
                    hasImages
                        ? _buildImageSlider(images)
                        : _buildPlaceholderImage(),
              ),
            ),
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: colorScheme.onSurface),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          SliverToBoxAdapter(
            child: Container(
              padding: EdgeInsets.all(screenWidth * 0.05),  // 5% padding
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          widget.group['name'] ?? 'Unnamed Group',
                          style: textTheme.headlineSmall?.copyWith(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                      SizedBox(width: screenWidth * 0.04),  // 4% gap
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: screenWidth * 0.03,
                          vertical: screenHeight * 0.007,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Available',
                          style: textTheme.labelSmall?.copyWith(
                            fontSize: 12,
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: screenHeight * 0.02),  // 2% gap
                  Text(
                    widget.group['description'] ?? 'No description available.',
                    style: textTheme.bodyLarge?.copyWith(
                      fontSize: 16,
                      color: colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.03),  // 3% gap
                  Divider(height: 1, color: colorScheme.outlineVariant),
                  SizedBox(height: screenHeight * 0.03),  // 3% gap
                  _buildFullWidthInfoCard(
                    icon: Icons.location_on_outlined,
                    title: 'Location',
                    value: widget.group['location'] ?? 'Not specified',
                    color: colorScheme.primary,
                  ),
                  SizedBox(height: screenHeight * 0.02),  // 2% gap
                  Row(
                    children: [
                      Expanded(
                        child: _buildInfoCard(
                          icon: Icons.attach_money,
                          title: 'Rent',
                          value: _formatRent(rentAmount, rentCurrency),
                          color: colorScheme.primary,
                        ),
                      ),
                      SizedBox(width: screenWidth * 0.04),  // 4% gap
                      Expanded(
                        child: _buildInfoCard(
                          icon: Icons.account_balance_wallet_outlined,
                          title: 'Advance',
                          value: _formatAdvance(advanceAmount, rentCurrency),
                          color: colorScheme.tertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildInfoCard(
                          icon: Icons.group_outlined,
                          title: 'Roommates',
                          value:
                              '${widget.group['memberCount'] ?? 0} / ${widget.group['capacity']?.toString() ?? 'N/A'}',
                          color: colorScheme.secondaryContainer,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildInfoCard(
                          icon: Icons.home_outlined,
                          title: 'Room Type',
                          value: widget.group['roomType'] ?? 'N/A',
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: screenHeight * 0.02),  // 2% gap
                  _buildInfoCard(
                    icon: Icons.calendar_today_outlined,
                    title: 'Created On',
                    value: _formatTimestamp(
                      widget.group['createdAt'] as Timestamp?,
                    ),
                    color: colorScheme.tertiary,
                  ),
                  SizedBox(height: screenHeight * 0.03),  // 3% gap
                  if (widget.group['amenities'] != null &&
                      (widget.group['amenities'] as List).isNotEmpty) ...[
                    Text(
                      'Amenities',
                      style: textTheme.titleLarge?.copyWith(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                    ),
                    SizedBox(height: screenHeight * 0.015),  // 1.5% gap
                    _buildAmenitiesGrid(
                      List<String>.from(widget.group['amenities']),
                    ),
                    SizedBox(height: screenHeight * 0.03),  // 3% gap
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(
          screenWidth * 0.05,  // 5% left
          screenHeight * 0.012,  // 1.2% top
          screenWidth * 0.05,  // 5% right
          screenHeight * 0.025,  // 2.5% bottom
        ),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(
            top: BorderSide(color: colorScheme.outlineVariant, width: 1),
          ),
        ),
        child: SizedBox(
          width: double.infinity,
          height: screenHeight * 0.065,  // 6.5% height
          child: ElevatedButton(
            onPressed: _isLoading ? null : _requestToJoin,
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  _isLoading ? colorScheme.outline : colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              disabledBackgroundColor: colorScheme.outlineVariant,
            ),
            child:
                _isLoading
                    ? SizedBox(
                      height: screenWidth * 0.06,  // 6% size
                      width: screenWidth * 0.06,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          colorScheme.onPrimary,
                        ),
                      ),
                    )
                    : const Text(
                      'Request to Join',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
          ),
        ),
      ),
    );
  }

  Widget _buildImageSlider(List<String> images) {
    return Stack(
      children: [
        PageView.builder(
          controller: _pageController,
          itemCount: images.length,
          onPageChanged: (index) {
            setState(() {
              _currentImageIndex = index;
            });
          },
          itemBuilder: (context, index) {
            return Image.network(
              images[index],
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return _buildPlaceholderImage();
              },
            );
          },
        ),
        if (images.length > 1)
          Positioned(
            bottom: 10,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(images.length, (index) {
                final colorScheme = Theme.of(context).colorScheme;
                return Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        _currentImageIndex == index
                            ? colorScheme.onInverseSurface
                            : colorScheme.onInverseSurface.withValues(
                              alpha: 0.5,
                            ),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }

  Widget _buildPlaceholderImage() {
    final screenWidth = MediaQuery.of(context).size.width;
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.group, color: colorScheme.onSurfaceVariant, size: screenWidth * 0.15),  // 15% icon
      ),
    );
  }

  Widget _buildAmenitiesGrid(List<String> amenities) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Wrap(
      spacing: screenWidth * 0.02,  // 2% spacing
      runSpacing: screenHeight * 0.01,  // 1% run spacing
      children:
          amenities.map((amenity) {
            return Container(
              padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.03, vertical: screenHeight * 0.007),  // Dynamic padding
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Text(
                amenity,
                style: textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
            );
          }).toList(),
    );
  }

  Widget _buildFullWidthInfoCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: EdgeInsets.all(screenWidth * 0.04),  // 4% padding
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.05),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: screenWidth * 0.055),  // 5.5% icon
          SizedBox(width: screenWidth * 0.03),  // 3% gap
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: textTheme.bodyMedium?.copyWith(
                    fontSize: 14,
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: screenHeight * 0.005),  // 0.5% gap
                Text(
                  value,
                  style: textTheme.titleMedium?.copyWith(
                    fontSize: 16,
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: EdgeInsets.all(screenWidth * 0.04),  // 4% padding
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.05),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: screenWidth * 0.055),  // 5.5% icon
              SizedBox(width: screenWidth * 0.02),  // 2% gap
              Text(
                title,
                style: textTheme.bodyMedium?.copyWith(
                  fontSize: 14,
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          SizedBox(height: screenHeight * 0.01),  // 1% gap
          Text(
            value,
            style: textTheme.titleMedium?.copyWith(
              fontSize: 16,
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
