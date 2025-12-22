import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

admin.initializeApp();

/**
 * 🔔 NOTIFICATION TRIGGER 1: New Chat Message
 * 
 * Sends notification when a new message is created in any chat
 * - Excludes sender from notification
 * - Only notifies participants with FCM tokens
 * - Deep-links to /chat/{chatId}
 */
export const onNewChatMessage = functions.firestore
  .document("chats/{chatId}/messages/{messageId}")
  .onCreate(async (snapshot, context) => {
    const chatId = context.params.chatId;
    const messageData = snapshot.data();

    try {
      // Get sender info
      const senderId = messageData.senderId;
      const senderDoc = await admin.firestore()
        .collection("users")
        .doc(senderId)
        .get();
      const senderName = senderDoc.data()?.name || "Someone";

      // Get chat participants
      const chatDoc = await admin.firestore()
        .collection("chats")
        .doc(chatId)
        .get();
      
      if (!chatDoc.exists) {
        console.log("Chat not found:", chatId);
        return null;
      }

      const participants = chatDoc.data()?.participants || [];
      
      // Get FCM tokens of recipients (exclude sender)
      const recipients = participants.filter((id: string) => id !== senderId);
      
      if (recipients.length === 0) {
        console.log("No recipients for chat:", chatId);
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

      // Prepare notification payload
      let messagePreview = "";
      if (messageData.type === "text") {
        messagePreview = messageData.text || "New message";
      } else if (messageData.type === "image") {
        messagePreview = "📷 Photo";
      } else if (messageData.type === "voice") {
        messagePreview = "🎤 Voice message";
      } else if (messageData.type === "poll") {
        messagePreview = "📊 Poll";
      } else if (messageData.type === "paymentRequest") {
        messagePreview = "💰 Payment request";
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
          },
        },
      };

      const response = await admin.messaging().sendEachForMulticast(message);
      
      console.log(`✅ Sent ${response.successCount} notifications for chat ${chatId}`);
      if (response.failureCount > 0) {
        console.log(`❌ Failed to send ${response.failureCount} notifications`);
      }

      return null;
    } catch (error) {
      console.error("Error sending chat notification:", error);
      return null;
    }
  });

/**
 * 🔔 NOTIFICATION TRIGGER 2: Payment Request Created
 * 
 * Sends notification when a payment request is created
 * - Notifies receiver only
 * - Deep-links to /chat/{chatId}
 */
export const onPaymentRequestCreated = functions.firestore
  .document("payment_requests/{requestId}")
  .onCreate(async (snapshot, context) => {
    const requestData = snapshot.data();

    try {
      const senderId = requestData.senderId;
      const receiverId = requestData.receiverId;
      const amount = requestData.amount;
      const chatId = requestData.chatId;

      // Get sender name
      const senderDoc = await admin.firestore()
        .collection("users")
        .doc(senderId)
        .get();
      const senderName = senderDoc.data()?.name || "Someone";

      // Get receiver FCM token
      const receiverDoc = await admin.firestore()
        .collection("users")
        .doc(receiverId)
        .get();
      const receiverToken = receiverDoc.data()?.fcmToken;

      if (!receiverToken) {
        console.log("No FCM token for receiver:", receiverId);
        return null;
      }

      const notification = {
        title: "💰 Payment Request",
        body: `${senderName} requested ₹${amount}`,
      };

      const data = {
        route: `/chat/${chatId}`,
        chatId: chatId,
        requestId: context.params.requestId,
      };

      const message = {
        notification: notification,
        data: data,
        token: receiverToken,
        android: {
          priority: "high" as const,
          notification: {
            channelId: "high_importance_channel",
            priority: "high" as const,
          },
        },
      };

      await admin.messaging().send(message);
      console.log(`✅ Payment request notification sent to ${receiverId}`);

      return null;
    } catch (error) {
      console.error("Error sending payment request notification:", error);
      return null;
    }
  });

/**
 * 🔔 NOTIFICATION TRIGGER 3: Payment Status Changed
 * 
 * Sends notification when payment status changes to PAID/CANCELLED/FAILED
 * - Notifies sender (request creator)
 * - Deep-links to /chat/{chatId}
 */
export const onPaymentStatusChanged = functions.firestore
  .document("payment_requests/{requestId}")
  .onUpdate(async (change, context) => {
    const beforeData = change.before.data();
    const afterData = change.after.data();

    // Only notify if status changed
    if (beforeData.status === afterData.status) {
      return null;
    }

    const newStatus = afterData.status;

    // Only notify for PAID, CANCELLED, FAILED
    if (!["PAID", "CANCELLED", "FAILED"].includes(newStatus)) {
      return null;
    }

    try {
      const senderId = afterData.senderId;
      const receiverId = afterData.receiverId;
      const amount = afterData.amount;
      const chatId = afterData.chatId;

      // Get receiver name (who took action)
      const receiverDoc = await admin.firestore()
        .collection("users")
        .doc(receiverId)
        .get();
      const receiverName = receiverDoc.data()?.name || "Someone";

      // Get sender FCM token (notify request creator)
      const senderDoc = await admin.firestore()
        .collection("users")
        .doc(senderId)
        .get();
      const senderToken = senderDoc.data()?.fcmToken;

      if (!senderToken) {
        console.log("No FCM token for sender:", senderId);
        return null;
      }

      let title = "";
      let body = "";

      if (newStatus === "PAID") {
        title = "✅ Payment Received";
        body = `${receiverName} paid ₹${amount}`;
      } else if (newStatus === "CANCELLED") {
        title = "❌ Payment Cancelled";
        body = `${receiverName} cancelled the payment of ₹${amount}`;
      } else if (newStatus === "FAILED") {
        title = "⚠️ Payment Failed";
        body = `Payment of ₹${amount} to ${receiverName} failed`;
      }

      const notification = {
        title: title,
        body: body,
      };

      const data = {
        route: `/chat/${chatId}`,
        chatId: chatId,
        requestId: context.params.requestId,
        status: newStatus,
      };

      const message = {
        notification: notification,
        data: data,
        token: senderToken,
        android: {
          priority: "high" as const,
          notification: {
            channelId: "high_importance_channel",
            priority: "high" as const,
          },
        },
      };

      await admin.messaging().send(message);
      console.log(`✅ Payment status notification sent to ${senderId}`);

      return null;
    } catch (error) {
      console.error("Error sending payment status notification:", error);
      return null;
    }
  });

/**
 * 🔔 NOTIFICATION TRIGGER 4: Expense Created
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
