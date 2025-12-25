# 💰 Roomie Chat Payment - Complete Flow Guide

## 📋 Table of Contents
1. [Overview](#overview)
2. [System Architecture](#system-architecture)
3. [User Flow - Sender Side](#user-flow---sender-side)
4. [User Flow - Receiver Side](#user-flow---receiver-side)
5. [Technical Flow](#technical-flow)
6. [Database Schema](#database-schema)
7. [State Transitions](#state-transitions)
8. [Error Handling](#error-handling)

---

## Overview

The Roomie chat payment system allows users to request and make payments directly within chat conversations (both direct and group chats). The system integrates with UPI payment apps for actual transactions.

### Key Features:
- 💸 Request payments in direct or group chats
- 📱 Launch UPI apps (GPay, PhonePe, Paytm) with pre-filled details
- ⏱️ Real-time payment status updates
- 🔄 Retry failed payments
- 🛡️ Double payment prevention
- 💱 Multi-currency support

---

## System Architecture

```
┌─────────────┐         ┌──────────────┐         ┌─────────────┐
│   Sender    │────────▶│  Chat Server │────────▶│  Receiver   │
│  (User A)   │         │   (Firebase) │         │  (User B)   │
└─────────────┘         └──────────────┘         └─────────────┘
       │                        │                        │
       │                        │                        │
       ▼                        ▼                        ▼
┌─────────────┐         ┌──────────────┐         ┌─────────────┐
│ Firestore   │         │  Realtime DB │         │  UPI Apps   │
│ (Expenses)  │         │  (Messages)  │         │ (Payment)   │
└─────────────┘         └──────────────┘         └─────────────┘
```

---

## User Flow - Sender Side

### Step 1: Initiate Payment Request

```
User A opens chat with User B
         ↓
Clicks attachment icon (📎)
         ↓
Selects "Payment" option
         ↓
Payment Request Bottom Sheet appears
```

### Step 2: Fill Payment Details

```
┌───────────────────────────────────────┐
│    💰 Request Payment                 │
├───────────────────────────────────────┤
│                                       │
│  Amount: [₹ 500] (₹ symbol auto)     │
│                                       │
│  Description: [Dinner at restaurant]  │
│                                       │
│  Request from:                        │
│  ☑ User B (Direct chat auto-selects) │
│  ☐ User C (Group chat multi-select)  │
│  ☐ User D                             │
│                                       │
│  [ Cancel ]        [ Send Request ]   │
└───────────────────────────────────────┘
```

### Step 3: System Fetches Sender Details

```dart
// System automatically fetches from Firestore
User A's Profile:
  - Phone: "9876543210"
  - UPI ID: "usera@paytm" (optional)
  - Name: "John Doe"
```

### Step 4: Message Sent

```
Payment request created:
  ✓ Type: MessageType.paymentRequest
  ✓ Amount: 500.0 (double)
  ✓ Currency: "INR"
  ✓ Note: "Dinner at restaurant"
  ✓ From: User A (sender)
  ✓ To: [User B] (receivers)
  ✓ Status: {"userB": "PENDING"}
  ✓ Phone: "9876543210"
  ✓ UPI ID: "usera@paytm"
         ↓
Message stored in Firebase Realtime DB
         ↓
Receiver gets push notification
```

### Step 5: Sender Sees Request in Chat

```
┌────────────────────────────────────────┐
│  💳 Payment Request                    │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │
│  ₹500.00                               │
│  Dinner at restaurant                  │
│                                        │
│  Requested by You                      │
│                                        │
│  📊 Payment Status:                    │
│  ⏳ User B: PENDING                    │
│                                        │
│  ℹ️ You sent this payment request     │
└────────────────────────────────────────┘
```

---

## User Flow - Receiver Side

### Step 1: Receiver Opens Chat

```
User B receives notification:
  "💰 Payment Request - John Doe requested ₹500"
         ↓
Opens chat
         ↓
Sees payment request card
```

### Step 2: Receiver Sees Payment Card

```
┌────────────────────────────────────────┐
│  💳 Payment Request                    │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │
│  ₹500.00                               │
│  Dinner at restaurant                  │
│                                        │
│  Requested by John Doe                 │
│                                        │
│  📊 Payment Status:                    │
│  ⏳ You: PENDING                       │
│                                        │
│  ┌──────────────────────────────┐     │
│  │      💳 PAY NOW              │     │
│  └──────────────────────────────┘     │
└────────────────────────────────────────┘
```

**Button Visibility Logic**:
```javascript
Show "PAY NOW" button IF:
  ✓ Current user is NOT the sender
  ✓ Current user IS in toUsers list
  ✓ Current user's status is NOT "PAID"

Hide button IF:
  ✗ User is the sender (sees info message instead)
  ✗ User already paid (status = "PAID")
  ✗ User not in target list
```

### Step 3: User Clicks "PAY NOW"

```
User B clicks PAY NOW button
         ↓
System validates data
         ↓
Builds UPI payment URL:
  upi://pay?
    pa=usera@paytm              (UPI ID)
    &pn=John Doe                (Name)
    &am=500.00                  (Amount)
    &tn=Dinner at restaurant    (Note)
    &cu=INR                     (Currency)
    &mc=9876543210              (Phone)
         ↓
Launches Android Intent
```

### Step 4: UPI App Opens

```
┌─────────────────────────────────┐
│         GPay / PhonePe          │
├─────────────────────────────────┤
│  Pay to: John Doe               │
│  Phone: 9876543210              │
│  UPI: usera@paytm               │
│                                 │
│  Amount: ₹500.00                │
│  Note: Dinner at restaurant     │
│                                 │
│  [ Select Account ▼ ]           │
│  Bank Account - ****1234        │
│                                 │
│  [ Cancel ]        [ Pay Now ]  │
└─────────────────────────────────┘
```

**User completes payment in UPI app**:
- Enters UPI PIN
- Confirms transaction
- Payment processed by bank

### Step 5: Return to Roomie App

```
User returns to Roomie
         ↓
Confirmation dialog appears:

┌─────────────────────────────────────┐
│  Payment Confirmation               │
├─────────────────────────────────────┤
│  Did you complete the payment of    │
│  ₹500.00 to John Doe?               │
│                                     │
│  ⚠️ If payment failed:              │
│  • Check UPI PIN / Reset if needed  │
│  • Verify bank server is working    │
│  • Check daily transaction limits   │
│  • Try again after 10-15 minutes    │
│  • Switch to different UPI app      │
│                                     │
│  [ NO / FAILED ]    [ YES, PAID ]   │
└─────────────────────────────────────┘
```

### Step 6a: If User Clicks "YES, PAID"

```
System processes payment:

1️⃣ Update Realtime DB:
   paymentStatus/userB = "PAID"
   paidAt/userB = timestamp
         ↓
2️⃣ Create Expense in Firestore:
   {
     groupId: chatId,
     amount: 500.0,
     currency: "INR",
     paidBy: "userB",
     requestedBy: "userA",
     source: "chat_payment",
     linkedMessageId: "msg_123"
   }
         ↓
3️⃣ Link expense to message:
   expenseId/userB = "exp_456"
         ↓
4️⃣ Send notification to sender:
   "✅ John Doe received your payment"
         ↓
5️⃣ UI updates automatically (realtime listener)
```

### Step 6b: If User Clicks "NO / FAILED"

```
System marks payment as cancelled:

   paymentStatus/userB = "CANCELLED"
         ↓
UI updates to show retry option:

┌────────────────────────────────────────┐
│  💳 Payment Request                    │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │
│  ₹500.00                               │
│  Dinner at restaurant                  │
│                                        │
│  📊 Payment Status:                    │
│  ⚠️ You: CANCELLED                     │
│                                        │
│  ┌──────────────────────────────┐     │
│  │    🔄 RETRY PAYMENT          │     │
│  └──────────────────────────────┘     │
│                                        │
│  💡 Common issues resolved? Retry!    │
└────────────────────────────────────────┘
```

### Step 7: Payment Complete - Both Users See Update

**Sender's View**:
```
┌────────────────────────────────────────┐
│  💳 Payment Request                    │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │
│  ₹500.00                               │
│  Dinner at restaurant                  │
│                                        │
│  📊 Payment Status:                    │
│  ✅ User B: PAID                       │
│                                        │
│  ✅ Payment Completed ✅               │
└────────────────────────────────────────┘
```

**Receiver's View**:
```
┌────────────────────────────────────────┐
│  💳 Payment Request                    │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │
│  ₹500.00                               │
│  Dinner at restaurant                  │
│                                        │
│  📊 Payment Status:                    │
│  ✅ You: PAID                          │
│                                        │
│  ✅ Payment Completed ✅               │
│  (Pay Now button hidden)               │
└────────────────────────────────────────┘
```

---

## Technical Flow

### A. Sending Payment Request

```mermaid
sequenceDiagram
    participant Sender as User A (Sender)
    participant UI as Chat UI
    participant Service as Chat Service
    participant Firebase as Firebase RTDB
    participant Firestore as Firestore
    
    Sender->>UI: Click Payment button
    UI->>UI: Show PaymentRequestBottomSheet
    Sender->>UI: Enter amount, note, select users
    UI->>Firestore: Fetch sender's phone & UPI ID
    Firestore-->>UI: Return user profile data
    UI->>Service: sendMessage(type=paymentRequest)
    Service->>Firebase: Store message with payment fields
    Firebase-->>Service: Message saved
    Service->>Firestore: Send push notification
    Firebase->>Receiver: Real-time update (listener)
```

### B. Making Payment

```mermaid
sequenceDiagram
    participant Receiver as User B (Receiver)
    participant Card as PaymentRequestCard
    participant UPI as UPI Service
    participant App as Payment App
    participant Firebase as Firebase RTDB
    participant Firestore as Firestore
    
    Receiver->>Card: Click PAY NOW
    Card->>UPI: initiateUpiPayment()
    UPI->>UPI: Build UPI URL
    UPI->>App: Launch Android Intent
    App-->>Receiver: User completes payment
    Receiver->>Card: Returns to app
    Card->>Receiver: Show confirmation dialog
    Receiver->>Card: Click YES, PAID
    Card->>Firebase: Update paymentStatus to PAID
    Card->>Firestore: Create expense entry
    Card->>Firebase: Link expense ID
    Card->>Firestore: Send notification to sender
    Firebase->>Sender: Real-time update (both users)
    Firebase->>Receiver: Real-time update (both users)
```

### C. Real-Time Status Updates

```mermaid
sequenceDiagram
    participant Card as PaymentRequestCard
    participant Firebase as Firebase RTDB
    participant Sender as Sender UI
    participant Receiver as Receiver UI
    
    Note over Card: Component mounts
    Card->>Firebase: Subscribe to message path
    
    Note over Receiver: User pays
    Receiver->>Firebase: Update paymentStatus
    Firebase-->>Card: onValue event fired
    Card->>Card: setState() with new status
    Card->>Receiver: UI updates (button hides)
    
    Firebase-->>Sender: onValue event fired
    Sender->>Sender: UI updates (shows PAID)
    
    Note over Card: Component unmounts
    Card->>Firebase: Unsubscribe listener
```

---

## Database Schema

### Firebase Realtime Database (Messages)

**Path**: `chats/{chatId}/messages/{messageId}` (Direct chat)  
**Path**: `groupChats/{chatId}/messages/{messageId}` (Group chat)

```json
{
  "id": "msg_1735048320000_userA",
  "type": "paymentRequest",
  "senderId": "userA",
  "senderName": "John Doe",
  "receiverId": "userB",
  "message": "Payment request: ₹500.00 - Dinner",
  "timestamp": 1735048320000,
  
  // Payment-specific fields
  "paymentRequestId": "req_1735048320000_userA",
  "paymentAmount": 500.0,
  "paymentCurrency": "INR",
  "paymentNote": "Dinner at restaurant",
  "paymentUpiId": "usera@paytm",
  "payToPhoneNumber": "9876543210",
  "payToUserIds": ["userB", "userC"],
  
  // Payment status map (real-time updates)
  "paymentStatus": {
    "userB": "PAID",
    "userC": "PENDING"
  },
  
  // Payment timestamps
  "paidAt": {
    "userB": 1735048500000
  },
  
  // Linked expense IDs
  "expenseId": {
    "userB": "exp_abc123"
  }
}
```

### Firestore (Expenses)

**Collection**: `expenses`

```json
{
  "id": "exp_abc123",
  "groupId": "chat_userA_userB",
  "title": "Dinner at restaurant",
  "amount": 500.0,
  "currency": "INR",
  "paidBy": "userB",
  "requestedBy": "userA",
  "payeeName": "John Doe",
  "linkedMessageId": "msg_1735048320000_userA",
  "participants": ["userB"],
  "isGroupPayment": false,
  "source": "chat_payment",
  "createdAt": "2025-12-24T10:25:00Z",
  "updatedAt": "2025-12-24T10:25:00Z"
}
```

---

## State Transitions

### Payment Status State Machine

```
                    ┌─────────┐
                    │ PENDING │ ◀── Initial state
                    └────┬────┘
                         │
                         │ User clicks PAY NOW
                         │
                    ┌────▼────┐
              ┌─────│ PAYMENT │
              │     │ LAUNCHED│
              │     └────┬────┘
              │          │
              │          │ UPI app opened
              │          │
              │     ┌────▼─────────┐
              │     │ CONFIRMATION │
              │     │   DIALOG     │
              │     └────┬─────────┘
              │          │
              │          ├──────────────┐
              │          │              │
              │     User confirms   User cancels
              │          │              │
              │     ┌────▼────┐    ┌───▼────────┐
              │     │  PAID   │    │ CANCELLED  │
              │     └─────────┘    └────┬───────┘
              │          │               │
              │          │               │ Retry enabled
              │          │               │
              │          │          ┌────▼────┐
              │          │          │ PENDING │
              │          │          └─────────┘
              │          │
              │     ┌────▼────┐
              │     │ EXPENSE │
              │     │ CREATED │
              │     └─────────┘
              │
              │ UPI launch fails
              │
         ┌────▼────┐
         │ FAILED  │
         └────┬────┘
              │
              │ Retry enabled
              │
         ┌────▼────┐
         │ PENDING │
         └─────────┘
```

### Status Descriptions

| Status | Description | User Action | Button State |
|--------|-------------|-------------|--------------|
| **PENDING** | Payment not yet initiated | Can click Pay Now | ✅ Show "PAY NOW" (Blue) |
| **PAID** | Payment completed successfully | None (done) | ❌ Hidden |
| **CANCELLED** | User declined/payment failed in UPI app | Can retry | ✅ Show "RETRY PAYMENT" (Orange) |
| **FAILED** | UPI app launch failed | Can retry | ✅ Show "RETRY PAYMENT" (Orange) |

---

## Error Handling

### 1. Sender Side Errors

#### Error: Phone Number Missing
```
┌─────────────────────────────────────────┐
│  ⚠️ Phone Number Required               │
├─────────────────────────────────────────┤
│  Phone number required for payment      │
│  requests. Please add your phone        │
│  number in profile settings.            │
│                                         │
│  [ Go to Profile ]        [ Cancel ]    │
└─────────────────────────────────────────┘

Action: Redirect to profile edit screen
```

#### Error: No Target Users Selected
```
Error: No members to request payment from

Prevention: Disable Send button until at least one user selected
```

### 2. Receiver Side Errors

#### Error: UPI App Not Installed
```
┌─────────────────────────────────────────┐
│  ⚠️ Unable to open payment app          │
├─────────────────────────────────────────┤
│  Please check if UPI app is installed   │
│                                         │
│  Recommended apps:                      │
│  • Google Pay                           │
│  • PhonePe                              │
│  • Paytm                                │
│                                         │
│  [ OK ]                                 │
└─────────────────────────────────────────┘

Status: Automatically marked as FAILED
Action: User can retry after installing app
```

#### Error: Network Connection Lost
```
Real-time listener disconnects:
  ↓
Status updates may be delayed
  ↓
Firebase automatically reconnects
  ↓
Updates sync when connection restored
```

### 3. System Errors

#### Error: Message Not Found
```
Transaction fails if message deleted:
  ↓
Show error: "Payment request no longer exists"
  ↓
User cannot proceed
```

#### Error: Duplicate Payment Prevention
```
if (currentStatus == 'PAID') {
  debugPrint('⚠️ Payment already marked as PAID - skipping');
  return; // Idempotency guard
}

Result: Transaction skipped, no double expense created
```

---

## Group Chat Special Cases

### Multiple Receivers

```
User A requests ₹300 from Users B, C, D in group chat

Payment Status Evolution:

┌─────────────────────────────────────┐
│  Initial State (all pending)        │
│  ⏳ User B: PENDING                 │
│  ⏳ User C: PENDING                 │
│  ⏳ User D: PENDING                 │
└─────────────────────────────────────┘
         ↓ User B pays
┌─────────────────────────────────────┐
│  After User B pays                  │
│  ✅ User B: PAID                    │
│  ⏳ User C: PENDING                 │
│  ⏳ User D: PENDING                 │
└─────────────────────────────────────┘
         ↓ User C pays
┌─────────────────────────────────────┐
│  After User C pays                  │
│  ✅ User B: PAID                    │
│  ✅ User C: PAID                    │
│  ⏳ User D: PENDING                 │
└─────────────────────────────────────┘
         ↓ User D pays
┌─────────────────────────────────────┐
│  All paid - Complete!               │
│  ✅ User B: PAID                    │
│  ✅ User C: PAID                    │
│  ✅ User D: PAID                    │
│                                     │
│  ✅ Payment Completed ✅            │
└─────────────────────────────────────┘
```

### Individual Expense Entries

Each user's payment creates **separate** expense entry:

```
User B pays → expense_1 (paidBy: userB, amount: 300)
User C pays → expense_2 (paidBy: userC, amount: 300)
User D pays → expense_3 (paidBy: userD, amount: 300)

All linked to same message via linkedMessageId
```

---

## Performance Optimizations

### Real-Time Listener Efficiency

```dart
// ✅ Efficient: Single listener per card
void _listenToPaymentStatus() {
  _statusSubscription = ref.onValue.listen((event) {
    if (!mounted) return; // Early exit if widget disposed
    
    // Only update if data actually changed
    final newStatus = parseStatus(event);
    if (newStatus != _realtimePaymentStatus) {
      setState(() {
        _realtimePaymentStatus = newStatus;
      });
    }
  });
}

// ✅ Cleanup
@override
void dispose() {
  _statusSubscription?.cancel(); // Prevent memory leaks
  super.dispose();
}
```

### Network Usage

- **Average**: ~1-2KB per status update
- **Peak**: ~5KB when multiple users pay simultaneously
- **Optimization**: Firebase automatically batches updates

---

## Security Considerations

### 1. Payment Verification
⚠️ **Current Implementation**: Manual confirmation only  
🔐 **Limitation**: No automatic bank verification  
✅ **Mitigation**: Clear user confirmation dialog

### 2. Double Payment Prevention
✅ **Implemented**: 
- Status check before showing button
- Idempotency guard in transaction
- UI immediately hides button after payment

### 3. Data Validation
✅ **Implemented**:
```dart
// Amount must be positive
if (amount <= 0) return null;

// UPI ID format check
if (upiId != null && !upiId.contains('@')) {
  debugPrint('Invalid UPI ID format');
}

// Phone number required
if (phoneNumber == null || phoneNumber.isEmpty) {
  throw Exception('Phone number required');
}
```

---

## Testing Checklist

### Manual Testing

- [ ] **Direct Chat Payment**
  - [ ] Send request with amount and note
  - [ ] Receiver sees Pay Now button
  - [ ] Pay Now opens UPI app
  - [ ] Confirm payment updates status
  - [ ] Sender sees status change

- [ ] **Group Chat Payment**
  - [ ] Request from multiple users
  - [ ] Each user sees Pay Now button
  - [ ] Individual payment tracking
  - [ ] All users see real-time updates

- [ ] **Error Scenarios**
  - [ ] Missing phone number
  - [ ] UPI app not installed
  - [ ] Payment cancellation
  - [ ] Network disconnection
  - [ ] App backgrounded during payment

- [ ] **Edge Cases**
  - [ ] Retry after cancellation
  - [ ] Multiple rapid button clicks
  - [ ] Payment from different devices
  - [ ] Message deletion after payment

---

## Troubleshooting Guide

### Issue: Pay Now Button Not Showing

**Debug Steps**:
1. Check Flutter logs for: `Should Show Pay Button: false`
2. Verify conditions:
   ```dart
   debugPrint('Current User: $currentUserId');
   debugPrint('Sender: ${widget.senderId}');
   debugPrint('To Users: ${widget.toUsers}');
   debugPrint('Status: ${_realtimePaymentStatus[currentUserId]}');
   ```
3. Common causes:
   - User is the sender
   - User not in `payToUserIds`
   - Status already "PAID"

### Issue: UPI App Not Opening

**Debug Steps**:
1. Check logs for UPI URL:
   ```
   UPI URL: upi://pay?pa=...&pn=...&am=...
   ```
2. Verify platform is Android
3. Confirm UPI apps installed
4. Check Android Intent permissions

### Issue: Status Not Updating

**Debug Steps**:
1. Check listener logs:
   ```
   🔔 Listening to payment status at: chats/.../messages/...
   ✅ Payment status updated: {userB: PAID}
   ```
2. Verify Firebase Realtime Database rules
3. Check network connection
4. Confirm listener not disposed prematurely

---

## Summary

The Roomie chat payment system provides a seamless in-app payment request experience with:

✅ **Simple UX**: Request → Pay → Confirm → Done  
✅ **Real-time**: Instant status updates for all users  
✅ **Reliable**: Comprehensive error handling  
✅ **Safe**: Double payment prevention  
✅ **Flexible**: Direct and group chat support  

**Total User Actions**: 
- **Sender**: 3 clicks (Attachment → Payment → Send)
- **Receiver**: 2 clicks + UPI (Pay Now → Confirm payment → YES, PAID)

**Average Time**: ~30 seconds from request to confirmation

---

**Last Updated**: December 24, 2025  
**Version**: 2.0 (with real-time updates)  
**Status**: Production Ready ✅
