import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:roomie/data/datasources/groups_service.dart';
import 'package:roomie/data/models/room_ownership_request_model.dart';
import 'package:intl/intl.dart';

/// Screen for room creator/admin to view and manage ownership requests.
/// 
/// STEP-3 APPROVAL UX - MINIMAL & SAFE:
/// - Display: Room name, Owner name, Request status (pending)
/// - Actions: ✅ Approve, ❌ Reject
/// - No voting, no comments, no automation
class OwnershipRequestsScreen extends StatefulWidget {
  final String roomId;
  final String roomName;

  const OwnershipRequestsScreen({
    super.key,
    required this.roomId,
    required this.roomName,
  });

  @override
  State<OwnershipRequestsScreen> createState() => _OwnershipRequestsScreenState();
}

class _OwnershipRequestsScreenState extends State<OwnershipRequestsScreen> {
  final GroupsService _groupsService = GroupsService();
  bool _isLoading = false;
  List<RoomOwnershipRequestModel> _requests = [];
  final Map<String, Map<String, dynamic>?> _ownerDetailsCache = {};

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() => _isLoading = true);
    
    try {
      final requests = await _groupsService.getPendingOwnershipRequests(widget.roomId);
      
      // Fetch owner details for each request
      for (final request in requests) {
        if (!_ownerDetailsCache.containsKey(request.ownerId)) {
          final ownerDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(request.ownerId)
              .get();
          _ownerDetailsCache[request.ownerId] = ownerDoc.data();
        }
      }
      
      if (mounted) {
        setState(() {
          _requests = requests;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading ownership requests: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _approveRequest(RoomOwnershipRequestModel request) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve Ownership'),
        content: Text(
          'Are you sure you want to approve this ownership request?\n\n'
          'The owner will be able to receive payments and manage rent for "${widget.roomName}".\n\n'
          'This action cannot be undone.',
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

    final success = await _groupsService.approveOwnershipRequest(request.requestId);

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ownership request approved'),
            backgroundColor: Colors.green,
          ),
        );
        _loadRequests(); // Refresh the list
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to approve ownership request'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _rejectRequest(RoomOwnershipRequestModel request) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Ownership'),
        content: Text(
          'Are you sure you want to reject this ownership request?\n\n'
          'The owner "${_getOwnerName(request.ownerId)}" will be notified.',
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

    final success = await _groupsService.rejectOwnershipRequest(request.requestId);

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ownership request rejected'),
            backgroundColor: Colors.orange,
          ),
        );
        _loadRequests();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to reject ownership request'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  String _getOwnerName(String ownerId) {
    final details = _ownerDetailsCache[ownerId];
    if (details == null) return 'Unknown';
    return details['username'] ?? details['name'] ?? 'Unknown';
  }

  String _getOwnerEmail(String ownerId) {
    final details = _ownerDetailsCache[ownerId];
    return details?['email'] ?? '';
  }

  String? _getOwnerPhoto(String ownerId) {
    final details = _ownerDetailsCache[ownerId];
    return details?['photoURL'] ?? details?['profileImageUrl'];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ownership Requests'),
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
            Icons.verified_user_outlined,
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
            'There are no ownership requests for "${widget.roomName}"',
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

  Widget _buildRequestCard(RoomOwnershipRequestModel request) {
    final ownerName = _getOwnerName(request.ownerId);
    final ownerEmail = _getOwnerEmail(request.ownerId);
    final ownerPhoto = _getOwnerPhoto(request.ownerId);
    final formattedDate = DateFormat('MMM d, yyyy').format(request.requestedAt);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with owner info
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundImage: ownerPhoto != null
                      ? NetworkImage(ownerPhoto)
                      : null,
                  child: ownerPhoto == null
                      ? Text(
                          ownerName.isNotEmpty ? ownerName[0].toUpperCase() : '?',
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
                        ownerName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (ownerEmail.isNotEmpty)
                        Text(
                          ownerEmail,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                    ],
                  ),
                ),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'PENDING',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Request info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.home, size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text(
                        'Room: ${widget.roomName}',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text(
                        'Requested: $formattedDate',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Info text
            Text(
              'If approved, this person will become the owner and can receive rent payments.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
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
                      padding: const EdgeInsets.symmetric(vertical: 12),
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
                      padding: const EdgeInsets.symmetric(vertical: 12),
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
