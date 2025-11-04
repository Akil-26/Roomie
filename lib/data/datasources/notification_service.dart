import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:roomie/data/models/notification_model.dart';
import 'package:roomie/data/datasources/auth_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();

  CollectionReference<Map<String, dynamic>> _userNotificationsRef(
    String userId,
  ) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('notifications');
  }

  // Initialize notifications
  Future<void> initialize() async {
    try {
      // Request permission
      NotificationSettings settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print('✅ User granted permission');

        // Get FCM token
        String? token = await _fcm.getToken();
        if (token != null) {
          await _saveFCMToken(token);
        }

        // Listen for token refresh
        _fcm.onTokenRefresh.listen(_saveFCMToken);

        // Handle foreground messages
        FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

        // Handle notification taps
        FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
      }
    } catch (e) {
      print('❌ Error initializing notifications: $e');
    }
  }

  // Save FCM token to Firestore
  Future<void> _saveFCMToken(String token) async {
    try {
      final user = _authService.currentUser;
      if (user != null) {
        await _firestore.collection('users').doc(user.uid).update({
          'fcmToken': token,
          'tokenUpdated': FieldValue.serverTimestamp(),
        });
        print('✅ FCM token saved');
      }
    } catch (e) {
      print('❌ Error saving FCM token: $e');
    }
  }

  // Handle foreground messages
  void _handleForegroundMessage(RemoteMessage message) {
    print('📨 Received foreground message: ${message.notification?.title}');
    // You can show a local notification here if needed
  }

  // Handle notification tap
  void _handleNotificationTap(RemoteMessage message) {
    print('🔔 Notification tapped: ${message.data}');
    // Navigate to a specific screen based on notification data
  }

  // Send notification to a specific user
  Future<void> sendUserNotification({
    required String userId,
    required String title,
    required String body,
    required String type,
    Map<String, dynamic>? data,
  }) async {
    try {
      final docRef = _userNotificationsRef(userId).doc();
      await docRef.set({
        'userId': userId,
        'title': title,
        'body': body,
        'type': type,
        'data': data ?? {},
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
        'id': docRef.id,
      });
      print('✅ User notification sent to $userId');
    } catch (e) {
      print('❌ Error sending user notification: $e');
    }
  }

  // Get notifications for a user
  Stream<List<NotificationModel>> getNotifications(String userId) {
    // Query all and filter unread in memory to avoid composite index requirements
    return _userNotificationsRef(
      userId,
    ).orderBy('createdAt', descending: true).snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => NotificationModel.fromFirestore(doc))
          .where((n) => n.isRead == false)
          .toList();
    });
  }

  // Mark a notification as read
  Future<void> markAsRead(String notificationId) async {
    try {
      final user = _authService.currentUser;
      if (user == null) throw Exception('Not authenticated');

      await _userNotificationsRef(
        user.uid,
      ).doc(notificationId).update({'isRead': true});
      print('✅ Notification marked as read: $notificationId');
    } catch (e) {
      print('❌ Error marking notification as read: $e');
    }
  }

  // Delete a notification
  Future<void> deleteNotification(String notificationId) async {
    try {
      final user = _authService.currentUser;
      if (user == null) throw Exception('Not authenticated');

      await _userNotificationsRef(user.uid).doc(notificationId).delete();
      print('✅ Notification deleted: $notificationId');
    } catch (e) {
      print('❌ Error deleting notification: $e');
    }
  }

  Future<void> clearJoinRequestNotifications({
    required String requestId,
    required Iterable<String> memberIds,
  }) async {
    if (memberIds.isEmpty) return;

    try {
      final futures = memberIds.map((memberId) async {
        final query =
            await _userNotificationsRef(memberId)
                .where('type', isEqualTo: 'join_request_received')
                .where('data.requestId', isEqualTo: requestId)
                .get();

        for (final doc in query.docs) {
          await doc.reference.delete();
        }
      });

      await Future.wait(futures);
    } catch (e) {
      print('❌ Error clearing join request notifications: $e');
    }
  }

  Future<void> sendGroupNotification({
    required String groupId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      final groupDoc = await _firestore.collection('groups').doc(groupId).get();
      if (!groupDoc.exists) {
        print('⚠️ Group not found for notification: $groupId');
        return;
      }

      final members = List<String>.from(groupDoc.data()?['members'] ?? []);
      if (members.isEmpty) {
        print('ℹ️ No members to notify for group: $groupId');
        return;
      }

      for (final memberId in members) {
        await sendUserNotification(
          userId: memberId,
          title: title,
          body: body,
          type: data?['type']?.toString() ?? 'general',
          data: {'groupId': groupId, ...?data},
        );
      }
    } catch (e) {
      print('❌ Error sending group notification: $e');
    }
  }

  Future<void> sendExpenseNotification({
    required String groupId,
    required String expenseTitle,
    required String action, // 'created', 'paid', 'reminder'
    required double amount,
  }) async {
    String title = '';
    String body = '';

    switch (action) {
      case 'created':
        title = 'New Expense Added';
        body = '$expenseTitle - ₹${amount.toStringAsFixed(0)}';
        break;
      case 'paid':
        title = 'Expense Payment Received';
        body = 'Payment received for $expenseTitle';
        break;
      case 'reminder':
        title = 'Payment Reminder';
        body = 'Please pay your share for $expenseTitle';
        break;
      default:
        title = 'Expense Update';
        body = expenseTitle;
        break;
    }

    await sendGroupNotification(
      groupId: groupId,
      title: title,
      body: body,
      data: {
        'type': 'expense',
        'action': action,
        'amount': amount,
        'title': expenseTitle,
      },
    );
  }

  // Show local notification
  void showLocalNotification({required String title, required String body}) {
    // In a real app, you'd use flutter_local_notifications here
    print('🔔 Local notification: $title - $body');
  }
}
