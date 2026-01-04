import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:roomie/data/datasources/groups_service.dart';
import 'package:roomie/data/models/room_ownership_request_model.dart';
import 'package:intl/intl.dart';

/// Screen for owners to view their ownership request statuses.
/// 
/// STEP-3 APPROVAL UX - OWNER VIEW:
/// - Show: Room name, Status (pending/approved/rejected)
/// - No actions needed here - just status visibility
class MyOwnershipRequestsScreen extends StatefulWidget {
  const MyOwnershipRequestsScreen({super.key});

  @override
  State<MyOwnershipRequestsScreen> createState() => _MyOwnershipRequestsScreenState();
}

class _MyOwnershipRequestsScreenState extends State<MyOwnershipRequestsScreen> {
  final GroupsService _groupsService = GroupsService();
  bool _isLoading = true;
  List<RoomOwnershipRequestModel> _requests = [];
  final Map<String, Map<String, dynamic>?> _roomDetailsCache = {};

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() => _isLoading = true);
    
    try {
      final requests = await _groupsService.getMyOwnershipRequests();
      
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
      debugPrint('Error loading my ownership requests: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _getRoomName(String roomId) {
    final details = _roomDetailsCache[roomId];
    return details?['name'] ?? 'Unknown Room';
  }

  String? _getRoomImage(String roomId) {
    final details = _roomDetailsCache[roomId];
    final images = details?['images'] as List<dynamic>?;
    if (images != null && images.isNotEmpty) {
      return images.first as String?;
    }
    return details?['imageUrl'];
  }

  String _getRoomLocation(String roomId) {
    final details = _roomDetailsCache[roomId];
    return details?['location'] ?? '';
  }

  Color _getStatusColor(OwnershipRequestStatus status) {
    switch (status) {
      case OwnershipRequestStatus.pending:
        return Colors.orange;
      case OwnershipRequestStatus.approved:
        return Colors.green;
      case OwnershipRequestStatus.rejected:
        return Colors.red;
    }
  }

  String _getStatusText(OwnershipRequestStatus status) {
    switch (status) {
      case OwnershipRequestStatus.pending:
        return 'PENDING';
      case OwnershipRequestStatus.approved:
        return 'APPROVED';
      case OwnershipRequestStatus.rejected:
        return 'REJECTED';
    }
  }

  IconData _getStatusIcon(OwnershipRequestStatus status) {
    switch (status) {
      case OwnershipRequestStatus.pending:
        return Icons.hourglass_empty;
      case OwnershipRequestStatus.approved:
        return Icons.check_circle;
      case OwnershipRequestStatus.rejected:
        return Icons.cancel;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Ownership Requests'),
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
            Icons.assignment_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No Ownership Requests',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'You haven\'t made any ownership requests yet. '
              'Browse rooms and claim ownership to manage rent payments.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
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

  Widget _buildRequestCard(RoomOwnershipRequestModel request) {
    final roomName = _getRoomName(request.roomId);
    final roomImage = _getRoomImage(request.roomId);
    final roomLocation = _getRoomLocation(request.roomId);
    final formattedDate = DateFormat('MMM d, yyyy').format(request.requestedAt);
    final statusColor = _getStatusColor(request.status);
    final statusText = _getStatusText(request.status);
    final statusIcon = _getStatusIcon(request.status);

    // Get appropriate date for status
    String? statusDate;
    if (request.approvedAt != null) {
      statusDate = 'Approved on ${DateFormat('MMM d, yyyy').format(request.approvedAt!)}';
    } else if (request.rejectedAt != null) {
      statusDate = 'Rejected on ${DateFormat('MMM d, yyyy').format(request.rejectedAt!)}';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Room image
          if (roomImage != null)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: Image.network(
                roomImage,
                height: 120,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  height: 120,
                  color: Colors.grey[200],
                  child: const Icon(Icons.home, size: 48, color: Colors.grey),
                ),
              ),
            ),
          
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Room name and status
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            roomName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (roomLocation.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.location_on,
                                    size: 14,
                                    color: Colors.grey[500],
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      roomLocation,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey[600],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Status badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withAlpha(30),
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
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                // Request info
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                          const SizedBox(width: 8),
                          Text(
                            'Requested: $formattedDate',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                      if (statusDate != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(statusIcon, size: 14, color: statusColor),
                            const SizedBox(width: 8),
                            Text(
                              statusDate,
                              style: TextStyle(
                                fontSize: 13,
                                color: statusColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                
                // Status message
                if (request.status == OwnershipRequestStatus.approved) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.verified, color: Colors.green, size: 20),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'You are now the owner. You can receive rent payments.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.green,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (request.status == OwnershipRequestStatus.pending) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Waiting for the room admin to review your request.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ] else if (request.status == OwnershipRequestStatus.rejected) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: Colors.red, size: 20),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Your request was not approved. You can contact the room admin for more information.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.red,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
