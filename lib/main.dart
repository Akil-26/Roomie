import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:roomie/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:roomie/presentation/screens/auth/login_s.dart';
import 'package:roomie/presentation/screens/home/home_s.dart';
import 'package:roomie/presentation/screens/profile/user_profile_s.dart';
import 'package:roomie/presentation/screens/onboarding/permissions_onboarding_s.dart';
import 'package:roomie/data/datasources/auth_service.dart';
import 'package:roomie/presentation/widgets/auth_wrapper.dart';
import 'package:roomie/data/datasources/notification_service.dart';
import 'package:roomie/presentation/screens/chat/chat_screen.dart';
import 'package:roomie/core/core.dart';
import 'package:roomie/core/logger.dart';
import 'package:roomie/data/datasources/local_sms_transaction_store.dart';
import 'package:roomie/data/datasources/sms_transaction_service.dart';

// Global navigator key for notification deep-linking
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  AppLogger.d('📱 App starting...');

  // Load environment variables with fallback
  try {
    await dotenv.load(fileName: ".env");
    AppLogger.d('✅ Environment variables loaded');
  } catch (e) {
    AppLogger.e('❌ Environment variables failed', e);
    AppLogger.d('🔧 Using hardcoded Firebase config for mobile');
  }

  // Initialize Firebase with error handling and duplicate-app guard
  try {
    if (Firebase.apps.isEmpty) {
      AppLogger.d('ℹ️ No Firebase apps found. Initializing default app...');
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      AppLogger.d('✅ Firebase initialized successfully');
    } else {
      // Reuse existing app (common after hot restart)
      AppLogger.d(
        'ℹ️ Firebase already initialized. Apps count: ${Firebase.apps.length}',
      );
    }
  } on FirebaseException catch (e) {
    if (e.code == 'duplicate-app') {
      // Safe to ignore and continue using the existing default app
      AppLogger.d(
        '⚠️ Firebase default app already exists; reusing existing instance.',
      );
    } else {
      AppLogger.e('❌ Firebase initialization failed: [${e.code}] ${e.message}');
      AppLogger.d(
        '🔧 App will continue to boot, but Firebase features may be unavailable.',
      );
    }
  } catch (e) {
    AppLogger.e('❌ Firebase initialization failed (unexpected): $e');
    AppLogger.d(
      '🔧 App will continue to boot, but Firebase features may be unavailable.',
    );
  }

  // Initialize notifications with navigator key
  try {
    NotificationService().setNavigatorKey(navigatorKey);
    await NotificationService().initialize();
    AppLogger.d('✅ Notifications initialized');
  } catch (e) {
    AppLogger.e('❌ Notifications failed: $e');
  }

  // Initialize local encrypted storage (Hive) for SMS transactions
  try {
    await LocalSmsTransactionStore().init();
    AppLogger.d('✅ Local SMS transaction store initialized');
  } catch (e) {
    AppLogger.e('❌ Local store init failed: $e');
  }

  // Configure SMS service for local-only, privacy-preserving storage
  try {
    final smsService = SmsTransactionService();
    smsService.setPersistRemoteTransactions(false); // local-only
    smsService.setStorePlainRawMessage(false);      // keep hashed raw SMS
    AppLogger.d('🔒 SMS service configured: local-only, hashed raw messages');
  } catch (e) {
    AppLogger.e('❌ SMS service configuration failed: $e');
  }

  AppLogger.d('🚀 Starting Roomie App (Firestore + Cloudinary mode)...');

  runApp(
    MultiProvider(
      providers: [
        Provider<AuthService>(create: (_) => AuthService()),
        // Add other services here
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Roomie',
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      onGenerateRoute: (settings) {
        // Handle deep-link routes with parameters
        if (settings.name?.startsWith('/chat/') == true) {
          final chatId = settings.name!.replaceFirst('/chat/', '');
          return MaterialPageRoute(
            builder: (context) => ChatScreen(
              chatData: {'id': chatId},
              chatType: 'individual', // Will be determined from chatId
            ),
          );
        }
        return null; // Use regular routes
      },
      routes: {
        '/': (context) => const AuthWrapper(),
        '/home': (context) => const HomeScreen(),
        '/login': (context) => const PhoneLoginScreen(),
        '/profile': (context) => const UserProfileScreen(),
        '/permissions-onboarding': (context) => const PermissionsOnboardingScreen(),
      },
      theme: AppThemes.lightTheme,
      darkTheme: AppThemes.darkTheme,
      themeMode: ThemeMode.system,
    );
  }
}