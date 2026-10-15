# Sloozly

**Wake up or pay up.** An iOS alarm app that charges a penalty to your bank account when you hit snooze.

## Overview

Sloozly is a behavioral accountability app for people who struggle with
morning discipline. Each snooze triggers a flat penalty charge (default $5)
from your linked bank account. Penalties are charged by Sloozly — there is
no charity component.

### Status

Sandbox-only beta. All payment processing uses **Stripe test mode** and
**Plaid sandbox**. No real money is moved.

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| iOS app | Swift / SwiftUI (iOS 16+) |
| Backend | Node.js 20+ / Express / TypeScript |
| Database | PostgreSQL via Prisma ORM |
| Auth | Firebase Auth |
| Bank linking | Plaid (sandbox) |
| Payments | Stripe ACH via PaymentIntents (test mode) |

---

## Project Structure

```
sloozly/
├── backend/              # Node.js API server
│   ├── prisma/
│   │   ├── schema.prisma
│   │   └── migrations/
│   ├── src/
│   │   ├── config/       # Env, DB, Stripe, Plaid, Firebase setup
│   │   ├── controllers/  # Route handlers
│   │   ├── middleware/    # Auth, validation, error handling
│   │   ├── routes/       # Express route definitions
│   │   ├── services/     # Business logic (penalty, stripe, plaid)
│   │   ├── test/         # Test setup and helpers
│   │   └── utils/        # Logger, custom errors
│   ├── vitest.config.ts
│   ├── tsconfig.json
│   └── .env.example
├── ios/Sloozly/          # SwiftUI iOS app
├── docs/
│   └── payment-design.md # Payment states & idempotency design
└── .github/workflows/
    └── backend-ci.yml    # Type-check + tests on PR
```

---

## Backend Setup

### Prerequisites

- Node.js 20+
- PostgreSQL 15+
- Plaid sandbox credentials
- Stripe test-mode API keys
- Firebase project

### Quick Start

```bash
cd backend
npm install
cp .env.example .env
# Edit .env with your credentials (all sandbox/test)

# Generate Prisma client
npx prisma generate

# Run migrations (requires a running PostgreSQL)
npx prisma migrate dev

# Start dev server
npm run dev
```

### Scripts

| Command | Description |
|---------|-------------|
| `npm run dev` | Start dev server with hot reload |
| `npm run build` | Compile TypeScript |
| `npm run typecheck` | Type-check without emitting |
| `npm test` | Run tests (vitest) |
| `npm run test:watch` | Run tests in watch mode |
| `npm run db:migrate` | Run Prisma migrations |
| `npm run db:push` | Push schema to DB (no migration) |

### Environment Variables

See [`backend/.env.example`](backend/.env.example) for all required
variables and documentation.

Key settings:

| Variable | Default | Description |
|----------|---------|-------------|
| `PENALTY_AMOUNT_CENTS` | `500` | Flat penalty per snooze ($5.00) |
| `PENALTY_DAILY_CAP_CENTS` | `2500` | Max daily penalties ($25.00) |
| `PLAID_ENV` | `sandbox` | Must be `sandbox` for beta |
| `STRIPE_SECRET_KEY` | — | Must be `sk_test_*` for beta |

---

## iOS Setup

```bash
cd ios/Sloozly
# Open in Xcode
# Add GoogleService-Info.plist from Firebase Console
# Build and run on simulator
```

> The iOS app cannot be compiled in a Linux environment. Swift edits in
> this repo are minimal and clearly flagged.

---

## API Endpoints

### Auth
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/auth/register` | Register after Firebase signup |
| GET | `/api/auth/me` | Get current user profile |
| PUT | `/api/auth/me` | Update profile |
| DELETE | `/api/auth/me` | Soft-delete account |

### Bank
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/bank/link-token` | Get Plaid Link token |
| POST | `/api/bank/exchange-token` | Link bank account |
| GET | `/api/bank/status` | Get bank account status |
| DELETE | `/api/bank/unlink` | Unlink bank account |

### Alarms
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/alarms` | List alarms |
| POST | `/api/alarms` | Create alarm |
| GET | `/api/alarms/:id` | Get alarm |
| PUT | `/api/alarms/:id` | Update alarm |
| DELETE | `/api/alarms/:id` | Delete alarm |

### Penalties
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/penalties/trigger` | Trigger penalty on snooze |
| GET | `/api/penalties/history` | Get penalty history |
| GET | `/api/penalties/stats` | Get penalty stats |

### Webhooks
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/webhooks/stripe` | Stripe webhook handler |

---

## Payment Design

See [`docs/payment-design.md`](docs/payment-design.md) for details on:

- Payment state machine (PENDING → PROCESSING → COMPLETED/FAILED)
- Idempotency via `(occurrenceId, snoozeNumber)` + Stripe idempotency keys
- Daily cap enforcement
- Webhook processing
- Deletion safety
- Mandate/authorization tracking

---

## Testing

```bash
cd backend
npm test
```

Tests cover:
- Duplicate snooze idempotency (returns existing penalty, no double charge)
- Delayed payment (stays PROCESSING until webhook)
- Failed payment handling
- Webhook processing (succeeded + failed events)
- Account deletion blocked by pending payments
- Bank unlink calls Stripe removal
- Daily cap enforcement

---

## License

Proprietary. All rights reserved.
