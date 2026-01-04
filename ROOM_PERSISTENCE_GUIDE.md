# Room Persistence System - Stable Room Foundation

## Overview

This document describes the "Stable Room Foundation" implementation that ensures rooms (groups) never get automatically deleted when users leave. This is the foundation for future features like owner-merge.

## Key Principles

### 1. Room Exists Independently of Members
- **Old behavior (REMOVED)**: Room was deleted when the last member left
- **New behavior**: Room persists even with ZERO members
- A room should only be deactivated (status change), never deleted

### 2. Separate Room from User-Room Relationship
Two core entities now track this:

#### `groups` collection (Room Entity)
The room itself with all its details:
- `status`: 'active' | 'inactive' (replaces deletion)
- `isPublic`: Whether room shows in available listings
- `creationType`: 'user_created' | 'owner_created'
- `ownerId`: For future owner-merge feature (nullable)

#### `room_members` collection (User-Room Link)
Tracks who is/was in a room:
- `roomId`: Reference to the room
- `userId`: Reference to the user  
- `role`: 'admin' | 'member'
- `joinedAt`: When they joined
- `leftAt`: When they left (nullable)
- `isActive`: false when user has left

## What Changed

### When a User Leaves a Room

**Before:**
```
1. Remove user from members array
2. If members array is empty → DELETE the room
3. Clean up related data (messages, join requests)
```

**After:**
```
1. Remove user from members array
2. Update room's memberCount
3. Mark room_member record as inactive (isActive: false, leftAt: timestamp)
4. Room STAYS ACTIVE - still visible in available rooms
5. NO deletion ever happens
```

### Available Rooms Logic

**Before:**
- Show rooms where `isActive == true` and user is not a member

**After:**
- Show rooms where:
  - `status == 'active'`
  - `isPublic == true`
  - User is not a member
- This means a room with ZERO members still shows up!

### Room Visibility

A room appears in "Available Rooms" if:
```dart
room.status == 'active' && room.isPublic == true
```

It does NOT matter if:
- 1 roommate left
- ALL roommates left
- Owner not merged yet

## New Model: RoomMemberModel

Located at: `lib/data/models/room_member_model.dart`

```dart
class RoomMemberModel {
  final String id;
  final String roomId;
  final String userId;
  final String role;      // 'admin' | 'member'
  final DateTime joinedAt;
  final DateTime? leftAt; // Set when user leaves
  final bool isActive;    // false when user left
}
```

## New/Updated GroupModel Fields

Located at: `lib/data/models/group_model.dart`

```dart
// New fields added to GroupModel:
final RoomStatus status;           // active | inactive
final bool isPublic;               // Show in listings?
final RoomCreationType creationType; // user_created | owner_created  
final String? ownerId;             // For future owner-merge
```

## API Changes in GroupsService

### Updated Methods:
- `leaveGroup()` - No longer deletes rooms
- `joinGroup()` - Creates room_member record
- `createGroup()` - Creates room_member record, sets new fields
- `getAvailableGroups()` - Filters by status AND isPublic
- `deleteGroup()` - Now only changes status to 'inactive'
- `approveJoinRequest()` - Creates room_member record

### New Methods:
- `_createRoomMemberRecord()` - Create new membership
- `_createOrReactivateRoomMember()` - Join/rejoin handling
- `_markRoomMemberAsLeft()` - Mark member as inactive
- `getRoomMembers()` - Get active members
- `getRoomMembershipHistory()` - Get all members including past
- `isUserActiveMember()` - Check active membership
- `reactivateRoom()` - Reactivate deactivated room
- `setRoomVisibility()` - Set public/private

## Firestore Rules

Updated rules at: `firestore.rules`

- Groups can no longer be deleted via client
- New `room_members` collection with proper security

## Migration for Existing Data

Existing rooms will work fine because:
1. Default value for `status` is 'active'
2. Default value for `isPublic` is true
3. Default value for `creationType` is 'user_created'
4. `ownerId` defaults to null

No migration script needed - backward compatible!

## Flow Example

```
User A creates room → 
  - Room stored in 'groups'
  - room_member record created (A as admin)

Users B, C, D join → 
  - Room members array updated
  - room_member records created (as members)

User B leaves → 
  - B removed from members array
  - B's room_member record: isActive=false, leftAt=now
  - Room STILL VISIBLE in available rooms

All users leave → 
  - members array empty
  - All room_member records: isActive=false
  - Room STILL VISIBLE in available rooms ✨

New user E finds and joins → 
  - E added to members array
  - E's room_member record created
  - Room continues its life!
```

## What's NOT Included (Future Work)

❌ Owner merge logic
❌ Dual chat system  
❌ Approval workflows for owner
❌ Payment integration
❌ Full deletion mechanism (intentionally not implemented)

## Testing Checklist

- [ ] Create a room → Check new fields are set
- [ ] Join room → Check room_member record created
- [ ] Leave room → Check room NOT deleted, room_member marked inactive
- [ ] All members leave → Room still in available rooms
- [ ] Rejoin room → room_member reactivated (not duplicated)
- [ ] Deactivate room → Not in available rooms but data preserved
- [ ] Reactivate room → Back in available rooms

## Summary

The core win of this implementation:
1. **Solves the biggest fear** - rooms can't get blocked/deleted
2. **Easy to build on** - foundation for owner-merge later
3. **Backward compatible** - no migration needed
4. **Clean separation** - room entity vs membership tracking
