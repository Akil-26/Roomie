/// Base failure class for error handling in the domain layer
abstract class Failure {
  final String message;
  final String? code;

  const Failure(this.message, [this.code]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Failure &&
          runtimeType == other.runtimeType &&
          message == other.message &&
          code == other.code;

  @override
  int get hashCode => message.hashCode ^ code.hashCode;

  @override
  String toString() =>
      'Failure: $message${code != null ? ' (Code: $code)' : ''}';
}

/// Authentication failures
class AuthFailure extends Failure {
  const AuthFailure(super.message, [super.code]);
}

/// Network failures
class NetworkFailure extends Failure {
  const NetworkFailure(super.message, [super.code]);
}

/// Server failures
class ServerFailure extends Failure {
  const ServerFailure(super.message, [super.code]);
}

/// Cache failures
class CacheFailure extends Failure {
  const CacheFailure(super.message, [super.code]);
}

/// Validation failures
class ValidationFailure extends Failure {
  const ValidationFailure(super.message, [super.code]);
}

/// Location failures
class LocationFailure extends Failure {
  const LocationFailure(super.message, [super.code]);
}

/// File operation failures
class FileFailure extends Failure {
  const FileFailure(super.message, [super.code]);
}

/// Permission failures
class PermissionFailure extends Failure {
  const PermissionFailure(super.message, [super.code]);
}

/// Database failures
class DatabaseFailure extends Failure {
  const DatabaseFailure(super.message, [super.code]);
}

/// Chat related failures
class ChatFailure extends Failure {
  const ChatFailure(super.message, [super.code]);
}

/// Unknown failures
class UnknownFailure extends Failure {
  const UnknownFailure(super.message, [super.code]);
}
