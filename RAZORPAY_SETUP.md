# Razorpay Payment Integration Setup

## 🚀 Quick Setup

### 1. Get Razorpay API Keys

1. Go to [Razorpay Dashboard](https://dashboard.razorpay.com/)
2. Sign up or login
3. Go to **Settings → API Keys**
4. Generate your **Test** and **Live** API keys

### 2. Configure API Keys

Open `lib/data/datasources/razorpay_service.dart` and update the keys:

```dart
// Replace these with your actual Razorpay API keys
static const String _testApiKey = 'rzp_test_YOUR_KEY_HERE';
static const String _liveApiKey = 'rzp_live_YOUR_KEY_HERE';

// Set to true when ready for production
static const bool _isProduction = false;
```

### 3. (Optional) Use Environment Variables

For better security, store keys in `.env`:

```env
RAZORPAY_TEST_KEY=rzp_test_xxxxx
RAZORPAY_LIVE_KEY=rzp_live_xxxxx
```

Then update the service to read from environment:

```dart
import 'package:flutter_dotenv/flutter_dotenv.dart';

static String get _testApiKey => dotenv.env['RAZORPAY_TEST_KEY'] ?? '';
static String get _liveApiKey => dotenv.env['RAZORPAY_LIVE_KEY'] ?? '';
```

## 📱 Features

- ✅ **Secure Payments** - All payments processed through Razorpay's secure checkout
- ✅ **Multiple Payment Methods** - UPI, Cards, Net Banking, Wallets
- ✅ **Payment History** - Automatic tracking in Firestore
- ✅ **Real-time Status** - Instant payment status updates
- ✅ **Retry Logic** - Automatic retry for failed payments

## 💰 Payment Flow

1. User clicks "Pay with Razorpay" button
2. Razorpay checkout opens with amount and details
3. User selects payment method and completes payment
4. On success:
   - Payment status updated in chat message
   - Payment history saved to sender's and recipient's Firestore
5. On failure:
   - Error message shown
   - User can retry

## 📊 Payment History

Payment history is stored in:
- `users/{userId}/payment_history` - Personal history
- `payments/{paymentId}` - Global admin tracking

Fields saved:
- Payment ID (from Razorpay)
- Sender and Recipient details
- Amount and currency
- Status (success/failed)
- Timestamp
- Chat/Message reference

## 🔒 Security Notes

1. **Never hardcode live API keys** - Use environment variables
2. **Server-side verification** - For production, verify payments on your server
3. **Webhook integration** - Set up Razorpay webhooks for reliable status updates

## 🧪 Testing

Use Razorpay test credentials:
- Test Card: `4111 1111 1111 1111`
- Any future expiry date
- Any CVV
- UPI: Use any test UPI ID

## 📞 Support

- [Razorpay Documentation](https://razorpay.com/docs/)
- [Flutter Integration Guide](https://razorpay.com/docs/payments/payment-gateway/android-integration/standard/flutter/)
