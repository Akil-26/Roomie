/// Custom Exception Classes
/// Provides structured error handling throughout the application
library;

/// Base exception class for all app-specific exceptions
abstract class AppException implements Exception {
  final String message;
  final String? code;

  const AppException(this.message, [this.code]);

  @override
  String toString() =>
      'AppException: $message${code != null ? ' (Code: $code)' : ''}';
}

/// Authentication related exceptions
class AuthException extends AppException {
  const AuthException(super.message, [super.code]);
}

/// Network related exceptions
class NetworkException extends AppException {
  const NetworkException(super.message, [super.code]);
}

/// Firestore related exceptions
class FirestoreException extends AppException {
  const FirestoreException(super.message, [super.code]);
}

/// Chat related exceptions
class ChatException extends AppException {
  const ChatException(super.message, [super.code]);
}

/// File/Image related exceptions
class FileException extends AppException {
  const FileException(super.message, [super.code]);
}

/// Validation exceptions
class ValidationException extends AppException {
  const ValidationException(super.message, [super.code]);
}

/// Location related exceptions
class LocationException extends AppException {
  const LocationException(super.message, [super.code]);
}

/// Permission related exceptions
class PermissionException extends AppException {
  const PermissionException(super.message, [super.code]);
}

/// Cache related exceptions
class CacheException extends AppException {
  const CacheException(super.message, [super.code]);
}

/// Server related exceptions
class ServerException extends AppException {
  const ServerException(super.message, [super.code]);
}

/// Common exception messages
class ExceptionMessages {
  // Auth
  static const String invalidCredentials = 'Invalid email or password';
  static const String userNotFound = 'User not found';
  static const String emailAlreadyInUse = 'Email is already in use';
  static const String weakPassword = 'Password is too weak';
  static const String userDisabled = 'User account has been disabled';
  static const String tooManyRequests =
      'Too many login attempts. Please try again later';
  static const String operationNotAllowed = 'Operation not allowed';
  static const String invalidEmail = 'Invalid email address';

  // Network
  static const String noInternet = 'No internet connection';
  static const String requestTimeout = 'Request timeout';
  static const String serverError = 'Server error occurred';
  static const String badRequest = 'Bad request';
  static const String unauthorized = 'Unauthorized access';
  static const String forbidden = 'Access forbidden';
  static const String notFound = 'Resource not found';

  // Firestore
  static const String documentNotFound = 'Document not found';
  static const String permissionDenied = 'Permission denied';
  static const String unavailable = 'Service unavailable';
  static const String alreadyExists = 'Document already exists';
  static const String aborted = 'Operation aborted';
  static const String outOfRange = 'Value out of range';
  static const String unimplemented = 'Operation not implemented';
  static const String internal = 'Internal error';
  static const String dataLoss = 'Data loss occurred';

  // File/Image
  static const String fileNotFound = 'File not found';
  static const String invalidFileFormat = 'Invalid file format';
  static const String fileTooLarge = 'File size too large';
  static const String uploadFailed = 'File upload failed';
  static const String downloadFailed = 'File download failed';

  // Validation
  static const String requiredField = 'This field is required';
  static const String invalidFormat = 'Invalid format';
  static const String tooShort = 'Value is too short';
  static const String tooLong = 'Value is too long';
  static const String invalidCharacters = 'Contains invalid characters';

  // Location
  static const String locationPermissionDenied = 'Location permission denied';
  static const String locationServiceDisabled = 'Location service is disabled';
  static const String locationUnavailable = 'Location unavailable';

  // Cache
  static const String cacheError = 'Cache error occurred';
  static const String cacheExpired = 'Cache has expired';

  // General
  static const String unknownError = 'An unknown error occurred';
  static const String operationFailed = 'Operation failed';
  static const String invalidState = 'Invalid state';
  static const String notInitialized = 'Not initialized';
}
