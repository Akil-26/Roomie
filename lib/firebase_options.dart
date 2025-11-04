import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter_dotenv/flutter_dotenv.dart';

String _env(String key) {
  try {
    final value = dotenv.env[key] ?? dotenv.env['FIREBASE_API_KEY'];
    if (value != null && value.isNotEmpty) {
      return value;
    }
  } catch (e) {
    // dotenv not loaded, use fallback
  }

  // SECURITY: No hardcoded API keys! Must be provided via environment variables
  throw Exception(
    'Firebase API key not found! Please set FIREBASE_API_KEY in your .env file',
  );
}

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static final FirebaseOptions android = FirebaseOptions(
    apiKey: _env('FIREBASE_API_KEY'),
    appId: '1:1066645245892:android:f8abb05603ffd67fe81e91',
    messagingSenderId: '1066645245892',
    projectId: 'roomie-cfc03',
    databaseURL: 'https://roomie-cfc03-default-rtdb.firebaseio.com/',
    storageBucket: 'roomie-cfc03.firebasestorage.app',
  );

  static final FirebaseOptions ios = FirebaseOptions(
    apiKey: _env('FIREBASE_API_KEY'),
    appId: '1:1066645245892:ios:8f0a91a844f187fee81e91',
    messagingSenderId: '1066645245892',
    projectId: 'roomie-cfc03',
    databaseURL: 'https://roomie-cfc03-default-rtdb.firebaseio.com/',
    storageBucket: 'roomie-cfc03.firebasestorage.app',
    androidClientId:
        '1066645245892-uj54e0j951ah54a8msqr05h34seoetkc.apps.googleusercontent.com',
    iosClientId:
        '1066645245892-ifm2s1tj55tigfdndb1n4tr2ua2qj6eo.apps.googleusercontent.com',
    iosBundleId: 'com.example.roomie',
  );

  static final FirebaseOptions web = FirebaseOptions(
    apiKey: _env('FIREBASE_API_KEY'),
    appId: '1:1066645245892:web:462cf265fd241a9de81e91',
    messagingSenderId: '1066645245892',
    projectId: 'roomie-cfc03',
    authDomain: 'roomie-cfc03.firebaseapp.com',
    databaseURL: 'https://roomie-cfc03-default-rtdb.firebaseio.com/',
    storageBucket: 'roomie-cfc03.firebasestorage.app',
    measurementId: 'G-CLXKM3E66E',
  );

  static final FirebaseOptions windows = FirebaseOptions(
    apiKey: _env('FIREBASE_API_KEY'),
    appId: '1:1066645245892:web:015767bf67bd8955e81e91',
    messagingSenderId: '1066645245892',
    projectId: 'roomie-cfc03',
    authDomain: 'roomie-cfc03.firebaseapp.com',
    databaseURL: 'https://roomie-cfc03-default-rtdb.firebaseio.com/',
    storageBucket: 'roomie-cfc03.firebasestorage.app',
    measurementId: 'G-CLXKM3E66E',
  );
}
