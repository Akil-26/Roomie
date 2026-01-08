# Roomie

**A trust-first room rental platform connecting property owners with students/tenants.**

Built with Flutter + Firebase. Designed for real-world use with proper role separation and safety guards.

---

## 🎯 Problem Statement

Finding shared accommodation is chaotic:
- **Students** struggle to find trustworthy rooms and transparent payment processes
- **Property owners** have no simple way to manage tenants and track rent payments
- Existing solutions mix roles, creating confusion and trust issues

**Roomie solves this** by creating a clear separation between Owner and Roommate experiences.

---

## 🏗️ Architecture Overview

| Layer | Technology |
|-------|------------|
| Frontend | Flutter (cross-platform) |
| Auth | Firebase Authentication (Google, Phone OTP) |
| Database | Cloud Firestore |
| Real-time Chat | Firebase Realtime Database |
| Media Storage | Cloudinary (unsigned uploads) |
| Payments | Razorpay Integration |

---

## 🔑 Key Design Decisions

### 1. Owner ≠ Roommate (Strict Role Separation)
- **Owner**: Property manager who creates rooms, receives payments, approves join requests
- **Roommate**: Tenant who joins rooms, pays rent, uses shared amenities
- Owner is NEVER listed as a "member" of the room
- This prevents authority confusion and trust violations

### 2. Room Persistence (Stable Foundation)
- Rooms are never deleted when members leave
- `room_members` collection tracks membership history separately
- Rooms can be deactivated but data is preserved
- Enables future features like analytics and re-occupancy

### 3. Safety Guards Throughout
- Double-action protection on all critical buttons (payments, approvals)
- UI locks during processing to prevent duplicate submissions
- App resume re-validation for stale state detection
- Network failure recovery with user-friendly messages

### 4. Trust by Design
- Owner sees aggregated payment status (who paid/hasn't) without individual snooping
- Roommates only see their own payment history
- Join requests require explicit approval
- Room visibility toggle gives owners control without micromanagement

---

## 📱 Core User Flows

### For Students (Roommates)
1. Browse available rooms with filters
2. Request to join a room
3. Wait for owner approval
4. Pay rent through integrated payment gateway
5. Chat with roommates

### For Property Owners
1. Create room listing with photos and details
2. Review and approve/reject join requests
3. Receive rent payments directly
4. Monitor room health via Owner Dashboard
5. Control room visibility (open/close to new requests)

---

## 🗂️ Project Structure

```
lib/
├── core/                    # Constants, themes, utilities
├── data/
│   ├── datasources/         # Firebase services (auth, groups, payments)
│   └── models/              # Data models (room, member, payment)
├── presentation/
│   ├── screens/             # UI screens organized by feature
│   └── widgets/             # Reusable components
└── main.dart                # App entry point
```

---

## 🚀 Getting Started

### Prerequisites
- Flutter SDK (3.x+)
- Firebase project with Firestore, Auth, and Realtime Database enabled
- Cloudinary account (for image uploads)
- Razorpay account (for payments - optional)

### Setup

1. Clone the repository
```bash
git clone https://github.com/your-username/roomie.git
cd roomie
```

2. Install dependencies
```bash
flutter pub get
```

3. Configure Firebase
- Add your `google-services.json` (Android) and `GoogleService-Info.plist` (iOS)
- Update `firebase_options.dart` with your project config

4. Run the app
```bash
flutter run
```

### Environment Variables (Optional)
```bash
flutter run \
  --dart-define=CLOUDINARY_CLOUD_NAME=your_cloud_name \
  --dart-define=CLOUDINARY_UPLOAD_PRESET=your_preset
```

---

## 🔒 Security Notes

- Never embed API secrets in client code
- Cloudinary uses unsigned upload presets (safe for client)
- Razorpay keys should be configured securely
- Firestore rules enforce role-based access

---

## 📊 Key Features

| Feature | Owner | Roommate |
|---------|:-----:|:--------:|
| Create Room | ✅ | ❌ |
| Join Room | ❌ | ✅ |
| Approve Requests | ✅ | ❌ |
| Pay Rent | ❌ | ✅ |
| Receive Payments | ✅ | ❌ |
| View Own Payments | ✅ | ✅ |
| View All Payments | ✅ | ❌ |
| Owner Dashboard | ✅ | ❌ |
| Room Visibility Control | ✅ | ❌ |
| Room Chat | ✅ | ✅ |

---

## 🎨 UI/UX Principles

1. **Empty states explain next steps** - No confusing blank screens
2. **Role badges are always visible** - Users always know their context
3. **Actions have visual feedback** - Loading states, success/error messages
4. **Consistent terminology** - "Room", "Owner", "Roommate" throughout

---

## 📝 Development Notes

### Frozen Architecture (Steps 1-7)
The core architecture is finalized and should not be modified:
- Room persistence model
- Owner/Roommate role separation
- Payment flow
- Join request approval flow
- Safety guards (double-action protection)
- Owner dashboard

### Future Considerations
- Push notifications for real-time updates
- Payment reminders (owner-initiated only)
- Room analytics for owners
- Multi-property management

---

## 📄 License

MIT License - See [LICENSE](LICENSE) file for details.

---

**Made with 💙 using Flutter**
