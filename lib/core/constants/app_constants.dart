/// App Constants
/// Contains all the constant values used throughout the application
class AppConstants {
  // API URLs
  static const String cloudinaryBaseUrl =
      'https://res.cloudinary.com/cloud-roomie';

  // Firebase Collections
  static const String usersCollection = 'users';
  static const String groupsCollection = 'groups';
  static const String expensesCollection = 'expenses';
  static const String notificationsCollection = 'notifications';

  // Firebase Realtime Database Paths
  static const String individualChatsPath = 'individualChats';
  static const String groupChatsPath = 'groupChats';
  static const String messagesPath = 'messages';

  // App Strings
  static const String appName = 'Roomie';
  static const String appVersion = '1.0.0';

  // Image Settings
  static const int maxImageWidth = 1024;
  static const int maxImageHeight = 1024;
  static const int imageQuality = 85;

  // Chat Settings
  static const int maxMessageLength = 500;
  static const int messagesPerPage = 50;

  // Location Settings
  static const double defaultLocationRadius = 10.0; // in kilometers

  // Validation
  static const int minUsernameLength = 3;
  static const int maxUsernameLength = 20;
  static const int minPasswordLength = 6;
  static const int maxBioLength = 150;

  // Timeouts
  static const Duration networkTimeout = Duration(seconds: 30);
  static const Duration cacheTimeout = Duration(minutes: 5);
}
