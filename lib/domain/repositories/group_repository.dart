import 'package:roomie/domain/entities/group_entity.dart';
import 'package:roomie/domain/entities/user_entity.dart';
import 'user_repository.dart';
import 'package:roomie/core/errors/failures.dart';

/// Group Repository Interface
/// Defines contract for group data operations
abstract class GroupRepository {
  /// Get user's current group
  Future<Either<Failure, GroupEntity?>> getCurrentGroup(String userId);

  /// Get available groups for user
  Future<Either<Failure, List<GroupEntity>>> getAvailableGroups(String userId);

  /// Get group by ID
  Future<Either<Failure, GroupEntity?>> getGroupById(String groupId);

  /// Create new group
  Future<Either<Failure, GroupEntity>> createGroup(GroupEntity group);

  /// Update group details
  Future<Either<Failure, void>> updateGroup(GroupEntity group);

  /// Join group
  Future<Either<Failure, void>> joinGroup(String groupId, String userId);

  /// Leave group
  Future<Either<Failure, void>> leaveGroup(String groupId, String userId);

  /// Send join request
  Future<Either<Failure, void>> sendJoinRequest(String groupId, String userId);

  /// Handle join request (accept/reject)
  Future<Either<Failure, void>> handleJoinRequest(
    String groupId,
    String requesterId,
    bool accept,
  );

  /// Get group members
  Future<Either<Failure, List<UserEntity>>> getGroupMembers(String groupId);

  /// Get join requests for group
  Future<Either<Failure, List<UserEntity>>> getJoinRequests(String groupId);

  /// Delete group
  Future<Either<Failure, void>> deleteGroup(String groupId);

  /// Upload group image
  Future<Either<Failure, String>> uploadGroupImage(String imagePath);

  /// Check if user can create group
  Future<Either<Failure, bool>> canCreateGroup(String userId);

  /// Search groups by name or location
  Future<Either<Failure, List<GroupEntity>>> searchGroups(String query);
}
