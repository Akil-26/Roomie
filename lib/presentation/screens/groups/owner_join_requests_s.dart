import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:roomie/data/datasources/groups_service.dart';
import 'package:roomie/data/models/room_join_request_model.dart';
import 'package:intl/intl.dart';

/// Screen for room owner to view and manage join requests.
/// 
/// STEP-4: JOIN REQUEST APPROVAL UX - MINIMAL & SAFE:
/// - Display: Student name, Request status (pending)
/// - Actions: ✅ Approve, ❌ Reject
/// - No voting, no roommate involvement
/// - OWNER ONLY can approve/reject
class OwnerJoinRequestsScreen extends StatefulWidget {
  final String roomId;
  final String roomName;

  const OwnerJoinRequestsScreen({
    super.key,
    required this.roomId,
    required this.roomName,
  });

  @override
  State<OwnerJoinRequestsScreen> createState() => _OwnerJoinRequestsScreenState();
}

class _OwnerJoinRequestsScreenState extends State<OwnerJoinRequestsScreen> {
  final GroupsService _groupsService = GroupsService();
  bool _isLoading = false;
  List<RoomJoinRequestModel> _requests = [];
  final Map<String, Map<String, dynamic>?> _userDetailsCache = {};

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() => _isLoading = true);
    
    try {
      final requests = await _groupsService.getPendingJoinRequests(widget.roomId);
      
      // Fetch user details for each request
      for (final request in requests) {
        if (!_userDetailsCache.containsKey(request.userId)) {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(request.userId)
              .get();
          _userDetailsCache[request.userId] = userDoc.data();
        }
      }
      
      if (mounted) {
        setState(() {
          _requests = requests;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading join requests: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _approveRequest(RoomJoinRequestModel request) async {
    final userName = _getUserName(request.userId);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve Join Request'),
        content: Text(
          'Are you sure you want to approve $userName\'s request to join "${widget.roomName}"?\n\n'
          'They will become a member of this room.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Approve'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    final success = await _groupsService.approveOwnerJoinRequest(request.requestId);

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$userName is now a member of "${widget.roomName}"'),
            backgroundColor: Colors.green,
          ),
        );
        _loadRequests(); // Refresh the list
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to approve join request'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _rejectRequest(RoomJoinRequestModel request) async {
    final userName = _getUserName(request.userId);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Join Request'),
        content: Text(
          'Are you sure you want to reject $userName\'s request to join "${widget.roomName}"?\n\n'
          'They will be notified.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    final success = await _groupsService.rejectOwnerJoinRequest(request.requestId);

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Join request rejected'),
            backgroundColor: Colors.orange,
          ),
        );
        _loadRequests();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to reject join request'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  String _getUserName(String userId) {
    final details = _userDetailsCache[userId];
    if (details == null) return 'Unknown';
    return details['username'] ?? details['name'] ?? 'Unknown';
  }

  String _getUserEmail(String userId) {
    final details = _userDetailsCache[userId];
    return details?['email'] ?? '';
  }

  String? _getUserPhoto(String userId) {
    final details = _userDetailsCache[userId];
    return details?['photoURL'] ?? details?['profileImageUrl'];
  }

  String? _getUserOccupation(String userId) {
    final details = _userDetailsCache[userId];
    return details?['occupation'];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Join Requests'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _requests.isEmpty
              ? _buildEmptyState()
              : _buildRequestsList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.person_add_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No Pending Requests',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'No one has requested to join\n"${widget.roomName}" yet',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestsList() {
    return RefreshIndicator(
      onRefresh: _loadRequests,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _requests.length,
        itemBuilder: (context, index) {
          final request = _requests[index];
          return _buildRequestCard(request);
        },
      ),
    );
  }

  Widget _buildRequestCard(RoomJoinRequestModel request) {
    final userName = _getUserName(request.userId);
    final userEmail = _getUserEmail(request.userId);
    final userPhoto = _getUserPhoto(request.userId);
    final occupation = _getUserOccupation(request.userId);
    final requestDate = DateFormat.yMMMd().add_jm().format(request.requestedAt);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User info row
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundImage: userPhoto != null ? NetworkImage(userPhoto) : null,
                  child: userPhoto == null 
                      ? Text(
                          userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                          style: const TextStyle(fontSize: 20),
                        ) 
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (userEmail.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          userEmail,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                      if (occupation != null && occupation.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          occupation,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Pending',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Request date
            Row(
              children: [
                Icon(Icons.schedule, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  'Requested: $requestDate',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _rejectRequest(request),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _approveRequest(request),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Approve'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
