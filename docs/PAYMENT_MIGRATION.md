# Roomie Payment Gateway Migration
## Razorpay → Stripe (Test Mode)

**Migration Date:** January 2026  
**Status:** Complete - Test Mode Ready

---

## 🎯 Migration Goals

1. ✅ Replace Razorpay with Stripe
2. ✅ Keep business logic unchanged
3. ✅ Maintain backwards compatibility with existing payments
4. ✅ Create abstraction for future gateway switches
5. ✅ Preserve Razorpay code as fallback

---

## 📁 File Structure

```
lib/data/datasources/payments/
├── payment_service.dart       # Gateway-independent interface (NEVER depends on Stripe/Razorpay)
├── stripe_service.dart        # Stripe implementation
└── razorpay_old/
    └── razorpay_service.dart  # Original Razorpay code (frozen backup)
```

---

## 🔑 Environment Configuration

Add to `.env`:
```env
# STRIPE PAYMENT GATEWAY (TEST MODE)
STRIPE_PUBLISHABLE_KEY=pk_test_YOUR_KEY_HERE
STRIPE_SECRET_KEY=sk_test_YOUR_KEY_HERE
```

⚠️ **CRITICAL:** Never use `sk_live_` or `pk_live_` keys in development!

---

## 🧪 Test Mode Rules

### Test Card Number
```
4242 4242 4242 4242
```
- Expiry: Any future date
- CVC: Any 3 digits

### Test Scenarios
| Scenario | Card Number |
|----------|-------------|
| Success | 4242 4242 4242 4242 |
| Decline | 4000 0000 0000 0002 |
| Auth Required | 4000 0025 0000 3155 |
| Insufficient Funds | 4000 0000 0000 9995 |

---

## 🔄 What Changed

### 1. Dependencies (`pubspec.yaml`)
```yaml
# OLD
razorpay_flutter: ^1.3.7

# NEW
# razorpay_flutter: ^1.3.7  (commented out)
flutter_stripe: ^11.4.0
```

### 2. Service Layer
- `RazorpayService` → `StripeService`
- Both implement `PaymentGateway` interface
- Old Razorpay code preserved in `payments/razorpay_old/`

### 3. UI Components
- Razorpay blue (#072654) → Stripe purple (#6366F1)
- "Pay with Razorpay" → "Pay with Card"
- Added test mode indicator

### 4. Database Schema
- Added `gateway` field to payment records
- Legacy records default to `gateway: 'razorpay'`
- New records use `gateway: 'stripe'`

---

## 🧠 Mental Model

```
┌─────────────────────────────────────────────────────┐
│                      UI Layer                       │
│    (payment_request_card.dart, room_payments_s)    │
└─────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────┐
│              Payment Abstraction Layer              │
│              (payment_service.dart)                 │
│        ┌───────────────────────────────────┐       │
│        │    PaymentGateway Interface       │       │
│        │    - createPayment()              │       │
│        │    - verifyPayment()              │       │
│        │    - getPaymentStatus()           │       │
│        └───────────────────────────────────┘       │
└─────────────────────────────────────────────────────┘
                         │
          ┌──────────────┴──────────────┐
          ▼                              ▼
┌──────────────────┐           ┌──────────────────┐
│  StripeService   │           │  RazorpayService │
│    (ACTIVE)      │           │   (BACKUP)       │
└──────────────────┘           └──────────────────┘
          │                              │
          ▼                              ▼
┌──────────────────┐           ┌──────────────────┐
│   Stripe API     │           │   Razorpay API   │
│  (Test Mode)     │           │   (Inactive)     │
└──────────────────┘           └──────────────────┘
```

---

## 🔐 What Did NOT Change

- ✅ Rent logic
- ✅ Room logic
- ✅ Owner logic
- ✅ Split logic
- ✅ Database schema (mostly - added `gateway` field)
- ✅ Payment history structure
- ✅ Notification flow

---

## 🔄 Switching Gateways (Future)

To switch back to Razorpay or another gateway:

1. **Quick Switch:**
   ```dart
   // In payment_service.dart
   PaymentGatewayFactory.activeGateway = SupportedGateway.razorpay;
   ```

2. **Or Replace Service Import:**
   ```dart
   // Change import in room_payment_service.dart
   import 'package:roomie/data/datasources/payments/razorpay_old/razorpay_service.dart';
   ```

---

## 📋 Files Modified

| File | Change |
|------|--------|
| `pubspec.yaml` | Added flutter_stripe, commented razorpay_flutter |
| `.env` | Added Stripe keys |
| `main.dart` | Added Stripe initialization |
| `payment_request_card.dart` | Replaced Razorpay UI with Stripe |
| `room_payments_s.dart` | Updated service imports |
| `room_payment_service.dart` | Updated to use StripeService |
| `payment_record_model.dart` | Added `gateway` field |

---

## 📋 Files Created

| File | Purpose |
|------|---------|
| `payments/payment_service.dart` | Gateway-independent interface |
| `payments/stripe_service.dart` | Stripe implementation |
| `payments/razorpay_old/razorpay_service.dart` | Frozen backup |
| `widgets/stripe_payment_sheet.dart` | Stripe payment UI widget |

---

## 🚀 Production Checklist

When ready to go live:

- [ ] Get Stripe live keys from dashboard
- [ ] Update `.env.prod` with `pk_live_` and `sk_live_` keys
- [ ] Set up Stripe webhook endpoint
- [ ] Test in Stripe test mode thoroughly
- [ ] Run small live test transaction
- [ ] Monitor Stripe dashboard for errors

---

## 🐛 Troubleshooting

### "Stripe publishable key not found"
→ Check `.env` file has `STRIPE_PUBLISHABLE_KEY`

### Payment fails immediately
→ Ensure `flutter_stripe` is properly initialized in `main.dart`

### UI shows Razorpay colors/text
→ Run `flutter clean && flutter pub get`

### Old payments show wrong gateway
→ Legacy records default to `gateway: 'razorpay'` - this is expected

---

## 📞 Support

For Stripe integration issues:
- Stripe Docs: https://stripe.com/docs
- Flutter Stripe: https://pub.dev/packages/flutter_stripe

For switching back to Razorpay:
- Code preserved in `payments/razorpay_old/`
- Uncomment `razorpay_flutter` in `pubspec.yaml`
