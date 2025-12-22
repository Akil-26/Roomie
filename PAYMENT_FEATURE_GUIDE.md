# 💰 Payment Request Feature - Implementation Guide

## Overview
This feature enables users to request and make payments directly through chat messages. When a user sends a payment-related message (e.g., "send money $10"), the system automatically:
1. Detects the payment request
2. Shows a "Pay Now" button
3. Opens UPI apps with pre-filled amount and "Roomie expense" note
4. Tracks the payment in the Expense page

---

## 🚀 Features Implemented

### 1. **Payment Message Detection**
- Automatically detects payment requests in chat messages
- Supports multiple formats:
  - "send money $10"
  - "pay $10"
  - "send $10"
  - "₹100" or "Rs 100"
  - "need $50"

### 2. **Smart User Targeting**
- **Direct Chat**: Payment request automatically targets the other person
- **Group Chat**: 
  - Mention specific users: "send money $10 @john @jane"
  - No mentions: All group members (except sender) will see Pay Now button

### 3. **UPI Integration**
- Opens installed UPI apps (GPay, PhonePe, Paytm, etc.)
- Pre-fills:
  - Amount
  - Note: "Roomie expense - [description]"
  - Payee name

### 4. **Expense Tracking**
- Payments made via chat are automatically saved
- Appears in "Roomie Expense" tab in User Expenses screen
- Only shows payments made through chat, not regular group expenses
- Tracks:
  - Who paid
  - How much
  - When
  - Payment status

---

## 📁 Files Added/Modified

### New Files Created:
1. **`lib/data/models/payment_request_model.dart`**
   - Model for payment requests
   - Tracks payment status per user

2. **`lib/core/utils/payment_message_parser.dart`**
   - Detects payment messages using regex patterns
   - Extracts amount and description
   - Identifies mentioned users

3. **`lib/data/datasources/upi_payment_service.dart`**
   - Handles UPI payment intents
   - Manages payment requests in Firestore
   - Updates payment statuses

4. **`lib/presentation/widgets/payment_request_card.dart`**
   - UI widget showing payment details
   - "Pay Now" button
   - User selection for group payments

### Modified Files:
1. **`pubspec.yaml`**
   - Added `android_intent_plus: ^5.1.0` for UPI integration

2. **`lib/presentation/widgets/message_bubble_widget.dart`**
   - Added payment detection in text messages
   - Integrated PaymentRequestCard widget
   - User targeting logic

3. **`lib/data/datasources/expense_service.dart`**
   - Added `createExpenseFromPayment()` method
   - Added `getChatPaymentExpenses()` stream
   - Links chat payments to expenses

4. **`lib/presentation/screens/expenses/user_expenses_s.dart`**
   - Updated to show only chat payment expenses in Roomie Expense tab
   - Separate from regular group expenses

---

## 🎯 How to Use

### For Users Requesting Payment:

1. **Direct Chat:**
   ```
   "Hey, send money $20 for dinner"
   ```
   - The other person will see a Pay Now button

2. **Group Chat (All Members):**
   ```
   "send $30 for groceries"
   ```
   - All group members (except you) will see Pay Now button

3. **Group Chat (Specific Members):**
   ```
   "pay $15 @john @sarah for pizza"
   ```
   - Only @john and @sarah will see Pay Now button

### For Users Making Payment:

1. Click **"Pay Now"** button on payment request
2. Select UPI app (GPay, PhonePe, etc.)
3. The app opens with:
   - Amount pre-filled
   - Note: "Roomie expense - [description]"
4. Complete payment in UPI app
5. Payment is automatically tracked in Expense page

---

## 🔧 Technical Details

### Firebase Collections:
- **`payment_requests`**: Stores all payment requests
- **`expenses`**: Links payments to expenses with metadata

### Payment Flow:
```
User sends message with payment
         ↓
Parser detects payment pattern
         ↓
PaymentRequestCard renders
         ↓
User clicks Pay Now
         ↓
Create expense entry
         ↓
Launch UPI app
         ↓
Update payment status
         ↓
Show in Expense page
```

### UPI Intent Format:
```
upi://pay?pa=UPI_ID&pn=NAME&am=AMOUNT&tn=Roomie expense&cu=INR
```

---

## 📱 Platform Support

- ✅ **Android**: Full UPI integration support
- ⚠️ **iOS**: UPI not available (iOS limitation)
- ⚠️ **Web**: Not supported

---

## 🎨 UI Components

### Payment Request Card:
- 💳 Payment icon + amount
- 📝 Description (if provided)
- 👥 Target users (for group payments)
- 🔘 "Pay Now" button (only for payers)
- ℹ️ Info message for requester

### Expense Page:
- Shows only chat-initiated payments
- Separate from regular group expenses
- Filter by: `metadata.source = 'chat_payment'`

---

## 🔐 Security & Data

- Payment requests stored in Firestore
- Tracks status: `pending` → `initiated` → `completed`/`failed`
- Links to chat messages for context
- Expense entries have metadata:
  ```dart
  {
    'source': 'chat_payment',
    'chatId': '...',
    'messageId': '...',
    'isGroupPayment': true/false
  }
  ```

---

## 🚨 Important Notes

1. **No Real Payment Processing**: This feature only opens UPI apps. Actual payment happens outside the app.

2. **Payment Confirmation**: Currently auto-marks as completed. In production, you'd need:
   - UPI payment gateway integration
   - Webhook callbacks for payment verification
   - Manual confirmation option

3. **Permissions**: Requires no special permissions (uses Android Intents)

4. **Testing**: 
   - Test on physical Android device with UPI apps installed
   - Emulator won't have UPI apps

---

## 🎯 Future Enhancements

1. **Payment Gateway Integration**: Real-time payment verification
2. **Payment History**: Detailed transaction logs
3. **Split Payment**: Multiple users paying different amounts
4. **Recurring Payments**: Scheduled payment requests
5. **Payment Reminders**: Notifications for pending payments
6. **Manual Marking**: Let users mark payments as completed manually

---

## 🐛 Troubleshooting

### Issue: Pay Now button not showing
- **Check**: Message must contain valid payment pattern
- **Solution**: Use "send money $10" format

### Issue: UPI app not opening
- **Check**: Device is Android
- **Check**: UPI apps are installed
- **Solution**: Install GPay/PhonePe/Paytm

### Issue: Expenses not showing in tab
- **Check**: Payment must be completed
- **Check**: Filter is set to `chat_payment` source
- **Solution**: Verify Firestore metadata

---

## 📞 Support

For issues or questions:
1. Check Firestore console for payment_requests
2. Check app logs for UPI intent errors
3. Verify expense service is filtering correctly

---

**Implementation Date**: December 17, 2025  
**Version**: 1.0.0  
**Status**: ✅ Completed
