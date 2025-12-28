import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

admin.initializeApp();

/**
 * 🔔 NOTIFICATION TRIGGER: Process Push Notification Queue
 * 
 * Sends push notification when a document is added to push_notifications collection
 * This is triggered by the Flutter app when a message is sent
 */
export const onPushNotificationCreated = functions.firestore
  .document("push_notifications/{notificationId}")
  .onCreate(async (snapshot, context) => {
    const notificationData = snapshot.data();

    if (!notificationData) {
      console.log("No notification data found");
      return null;
    }

    // Skip if already processed
    if (notificationData.processed === true) {
      console.log("Notification already processed");
      return null;
    }

    try {
      const token = notificationData.token;
      const notification = notificationData.notification || {};
      const data = notificationData.data || {};

      if (!token) {
        console.log("No FCM token in notification request");
        await snapshot.ref.update({ processed: true, error: "No token" });
        return null;
      }

      // Send the push notification
      const message = {
        token: token,
        notification: {
          title: notification.title || "Roomie",
          body: notification.body || "You have a new notification",
        },
        data: {
          ...data,
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
        android: {
          priority: "high" as const,
          notification: {
            channelId: "high_importance_channel",
            priority: "high" as const,
            sound: "default",
          },
        },
        apns: {
          payload: {
            aps: {
              alert: {
                title: notification.title || "Roomie",
                body: notification.body || "You have a new notification",
              },
              badge: 1,
              sound: "default",
            },
          },
        },
      };

      const response = await admin.messaging().send(message);
      console.log(`✅ Push notification sent successfully: ${response}`);

      // Mark as processed
      await snapshot.ref.update({ 
        processed: true, 
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
        messageId: response,
      });

      return null;
    } catch (error: unknown) {
      console.error("Error sending push notification:", error);
      const errorMessage = error instanceof Error ? error.message : String(error);
      await snapshot.ref.update({ 
        processed: true, 
        error: errorMessage,
      });
      return null;
    }
  });

/**
 * 🔔 NOTIFICATION TRIGGER: New Chat Message (Realtime Database)
 * 
 * Sends push notification when a new message is created in any chat
 * - Triggers from Realtime Database (where chat messages are stored)
 * - Excludes sender from notification
 * - Only notifies participants with FCM tokens
 * - Deep-links to /chat/{chatId}
 */
export const onNewChatMessage = functions.database
  .ref("chats/{chatId}/messages/{messageId}")
  .onCreate(async (snapshot, context) => {
    const chatId = context.params.chatId;
    const messageData = snapshot.val();

    if (!messageData) {
      console.log("No message data found");
      return null;
    }

    // Skip system messages
    if (messageData.isSystemMessage === true || messageData.senderId === "system") {
      console.log("Skipping system message");
      return null;
    }

    try {
      const senderId = messageData.senderId;
      const senderName = messageData.senderName || "Someone";

      // Get chat data from Realtime Database to find participants
      const chatSnapshot = await admin.database()
        .ref(`chats/${chatId}`)
        .once("value");
      
      const chatData = chatSnapshot.val();
      if (!chatData) {
        console.log("Chat not found:", chatId);
        return null;
      }

      const participants: string[] = chatData.participants || [];
      
      // Get FCM tokens of recipients (exclude sender)
      const recipients = participants.filter((id: string) => id !== senderId);
      
      if (recipients.length === 0) {
        console.log("No recipients for chat:", chatId);
        return null;
      }

      // Fetch FCM tokens from Firestore users collection
      const tokensPromises = recipients.map(async (userId: string) => {
        const userDoc = await admin.firestore()
          .collection("users")
          .doc(userId)
          .get();
        return userDoc.data()?.fcmToken;
      });

      const tokens = (await Promise.all(tokensPromises))
        .filter((token): token is string => !!token);

      if (tokens.length === 0) {
        console.log("No FCM tokens found for recipients");
        return null;
      }

      // Prepare notification payload based on message type
      let messagePreview = "";
      const msgType = messageData.type || "text";
      
      if (msgType === "text") {
        messagePreview = messageData.message || "New message";
        // Truncate long messages
        if (messagePreview.length > 100) {
          messagePreview = messagePreview.substring(0, 97) + "...";
        }
      } else if (msgType === "image") {
        messagePreview = "📷 Photo";
      } else if (msgType === "voice") {
        messagePreview = "🎤 Voice message";
      } else if (msgType === "poll") {
        messagePreview = "📊 Poll";
      } else if (msgType === "paymentRequest") {
        const amount = messageData.extraData?.amount || "";
        messagePreview = `💰 Payment request: ₹${amount}`;
      } else if (msgType === "todo") {
        messagePreview = "✅ Todo list";
      } else if (msgType === "file") {
        messagePreview = "📎 File";
      } else {
        messagePreview = "New message";
      }

      const notification = {
        title: senderName,
        body: messagePreview,
      };

      const data = {
        route: `/chat/${chatId}`,
        chatId: chatId,
        senderId: senderId,
        type: "chat_message",
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      };

      // Send notification to all recipients
      const message = {
        notification: notification,
        data: data,
        tokens: tokens,
        android: {
          priority: "high" as const,
          notification: {
            channelId: "high_importance_channel",
            priority: "high" as const,
            sound: "default",
          },
        },
        apns: {
          payload: {
            aps: {
              alert: {
                title: senderName,
                body: messagePreview,
              },
              badge: 1,
              sound: "default",
            },
          },
        },
      };

      const response = await admin.messaging().sendEachForMulticast(message);
      
      console.log(`✅ Sent ${response.successCount} notifications for chat ${chatId}`);
      if (response.failureCount > 0) {
        console.log(`❌ Failed to send ${response.failureCount} notifications`);
        response.responses.forEach((resp, idx) => {
          if (!resp.success) {
            console.log(`Token ${idx} failed:`, resp.error?.message);
          }
        });
      }

      return null;
    } catch (error) {
      console.error("Error sending chat notification:", error);
      return null;
    }
  });

/**
 * 🔔 NOTIFICATION TRIGGER 2: Expense Created
 * 
 * Sends notification when a new expense is created in a group
 * - Notifies all group members except creator
 * - Deep-links to /expenses/{expenseId}
 */
export const onExpenseCreated = functions.firestore
  .document("expenses/{expenseId}")
  .onCreate(async (snapshot, context) => {
    const expenseData = snapshot.data();

    try {
      const creatorId = expenseData.paidBy;
      const groupId = expenseData.groupId;
      const title = expenseData.title;
      const amount = expenseData.amount;

      // Get creator name
      const creatorDoc = await admin.firestore()
        .collection("users")
        .doc(creatorId)
        .get();
      const creatorName = creatorDoc.data()?.name || "Someone";

      // Get group members
      const groupDoc = await admin.firestore()
        .collection("groups")
        .doc(groupId)
        .get();
      
      if (!groupDoc.exists) {
        console.log("Group not found:", groupId);
        return null;
      }

      const members = groupDoc.data()?.members || [];
      
      // Get FCM tokens of recipients (exclude creator)
      const recipients = members.filter((id: string) => id !== creatorId);
      
      if (recipients.length === 0) {
        console.log("No recipients for expense:", context.params.expenseId);
        return null;
      }

      const tokensPromises = recipients.map(async (userId: string) => {
        const userDoc = await admin.firestore()
          .collection("users")
          .doc(userId)
          .get();
        return userDoc.data()?.fcmToken;
      });

      const tokens = (await Promise.all(tokensPromises))
        .filter((token): token is string => !!token);

      if (tokens.length === 0) {
        console.log("No FCM tokens found for recipients");
        return null;
      }

      const notification = {
        title: "💸 New Expense",
        body: `${creatorName} added "${title}" - ₹${amount}`,
      };

      const data = {
        route: `/expenses/${context.params.expenseId}`,
        expenseId: context.params.expenseId,
        groupId: groupId,
      };

      const message = {
        notification: notification,
        data: data,
        tokens: tokens,
        android: {
          priority: "high" as const,
          notification: {
            channelId: "high_importance_channel",
            priority: "high" as const,
          },
        },
      };

      const response = await admin.messaging().sendEachForMulticast(message);
      
      console.log(`✅ Sent ${response.successCount} expense notifications`);
      if (response.failureCount > 0) {
        console.log(`❌ Failed to send ${response.failureCount} notifications`);
      }

      return null;
    } catch (error) {
      console.error("Error sending expense notification:", error);
      return null;
    }
  });
