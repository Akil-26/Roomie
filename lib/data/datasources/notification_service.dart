import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:roomie/data/models/notification_model.dart';
import 'package:roomie/data/datasources/auth_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  
  GlobalKey<NavigatorState>? _navigatorKey;
  
  void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

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
      // Initialize flutter_local_notifications (Android only for now)
      if (!kIsWeb) {
        const androidSettings =
            AndroidInitializationSettings('@mipmap/ic_launcher');
        const initSettings = InitializationSettings(android: androidSettings);

        await _localNotifications.initialize(
          initSettings,
          onDidReceiveNotificationResponse: _onTapNotification,
        );
        print('✅ Local notifications initialized');
      }

      // Request permission
      NotificationSettings settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print('✅ User granted permission');

        // Get FCM token (with web-specific handling)
        String? token;
        if (kIsWeb) {
          // On web, service worker registration might fail
          // but we can still get a token
          try {
            token = await _fcm.getToken(
              vapidKey: 'YOUR_VAPID_KEY', // Optional: Add your VAPID key here
            );
          } catch (webError) {
            print('⚠️ Web FCM token error (expected in development): $webError');
            // Continue without FCM token on web - other features still work
          }
        } else {
          // Mobile platforms
          token = await _fcm.getToken();
        }

        if (token != null) {
          await _saveFCMToken(token);
        }

        // Listen for token refresh
        _fcm.onTokenRefresh.listen(_saveFCMToken);

        // Handle foreground messages with local notification
        FirebaseMessaging.onMessage.listen(_showForegroundNotification);

        // Handle notification taps (background/killed app)
        FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
        
        // Check if app was opened from terminated state via notification
        final initialMessage = await _fcm.getInitialMessage();
        if (initialMessage != null) {
          print('🚀 App opened from terminated state via notification');
          // Delay to ensure navigator is ready
          Future.delayed(const Duration(milliseconds: 500), () {
            _handleNotificationTap(initialMessage);
          });
        }
      }
    } catch (e) {
      print('❌ Error initializing notifications: $e');
      // Don't rethrow - allow app to continue without notifications
    }
    
    // Always print this to indicate initialization completed
    print('✅ Notifications initialized');
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

  // Handle foreground messages with local notification display
  Future<void> _showForegroundNotification(RemoteMessage message) async {
    print('📨 Received foreground message: ${message.notification?.title}');
    
    if (kIsWeb) return; // Skip on web

    const androidDetails = AndroidNotificationDetails(
      'high_importance_channel',
      'High Importance Notifications',
      importance: Importance.max,
      priority: Priority.high,
    );

    const details = NotificationDetails(android: androidDetails);

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      message.notification?.title,
      message.notification?.body,
      details,
      payload: message.data['route'], // Deep link route (e.g., "/chats/{chatId}")
    );
  }

  // Handle notification tap (local notification tap)
  void _onTapNotification(NotificationResponse response) {
    final route = response.payload;
    if (route != null) {
      print('🔔 Notification tapped → $route');
      _navigateToRoute(route);
    }
  }

  // Handle notification tap from background/killed app
  void _handleNotificationTap(RemoteMessage message) {
    print('🔔 Notification tapped (background/killed): ${message.data}');
    final route = message.data['route'];
    if (route != null) {
      print('📍 Should navigate to: $route');
      _navigateToRoute(route);
    }
  }
  
  // Navigate to route from notification
  void _navigateToRoute(String route) {
    if (_navigatorKey?.currentContext == null) {
      print('⚠️ Navigator not ready, skipping navigation');
      return;
    }
    
    try {
      // Parse route: /chat/{chatId} or /expenses/{expenseId}
      if (route.startsWith('/chat/')) {
        final chatId = route.replaceFirst('/chat/', '');
        print('📍 Navigating to chat: $chatId');
        _navigatorKey!.currentState?.pushNamed(route);
      } else if (route.startsWith('/expenses/')) {
        final expenseId = route.replaceFirst('/expenses/', '');
        print('📍 Navigating to expense: $expenseId');
        // Expense detail screen navigation will be added in Phase 2
        print('⚠️ Expense detail screen not yet implemented');
      } else {
        print('⚠️ Unknown route format: $route');
      }
    } catch (e) {
      print('❌ Navigation error: $e');
    }
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

  // Create chat notification (dynamic data)
  Future<void> createChatNotification({
    required String userId,
    required String senderName,
    required String message,
    Map<String, dynamic>? extraData,
  }) async {
    try {
      final docRef = _userNotificationsRef(userId).doc();
      await docRef.set({
        'userId': userId,
        'type': 'chat',
        'senderName': senderName,
        'message': message,
        'data': extraData ?? {},
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
        'id': docRef.id,
      });
      print('✅ Chat notification created for $userId');
    } catch (e) {
      print('❌ Error creating chat notification: $e');
    }
  }

  // Create expense notification (dynamic data)
  Future<void> createExpenseNotification({
    required String userId,
    required String expenseTitle,
    required int amount,
    Map<String, dynamic>? extraData,
  }) async {
    try {
      final docRef = _userNotificationsRef(userId).doc();
      await docRef.set({
        'userId': userId,
        'type': 'expense',
        'title': expenseTitle,
        'amount': amount,
        'data': extraData ?? {},
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
        'id': docRef.id,
      });
      print('✅ Expense notification created for $userId');
    } catch (e) {
      print('❌ Error creating expense notification: $e');
    }
  }

  // Create payment notification (dynamic data)
  Future<void> createPaymentNotification({
    required String userId,
    required String status,
    required int amount,
    Map<String, dynamic>? extraData,
  }) async {
    try {
      final docRef = _userNotificationsRef(userId).doc();
      await docRef.set({
        'userId': userId,
        'type': 'payment',
        'status': status,
        'amount': amount,
        'data': extraData ?? {},
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
        'id': docRef.id,
      });
      print('✅ Payment notification created for $userId');
    } catch (e) {
      print('❌ Error creating payment notification: $e');
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

  // Get unread notification count stream
  Stream<int> getUnreadCount(String userId) {
    return _userNotificationsRef(userId)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
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

  /// Send push notification to a specific user via FCM
  /// This is used when Cloud Functions are not available
  Future<void> sendPushNotification({
    required String receiverId,
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    try {
      // Get receiver's FCM token from Firestore
      final userDoc = await _firestore.collection('users').doc(receiverId).get();
      final fcmToken = userDoc.data()?['fcmToken'] as String?;
      
      if (fcmToken == null || fcmToken.isEmpty) {
        print('⚠️ No FCM token found for user: $receiverId');
        return;
      }

      // Store the notification request in Firestore for the Cloud Function to process
      // This works as a trigger mechanism even without deployed Cloud Functions
      await _firestore.collection('push_notifications').add({
        'token': fcmToken,
        'notification': {
          'title': title,
          'body': body,
        },
        'data': data ?? {},
        'createdAt': FieldValue.serverTimestamp(),
        'processed': false,
      });
      
      print('✅ Push notification queued for $receiverId');
    } catch (e) {
      print('❌ Error sending push notification: $e');
    }
  }

  /// Send chat push notification to receiver
  Future<void> sendChatPushNotification({
    required String receiverId,
    required String senderName,
    required String messagePreview,
    required String chatId,
  }) async {
    await sendPushNotification(
      receiverId: receiverId,
      title: senderName,
      body: messagePreview,
      data: {
        'route': '/chat/$chatId',
        'chatId': chatId,
        'type': 'chat_message',
      },
    );
  }

  // ============================================================
  // STEP-2: OWNERSHIP CLAIM NOTIFICATIONS
  // ============================================================

  /// Notify room creator about an ownership claim request
  Future<void> sendOwnershipClaimNotification({
    required String roomId,
    required String roomName,
    required String ownerId,
    required String creatorId,
    required String requestId,
  }) async {
    try {
      await sendUserNotification(
        userId: creatorId,
        title: 'Ownership Claim Request',
        body: 'Someone wants to claim ownership of "$roomName"',
        type: 'ownership_claim',
        data: {
          'roomId': roomId,
          'roomName': roomName,
          'ownerId': ownerId,
          'requestId': requestId,
          'route': '/room/$roomId/ownership-requests',
        },
      );
      print('✅ Ownership claim notification sent to creator: $creatorId');
    } catch (e) {
      print('❌ Error sending ownership claim notification: $e');
    }
  }

  /// Notify owner that their claim was approved
  Future<void> sendOwnershipApprovedNotification({
    required String roomId,
    required String roomName,
    required String ownerId,
  }) async {
    try {
      await sendUserNotification(
        userId: ownerId,
        title: 'Ownership Claim Approved',
        body: 'Your ownership claim for "$roomName" has been approved!',
        type: 'ownership_approved',
        data: {
          'roomId': roomId,
          'roomName': roomName,
          'route': '/room/$roomId',
        },
      );
      print('✅ Ownership approved notification sent to owner: $ownerId');
    } catch (e) {
      print('❌ Error sending ownership approved notification: $e');
    }
  }

  /// Notify owner that their claim was rejected
  Future<void> sendOwnershipRejectedNotification({
    required String roomId,
    required String roomName,
    required String ownerId,
  }) async {
    try {
      await sendUserNotification(
        userId: ownerId,
        title: 'Ownership Claim Rejected',
        body: 'Your ownership claim for "$roomName" was not approved.',
        type: 'ownership_rejected',
        data: {
          'roomId': roomId,
          'roomName': roomName,
        },
      );
      print('✅ Ownership rejected notification sent to owner: $ownerId');
    } catch (e) {
      print('❌ Error sending ownership rejected notification: $e');
    }
  }

  // ============================================================
  // STEP-4: JOIN REQUEST NOTIFICATIONS
  // ============================================================

  /// Notify owner that someone wants to join their room
  Future<void> sendJoinRequestNotification({
    required String roomId,
    required String roomName,
    required String ownerId,
    required String requesterId,
  }) async {
    try {
      // Get requester name
      final requesterDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(requesterId)
          .get();
      final requesterName = requesterDoc.data()?['name'] ?? 'Someone';

      await sendUserNotification(
        userId: ownerId,
        title: 'New Join Request',
        body: '$requesterName wants to join "$roomName"',
        type: 'join_request',
        data: {
          'roomId': roomId,
          'roomName': roomName,
          'requesterId': requesterId,
          'route': '/room/$roomId/join-requests',
        },
      );
      print('✅ Join request notification sent to owner: $ownerId');
    } catch (e) {
      print('❌ Error sending join request notification: $e');
    }
  }

  /// Notify user that their join request was approved
  Future<void> sendJoinRequestApprovedNotification({
    required String roomId,
    required String roomName,
    required String userId,
  }) async {
    try {
      await sendUserNotification(
        userId: userId,
        title: 'Join Request Approved',
        body: 'You are now a member of "$roomName"!',
        type: 'join_approved',
        data: {
          'roomId': roomId,
          'roomName': roomName,
          'route': '/room/$roomId',
        },
      );
      print('✅ Join approved notification sent to user: $userId');
    } catch (e) {
      print('❌ Error sending join approved notification: $e');
    }
  }

  /// Notify user that their join request was rejected
  Future<void> sendJoinRequestRejectedNotification({
    required String roomId,
    required String roomName,
    required String userId,
  }) async {
    try {
      await sendUserNotification(
        userId: userId,
        title: 'Join Request Declined',
        body: 'Your request to join "$roomName" was not approved.',
        type: 'join_rejected',
        data: {
          'roomId': roomId,
          'roomName': roomName,
        },
      );
      print('✅ Join rejected notification sent to user: $userId');
    } catch (e) {
      print('❌ Error sending join rejected notification: $e');
    }
  }
}
