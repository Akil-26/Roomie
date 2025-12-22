# 🔥 Roomie Cloud Functions - Push Notifications

## 📋 Overview

This directory contains Firebase Cloud Functions that trigger push notifications for:
- ✅ New chat messages
- ✅ Payment requests
- ✅ Payment status changes (PAID/CANCELLED/FAILED)
- ✅ New expenses

## 🚀 Setup & Deployment

### 1️⃣ Install Dependencies

```bash
cd functions
npm install
```

### 2️⃣ Build TypeScript

```bash
npm run build
```

### 3️⃣ Deploy to Firebase

```bash
# Deploy all functions
firebase deploy --only functions

# Deploy specific function
firebase deploy --only functions:onNewChatMessage
```

### 4️⃣ Test Locally (Optional)

```bash
# Start emulator
npm run serve

# View logs
firebase functions:log
```

## 📱 Notification Triggers

### 1. Chat Message (`onNewChatMessage`)
**Trigger:** `chats/{chatId}/messages/{messageId}` onCreate  
**Notifies:** All chat participants except sender  
**Payload:**
```json
{
  "notification": {
    "title": "Akil",
    "body": "Hey! What's up?"
  },
  "data": {
    "route": "/chat/{chatId}",
    "chatId": "chat_123",
    "senderId": "user_456"
  }
}
```

### 2. Payment Request (`onPaymentRequestCreated`)
**Trigger:** `payment_requests/{requestId}` onCreate  
**Notifies:** Receiver only  
**Payload:**
```json
{
  "notification": {
    "title": "💰 Payment Request",
    "body": "Akil requested ₹500"
  },
  "data": {
    "route": "/chat/{chatId}",
    "requestId": "req_789"
  }
}
```

### 3. Payment Status (`onPaymentStatusChanged`)
**Trigger:** `payment_requests/{requestId}` onUpdate  
**Notifies:** Request sender  
**Payload:**
```json
{
  "notification": {
    "title": "✅ Payment Received",
    "body": "Ravi paid ₹500"
  },
  "data": {
    "route": "/chat/{chatId}",
    "status": "PAID"
  }
}
```

### 4. Expense Created (`onExpenseCreated`)
**Trigger:** `expenses/{expenseId}` onCreate  
**Notifies:** All group members except creator  
**Payload:**
```json
{
  "notification": {
    "title": "💸 New Expense",
    "body": "Akil added \"Groceries\" - ₹1200"
  },
  "data": {
    "route": "/expenses/{expenseId}",
    "expenseId": "exp_123",
    "groupId": "group_456"
  }
}
```

## 🔒 Security Rules

All functions:
- ✅ Only notify users with FCM tokens
- ✅ Exclude sender/creator from notifications
- ✅ Validate document existence
- ✅ Handle errors gracefully

## 📊 Monitoring

View logs in Firebase Console:
```bash
firebase functions:log --only onNewChatMessage
```

## 🐛 Troubleshooting

### No notifications received?
1. Check FCM token is saved in Firestore `users/{uid}/fcmToken`
2. Verify functions deployed: `firebase functions:list`
3. Check function logs: `firebase functions:log`
4. Ensure Android notification channel configured

### Function timeout?
- Default timeout: 60s
- Increase in code: `runWith({ timeoutSeconds: 120 })`

## 📝 Update Functions

After code changes:
```bash
npm run build
firebase deploy --only functions
```

## 💡 Tips

- Functions run in Node.js 18 environment
- FCM tokens auto-refresh (client handles it)
- Multicast sends max 500 tokens per call
- Use `sendEachForMulticast` for batch sends

---

**🎯 Status:** ✅ Production Ready  
**📦 Version:** 1.0.0  
**🔥 Firebase Project:** roomie-cfc03
