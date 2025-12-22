# Payment Request Implementation - Complete Guide

## Overview
சரியான payment request feature implement பண்ணிட்டேன் with all requirements.

## Features Implemented

### 1. **Phone Number Integration** 📱
- Requester-ன் phone number automatically fetch பண்ணும்
- MessageModel-ல் `payToPhoneNumber` field added
- UPI payment-ல் phone number pass ஆகும்

### 2. **UPI Payment with Auto-Fill** 💳
When "Pay Now" button click:
- **Amount**: Auto-filled (₹50, ₹100, etc.)
- **Phone Number**: Requester-ன் phone number auto-filled
- **Note**: "Roomie expence" automatically added
- **UPI Apps**: GPay, PhonePe, Paytm எல்லாம் show ஆகும்

### 3. **Payment Confirmation** ✅
- User payment பண்ணின பிறகு confirmation dialog show ஆகும்
- "Yes, Paid" click பண்ணா மட்டும் payment record ஆகும்
- Manual confirmation because UPI apps don't send callback

### 4. **Payment Status Display** 📊
Chat-ல payment message-க்கு கீழே:
- **Before Payment**: "Pay Now" button show ஆகும்
- **After Payment**: "Paid by [Name]" green indicator show ஆகும்
- Requester-க்கு: "You sent this payment request" show ஆகும்

### 5. **Roomie Expense Integration** 💰
- Payment confirm பண்ணினா automatically expense entry create ஆகும்
- Note-ல "Roomie expence" irukum
- Expense page-ல all payments show ஆகும்

## How It Works - Step by Step

### Sending Payment Request:
```
1. User clicks Payment button in chat
2. Enters amount + selects users + optional description
3. System fetches sender's phone number from Firestore
4. Creates payment request message with:
   - type: MessageType.paymentRequest
   - paymentAmount: 50.0
   - payToUserIds: ["user1", "user2"]
   - paymentNote: "description"
   - payToPhoneNumber: "7904122501"
5. Message sent to chat
```

### Receiving & Paying:
```
1. Receiver sees payment request card with "Pay Now" button
2. Clicks "Pay Now"
3. System creates expense entry in Firestore
4. Launches UPI app with:
   - Amount: ₹50
   - Payee: Sender's name
   - Phone: 7904122501
   - Note: "Roomie expence - [description]"
5. User selects GPay/PhonePe and completes payment
6. Returns to Roomie app
7. Sees confirmation dialog: "Did you complete payment?"
8. Clicks "Yes, Paid"
9. Payment marked as completed
10. "Paid by [Username]" shows in chat
11. Expense updated in Roomie Expense page
```

## Files Modified

### Core Data Model:
- **`lib/data/models/message_model.dart`**
  - Added fields: `payToPhoneNumber`, `paymentCompletedBy`
  - Updated serialization/deserialization
  - Updated copyWith method

### Services:
- **`lib/data/datasources/chat_service.dart`**
  - Updated `sendMessage()` with `payToPhoneNumber` parameter
  - Updated `sendGroupMessage()` with `payToPhoneNumber` parameter

- **`lib/data/datasources/upi_payment_service.dart`**
  - Added `payeePhoneNumber` parameter
  - Updated UPI URL to include phone number (mc parameter)
  - Changed note to "Roomie expence" (with 'c')

### UI Components:
- **`lib/presentation/screens/chat/chat_screen.dart`**
  - Fetches current user phone from Firestore
  - Passes phone number when sending payment request

- **`lib/presentation/widgets/payment_request_card.dart`**
  - Added `requestedByPhone` and `completedBy` parameters
  - Added payment confirmation dialog
  - Shows "Paid by [Name]" when completed
  - Hides "Pay Now" button after payment

- **`lib/presentation/widgets/message_bubble_widget.dart`**
  - Passes phone number and completion status to PaymentRequestCard
  - Added debug prints for all payment fields

## Testing Steps

### 1. Send Payment Request:
```
1. Login as User A (with phone: 7904122501)
2. Open chat with User B
3. Click attachment menu → Payment button
4. Enter: ₹50, description: "Dinner"
5. Select User B
6. Click Send
```

### 2. Pay Request:
```
1. Login as User B
2. Open chat with User A
3. See payment request card with "Pay Now"
4. Click "Pay Now"
5. GPay/PhonePe opens with:
   - Amount: ₹50.00
   - Phone: 7904122501
   - Note: "Roomie expence - Dinner"
6. Complete payment in app
7. Return to Roomie
8. See confirmation dialog
9. Click "Yes, Paid"
10. See green "Paid by [Your Name]" indicator
```

### 3. Check Expense Page:
```
1. Go to Roomie Expense tab
2. Should see entry:
   - Amount: ₹50
   - From: User B
   - To: User A
   - Note: "Dinner"
   - Source: "chat_payment"
```

## Important Notes

### Phone Number Format:
- Stored as string: "7904122501"
- No country code needed for India
- UPI apps handle formatting

### Note: "Roomie expence" vs "Roomie expense"
- Intentionally using "expence" (user's spelling)
- This helps filter payments in expense page
- All payment notes will have this exact string

### Payment Confirmation:
- Manual confirmation required because:
  - UPI apps don't send callback to our app
  - No way to auto-detect payment completion
  - User must confirm payment was successful

### Expense Tracking:
- All confirmed payments automatically create expense entry
- Metadata includes:
  - `source: "chat_payment"`
  - `chatId`: For reference
  - `messageId`: To link back to payment request

## Future Enhancements

### 1. SMS Reading (Optional):
```dart
// Can read SMS to auto-confirm payment
// Requires SMS permission
// Parse payment success SMS from banks
```

### 2. Split Payments:
```dart
// For group payments, track multiple payers
// Each person pays their share
// Show individual payment status
```

### 3. Payment Reminders:
```dart
// Send notification if payment not done in X days
// Auto-reminder feature
```

### 4. Payment History:
```dart
// Dedicated payment history screen
// Filter by paid/pending
// Export to CSV
```

## Debugging

If payment button doesn't show:
```
Check console for:
📨 Message: "..."
   Type: MessageType.paymentRequest
   Payment Amount: 50.0
   Pay To Users: [user_ids]
   Phone: 7904122501

If missing, message type not set correctly.
```

If UPI doesn't open:
```
Check console for:
🚀 Initiating UPI Payment
Amount: ₹50.0
Payee: Name
Phone: 7904122501
UPI URL: upi://pay?...

If URL wrong, UPI app won't recognize.
```

## Summary
✅ Phone number integration
✅ UPI auto-fill (amount, phone, note)
✅ Payment confirmation dialog
✅ "Paid by [Name]" display in chat
✅ Roomie Expense page integration
✅ Note: "Roomie expence" for tracking

All requirements சரியா implement பண்ணிட்டேன்! 🎉
