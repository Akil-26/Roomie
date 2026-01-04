import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:roomie/data/datasources/groups_service.dart';
import 'package:roomie/data/models/room_join_request_model.dart';
import 'package:intl/intl.dart';

/// Screen for students to view their join request statuses.
/// 
/// STEP-4: MY JOIN REQUESTS VIEW:
/// - Shows all join requests made by current user
/// - Status: pending, approved, rejected
/// - No private data exposed before approval
class MyJoinRequestsScreen extends StatefulWidget {
  const MyJoinRequestsScreen({super.key});

  @override
  State<MyJoinRequestsScreen> createState() => _MyJoinRequestsScreenState();
}

class _MyJoinRequestsScreenState extends State<MyJoinRequestsScreen> {
  final GroupsService _groupsService = GroupsService();
  bool _isLoading = true;
  List<RoomJoinRequestModel> _requests = [];
  final Map<String, Map<String, dynamic>?> _roomDetailsCache = {};

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() => _isLoading = true);
    
    try {
      final requests = await _groupsService.getMyJoinRequests();
      
      // Fetch room details for each request
      for (final request in requests) {
        if (!_roomDetailsCache.containsKey(request.roomId)) {
          final roomDoc = await FirebaseFirestore.instance
              .collection('groups')
              .doc(request.roomId)
              .get();
          _roomDetailsCache[request.roomId] = roomDoc.data();
        }
      }
      
      if (mounted) {
        setState(() {
          _requests = requests;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading my join requests: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _getRoomName(String roomId) {
    final details = _roomDetailsCache[roomId];
    return details?['name'] ?? 'Unknown Room';
  }

  String _getRoomLocation(String roomId) {
    final details = _roomDetailsCache[roomId];
    return details?['location'] ?? '';
  }

  String? _getRoomImage(String roomId) {
    final details = _roomDetailsCache[roomId];
    final images = details?['images'] as List<dynamic>?;
    if (images != null && images.isNotEmpty) {
      return images.first as String?;
    }
    return details?['imageUrl'];
  }

  Color _getStatusColor(JoinRequestStatus status) {
    switch (status) {
      case JoinRequestStatus.pending:
        return Colors.orange;
      case JoinRequestStatus.approved:
        return Colors.green;
      case JoinRequestStatus.rejected:
        return Colors.red;
    }
  }

  String _getStatusText(JoinRequestStatus status) {
    switch (status) {
      case JoinRequestStatus.pending:
        return 'Pending';
      case JoinRequestStatus.approved:
        return 'Approved';
      case JoinRequestStatus.rejected:
        return 'Rejected';
    }
  }

  IconData _getStatusIcon(JoinRequestStatus status) {
    switch (status) {
      case JoinRequestStatus.pending:
        return Icons.hourglass_empty;
      case JoinRequestStatus.approved:
        return Icons.check_circle;
      case JoinRequestStatus.rejected:
        return Icons.cancel;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Join Requests'),
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
            Icons.send_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No Join Requests',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You haven\'t requested to join any rooms yet.\n'
            'Browse available rooms to find one!',
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
    final roomName = _getRoomName(request.roomId);
    final roomLocation = _getRoomLocation(request.roomId);
    final roomImage = _getRoomImage(request.roomId);
    final requestDate = DateFormat.yMMMd().add_jm().format(request.requestedAt);
    final statusColor = _getStatusColor(request.status);
    final statusText = _getStatusText(request.status);
    final statusIcon = _getStatusIcon(request.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Room info row
            Row(
              children: [
                // Room image
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: roomImage != null
                      ? Image.network(
                          roomImage,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            width: 56,
                            height: 56,
                            color: Colors.grey[200],
                            child: Icon(
                              Icons.home,
                              color: Colors.grey[400],
                            ),
                          ),
                        )
                      : Container(
                          width: 56,
                          height: 56,
                          color: Colors.grey[200],
                          child: Icon(
                            Icons.home,
                            color: Colors.grey[400],
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        roomName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (roomLocation.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          roomLocation,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 14, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            
            // Request details
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

            // Show status-specific message
            if (request.status == JoinRequestStatus.pending) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: Colors.orange[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Waiting for the owner to review your request.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.orange[800],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (request.status == JoinRequestStatus.approved) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline, size: 18, color: Colors.green[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'You are now a member of this room!',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.green[800],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (request.status == JoinRequestStatus.rejected) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: Colors.red[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your request was not approved. You can try other rooms.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.red[800],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Show reviewed date for approved/rejected
            if (request.reviewedAt != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.done_all, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    'Reviewed: ${DateFormat.yMMMd().add_jm().format(request.reviewedAt!)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
