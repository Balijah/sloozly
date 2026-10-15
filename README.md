# Sloozly

**Wake up or pay up.** An iOS alarm app that withdraws money from your bank account when you hit snooze.

---

## Overview

Sloozly is a behavioral accountability app targeting young professionals (22-35) who struggle with morning discipline. Each snooze triggers a real bank withdrawal — starting at $5 and doubling with each subsequent snooze ($5 → $10 → $20 → $40...).

### Core Value Proposition
- Loss aversion is a powerful motivator
- Real financial consequences create real behavior change
- Users choose where their "penalty" money goes (charity partners)

---

## Project Status

| Phase | Status | Target Date |
|-------|--------|-------------|
| Planning | ✅ Complete | Jan 13, 2026 |
| MVP Development | 🔄 In Progress | Jan 27, 2026 |
| TestFlight Beta | ⏳ Pending | Jan 27 – Feb 3, 2026 |
| MMF Development | ⏳ Pending | Feb 17, 2026 |
| App Store Submission | ⏳ Pending | Feb 18, 2026 |
| App Store Launch | ⏳ Pending | Before Mar 1, 2026 |

---

## Tech Stack

### iOS App
- **Language:** Swift 5.9+
- **UI Framework:** SwiftUI
- **Minimum iOS:** 16.0
- **Architecture:** MVVM (Model-View-ViewModel)

### Backend
- **Runtime:** Node.js 20+
- **Framework:** Express.js
- **Database:** PostgreSQL (via Prisma ORM)
- **Authentication:** Firebase Auth
- **Hosting:** Railway (MVP) / AWS (Production)

### Payment Infrastructure
- **Bank Linking:** Plaid
- **Money Movement:** Stripe (ACH transfers)

---

## Project Structure

```
sloozly/
├── README.md
├── docs/                          # Documentation
│   ├── API.md                     # API endpoint documentation
│   ├── ARCHITECTURE.md            # System design decisions
│   └── DEPLOYMENT.md              # Deployment guides
│
├── backend/                       # Node.js API server
│   ├── prisma/
│   │   └── schema.prisma          # Database schema
│   ├── src/
│   │   ├── config/                # Environment & service config
│   │   │   ├── index.ts           # Config loader
│   │   │   ├── firebase.ts        # Firebase Admin SDK setup
│   │   │   ├── plaid.ts           # Plaid client setup
│   │   │   └── stripe.ts          # Stripe client setup
│   │   ├── controllers/           # Request handlers
│   │   │   ├── auth.controller.ts
│   │   │   ├── alarm.controller.ts
│   │   │   ├── bank.controller.ts
│   │   │   └── penalty.controller.ts
│   │   ├── middleware/            # Express middleware
│   │   │   ├── auth.middleware.ts # Firebase token verification
│   │   │   ├── error.middleware.ts
│   │   │   └── validation.middleware.ts
│   │   ├── models/                # Type definitions
│   │   │   ├── user.model.ts
│   │   │   ├── alarm.model.ts
│   │   │   └── penalty.model.ts
│   │   ├── routes/                # API route definitions
│   │   │   ├── index.ts           # Route aggregator
│   │   │   ├── auth.routes.ts
│   │   │   ├── alarm.routes.ts
│   │   │   ├── bank.routes.ts
│   │   │   └── penalty.routes.ts
│   │   ├── services/              # Business logic
│   │   │   ├── plaid.service.ts   # Bank linking logic
│   │   │   ├── stripe.service.ts  # Payment processing
│   │   │   ├── penalty.service.ts # Penalty calculation & execution
│   │   │   └── notification.service.ts
│   │   ├── utils/                 # Helper functions
│   │   │   ├── logger.ts
│   │   │   └── errors.ts          # Custom error classes
│   │   ├── app.ts                 # Express app setup
│   │   └── server.ts              # Entry point
│   ├── package.json
│   ├── tsconfig.json
│   └── .env.example
│
└── ios/                           # iOS application
    └── Sloozly/
        ├── App/
        │   ├── SloozlyApp.swift       # App entry point
        │   └── AppDelegate.swift      # Lifecycle & push notifications
        ├── Models/
        │   ├── User.swift
        │   ├── Alarm.swift
        │   └── Penalty.swift
        ├── ViewModels/
        │   ├── AuthViewModel.swift
        │   ├── AlarmViewModel.swift
        │   ├── BankViewModel.swift
        │   └── PenaltyViewModel.swift
        ├── Views/
        │   ├── Onboarding/
        │   │   ├── OnboardingView.swift
        │   │   └── OnboardingPageView.swift
        │   ├── Auth/
        │   │   ├── LoginView.swift
        │   │   └── SignUpView.swift
        │   ├── Alarm/
        │   │   ├── AlarmListView.swift
        │   │   ├── AlarmDetailView.swift
        │   │   ├── AlarmEditView.swift
        │   │   └── AlarmRingingView.swift
        │   ├── Bank/
        │   │   ├── BankLinkView.swift
        │   │   └── BankStatusView.swift
        │   └── Settings/
        │       ├── SettingsView.swift
        │       └── PenaltyHistoryView.swift
        ├── Services/
        │   ├── APIService.swift       # Backend communication
        │   ├── AuthService.swift      # Firebase Auth wrapper
        │   ├── AlarmService.swift     # Local alarm scheduling
        │   ├── PlaidService.swift     # Plaid Link integration
        │   └── NotificationService.swift
        ├── Utilities/
        │   ├── Constants.swift
        │   ├── Extensions.swift
        │   └── KeychainManager.swift
        └── Resources/
            ├── Assets.xcassets
            ├── Info.plist
            └── GoogleService-Info.plist
```

---

## Feature Specifications

### MVP Features (v0.1)
- [x] User authentication (email/password via Firebase)
- [ ] Bank account linking (Plaid Link)
- [ ] Single alarm creation (time only)
- [ ] Snooze triggers $5 flat penalty
- [ ] ACH withdrawal to operator Stripe account
- [ ] Failed transfer handling (log, notify, no retry)
- [ ] Basic functional UI

### MMF Features (v1.0)
- [ ] Escalating penalties ($5 → $10 → $20 → $40...)
- [ ] Multiple alarms with repeat scheduling (weekdays, weekends, custom)
- [ ] "Sleep in" days (skip penalties)
- [ ] Charity selection (3-5 partners)
- [ ] Penalty history and lifetime stats
- [ ] Polished onboarding flow
- [ ] Refined UI/UX

### Future Considerations (v1.x+)
- [ ] Social accountability (share stats with friends)
- [ ] Streak tracking and achievements
- [ ] Custom penalty amounts
- [ ] Android app
- [ ] Apple Watch companion

---

## API Endpoints

### Authentication
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/auth/register` | Create new user account |
| POST | `/api/auth/login` | Authenticate user |
| GET | `/api/auth/me` | Get current user profile |

### Bank
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/bank/link-token` | Generate Plaid Link token |
| POST | `/api/bank/exchange-token` | Exchange public token for access token |
| GET | `/api/bank/status` | Get linked bank account status |
| DELETE | `/api/bank/unlink` | Remove linked bank account |

### Alarms
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/alarms` | List user's alarms |
| POST | `/api/alarms` | Create new alarm |
| PUT | `/api/alarms/:id` | Update alarm |
| DELETE | `/api/alarms/:id` | Delete alarm |

### Penalties
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/penalties/trigger` | Trigger penalty (called on snooze) |
| GET | `/api/penalties/history` | Get penalty history |
| GET | `/api/penalties/stats` | Get penalty statistics |

---

## Environment Variables

### Backend (.env)
```bash
# Server
NODE_ENV=development
PORT=3000

# Database
DATABASE_URL=postgresql://user:password@localhost:5432/sloozly

# Firebase Admin
FIREBASE_PROJECT_ID=your-project-id
FIREBASE_PRIVATE_KEY=your-private-key
FIREBASE_CLIENT_EMAIL=your-client-email

# Plaid
PLAID_CLIENT_ID=your-client-id
PLAID_SECRET=your-secret
PLAID_ENV=sandbox  # sandbox | development | production

# Stripe
STRIPE_SECRET_KEY=sk_test_xxx
STRIPE_WEBHOOK_SECRET=whsec_xxx
```

### iOS (Constants.swift)
```swift
enum Environment {
    static let apiBaseURL = "https://api.sloozly.com"  // Or localhost for dev
    static let plaidEnv = "sandbox"
}
```

---

## Development Setup

### Prerequisites
- Xcode 15+
- Node.js 20+
- PostgreSQL 15+
- Plaid developer account
- Stripe developer account
- Firebase project

### Backend Setup
```bash
cd backend
npm install
cp .env.example .env
# Edit .env with your credentials
npx prisma migrate dev
npm run dev
```

### iOS Setup
```bash
cd ios/Sloozly
# Open Sloozly.xcodeproj in Xcode
# Add GoogleService-Info.plist from Firebase Console
# Build and run on simulator or device
```

---

## Testing Strategy

### MVP Testing (2-5 users)
1. Deploy backend to Railway
2. Distribute iOS app via TestFlight
3. Monitor for:
   - Successful bank linking
   - Alarm triggering behavior
   - Payment processing success/failure
   - User feedback on UX

### Metrics to Track
- Bank link completion rate
- Snooze vs. dismiss ratio
- Payment success rate
- User retention (do they keep using it?)

---

## Failed Transfer Protocol

When an ACH transfer fails:
1. Log failure internally (reason, timestamp, amount)
2. Notify user: "Your $X penalty couldn't be processed. No charge was made."
3. Do NOT retry automatically (avoids overdraft issues)
4. After 3 failures: prompt user to re-link bank account
5. User does NOT accumulate "debt" — failed = no penalty

---

## Legal & Compliance

### Before App Store Submission
- [ ] Register LLC
- [ ] Draft Terms of Service
- [ ] Draft Privacy Policy
- [ ] Plaid compliance review
- [ ] Apple Developer Program membership ($99/year)

### Key Compliance Points
- Clear disclosure of how penalties work
- User consent before any money movement
- Transparent charity partner information
- Easy account deletion / bank unlinking

---

## Contributing

This is currently a solo project. If you're reading this and want to contribute, open an issue first to discuss.

---

## License

Proprietary. All rights reserved.

---

## Contact

**Developer:** Burhan Khan

---

*Last updated: January 13, 2026*
