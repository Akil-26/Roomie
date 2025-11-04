import 'package:roomie/domain/entities/user_entity.dart';
import 'package:roomie/core/errors/failures.dart';

/// User Repository Interface
/// Defines contract for user data operations
abstract class UserRepository {
  /// Get current user
  Future<Either<Failure, UserEntity?>> getCurrentUser();

  /// Get user by ID
  Future<Either<Failure, UserEntity?>> getUserById(String userId);

  /// Update user profile
  Future<Either<Failure, void>> updateUserProfile(UserEntity user);

  /// Upload profile image
  Future<Either<Failure, String>> uploadProfileImage(String imagePath);

  /// Search users by name or username
  Future<Either<Failure, List<UserEntity>>> searchUsers(String query);

  /// Follow/Unfollow user
  Future<Either<Failure, void>> followUser(String userId);
  Future<Either<Failure, void>> unfollowUser(String userId);

  /// Check if user is following another user
  Future<Either<Failure, bool>> isFollowing(String userId);

  /// Get user's followers
  Future<Either<Failure, List<UserEntity>>> getFollowers(String userId);

  /// Get user's following
  Future<Either<Failure, List<UserEntity>>> getFollowing(String userId);

  /// Delete user account
  Future<Either<Failure, void>> deleteAccount();
}

/// Result type for repository operations
class Either<L, R> {
  final L? _left;
  final R? _right;
  final bool _isLeft;

  Either.left(L left) : _left = left, _right = null, _isLeft = true;
  Either.right(R right) : _left = null, _right = right, _isLeft = false;

  bool get isLeft => _isLeft;
  bool get isRight => !_isLeft;

  L get left {
    if (!_isLeft) throw Exception('Trying to get left value from right Either');
    return _left!;
  }

  R get right {
    if (_isLeft) throw Exception('Trying to get right value from left Either');
    return _right!;
  }

  T fold<T>(T Function(L) leftMapper, T Function(R) rightMapper) {
    if (_isLeft) {
      return leftMapper(_left as L);
    } else {
      return rightMapper(_right as R);
    }
  }
}
