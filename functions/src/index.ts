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
