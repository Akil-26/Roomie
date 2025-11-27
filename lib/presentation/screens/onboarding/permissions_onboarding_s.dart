import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionsOnboardingScreen extends StatefulWidget {
  const PermissionsOnboardingScreen({super.key});

  @override
  State<PermissionsOnboardingScreen> createState() => _PermissionsOnboardingScreenState();
}

class _PermissionsOnboardingScreenState extends State<PermissionsOnboardingScreen> {
  bool _notificationGranted = false;
  bool _locationGranted = false;
  bool _smsGranted = false;
  bool _isRequesting = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    // Check notification permission
    final notificationStatus = await FirebaseMessaging.instance.getNotificationSettings();
    final notificationGranted = notificationStatus.authorizationStatus == AuthorizationStatus.authorized ||
        notificationStatus.authorizationStatus == AuthorizationStatus.provisional;

    // Check location permission
    final locationPermission = await Geolocator.checkPermission();
    final locationGranted = locationPermission == LocationPermission.always ||
        locationPermission == LocationPermission.whileInUse;

    // Check SMS permission
    final smsStatus = await Permission.sms.status;
    final smsGranted = smsStatus.isGranted;

    if (mounted) {
      setState(() {
        _notificationGranted = notificationGranted;
        _locationGranted = locationGranted;
        _smsGranted = smsGranted;
      });
    }
  }

  Future<void> _requestAllPermissions() async {
    setState(() => _isRequesting = true);

    // Request notification permission
    if (!_notificationGranted) {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      _notificationGranted = settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    }

    // Request location permission
    if (!_locationGranted) {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      _locationGranted = permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    }

    // Request SMS permission
    if (!_smsGranted) {
      final status = await Permission.sms.request();
      _smsGranted = status.isGranted;
    }

    if (mounted) {
      setState(() => _isRequesting = false);
      _checkPermissions();
    }
  }

  void _continueToHome() {
    Navigator.pushNamedAndRemoveUntil(
      context,
      '/home',
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    final allGranted = _notificationGranted && _locationGranted && _smsGranted;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.06),
          child: Column(
            children: [
              SizedBox(height: screenHeight * 0.05),
              
              // Header
              Text(
                'Enable Permissions',
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: screenHeight * 0.01),
              Text(
                'To provide you the best experience, we need a few permissions',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              
              SizedBox(height: screenHeight * 0.05),
              
              // Permission cards
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _PermissionCard(
                        icon: Icons.notifications_outlined,
                        title: 'Notifications',
                        description: 'Stay updated with messages, expenses, and group activities',
                        isGranted: _notificationGranted,
                        colorScheme: cs,
                      ),
                      SizedBox(height: screenHeight * 0.02),
                      
                      _PermissionCard(
                        icon: Icons.location_on_outlined,
                        title: 'Location',
                        description: 'Find roommates nearby and share your location with your group',
                        isGranted: _locationGranted,
                        colorScheme: cs,
                      ),
                      SizedBox(height: screenHeight * 0.02),
                      
                      _PermissionCard(
                        icon: Icons.sms_outlined,
                        title: 'SMS (Optional)',
                        description: 'Automatically track your expenses from bank transaction messages',
                        isGranted: _smsGranted,
                        colorScheme: cs,
                        isOptional: true,
                      ),
                    ],
                  ),
                ),
              ),
              
              SizedBox(height: screenHeight * 0.02),
              
              // Action buttons
              if (!allGranted)
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: _isRequesting ? null : _requestAllPermissions,
                    icon: _isRequesting
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: cs.onPrimary,
                            ),
                          )
                        : const Icon(Icons.check_circle_outline),
                    label: Text(
                      _isRequesting ? 'Requesting...' : 'Grant Permissions',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              
              SizedBox(height: screenHeight * 0.015),
              
              SizedBox(
                width: double.infinity,
                height: 54,
                child: TextButton(
                  onPressed: _continueToHome,
                  style: TextButton.styleFrom(
                    foregroundColor: cs.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    allGranted ? 'Continue' : 'Skip for now',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              
              SizedBox(height: screenHeight * 0.02),
              
              // Privacy note
              Padding(
                padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.04),
                child: Text(
                  'You can change these permissions anytime in your device settings',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              
              SizedBox(height: screenHeight * 0.02),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool isGranted;
  final ColorScheme colorScheme;
  final bool isOptional;

  const _PermissionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.isGranted,
    required this.colorScheme,
    this.isOptional = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isGranted ? colorScheme.primaryContainer.withOpacity(0.3) : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isGranted ? colorScheme.primary : colorScheme.outlineVariant,
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isGranted ? colorScheme.primaryContainer : colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: isGranted ? colorScheme.primary : colorScheme.onSurfaceVariant,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    if (isOptional) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Optional',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Icon(
            isGranted ? Icons.check_circle : Icons.circle_outlined,
            color: isGranted ? colorScheme.primary : colorScheme.onSurfaceVariant,
            size: 28,
          ),
        ],
      ),
    );
  }
}
