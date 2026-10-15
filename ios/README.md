# Sloozly iOS — AlarmKit Integration

> **Minimum:** iOS 26+ / Xcode 26 / Swift 6.0  
> **Architecture:** SwiftUI + AlarmKit + Live Activities + App Intents

## Quick Start

### Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| Xcode | 26+ | AlarmKit is iOS 26+ only |
| XcodeGen | 2.42+ | `brew install xcodegen` |
| iOS device | iPhone running iOS 26+ | AlarmKit **does not work in Simulator** for alarm alerts |
| Firebase | — | A `GoogleService-Info.plist` from your Firebase project |

### Generate Xcode Project

```bash
cd ios
brew install xcodegen   # if not installed
xcodegen generate
open Sloozly.xcodeproj
```

XcodeGen reads `project.yml` and produces `Sloozly.xcodeproj` with three
targets:

| Target | Type | Description |
|--------|------|-------------|
| **Sloozly** | App | Main SwiftUI app |
| **SloozlyWidgetExtension** | Widget Extension | Live Activity for alarm countdown on Lock Screen / Dynamic Island |
| **SloozlyTests** | Unit Test Bundle | Pure-logic tests (occurrence IDs, snooze store, queue) |

### Configure Signing & Firebase

1. In Xcode, select the **Sloozly** target → Signing & Capabilities.
2. Set your Team and Bundle ID (default: `com.sloozly.app`).
3. Do the same for **SloozlyWidgetExtension** (`com.sloozly.app.widget`).
4. Drop `GoogleService-Info.plist` from Firebase Console into `ios/Sloozly/`.
5. Ensure the App Group `group.com.sloozly.app` is registered on your
   Apple Developer account and enabled in both targets.

### Build & Run

```bash
# In Xcode:
# 1. Select the "Sloozly" scheme
# 2. Pick a physical iPhone (not Simulator)
# 3. ⌘R to build and run
```

### Run Tests

```bash
# In Xcode: ⌘U to run all tests, or:
xcodebuild test \
  -project Sloozly.xcodeproj \
  -scheme Sloozly \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Tests cover:
- `OccurrenceIDGeneratorTests` — deterministic ID generation, parsing
- `SnoozeEventStoreTests` — file persistence, queries, pruning
- `SnoozeEventQueueTests` — duplicate prevention, crash recovery, permanent failures, in-flight enqueue
- `UUIDv5Tests` — stable UUID generation for AlarmKit alarm IDs

---

## Architecture

### AlarmKit Flow

```text
AlarmModel → AlarmKitManager → AlarmManager.shared.schedule()
                                      │
                        ┌─────────────┼──────────────┐
                        ▼             ▼              ▼
                   Stop intent   Snooze intent   alarmUpdates
                        │             │              │
                        │       Persist event     UI state only
                        │             │
                        └──────→ SnoozeEventQueue
                                      │
                           POST /penalties/trigger
```

Only `SnoozeAlarmIntent` records snoozes. State observation updates the UI;
it never creates another penalty for the same tap. Interrupted `.sending` events
are recovered as pending when the store reloads, preserving their occurrence ID
and snooze number. Permanently failed events are excluded from retries.

CI builds both targets and runs the simulator unit tests with a generated dummy
Firebase configuration. Device alarm delivery and real sandbox debits still need
the manual checks below.

### Key Components

| File | Purpose |
|------|---------|
| `Services/AlarmKitManager.swift` | Schedule/cancel alarms, observe auth and state, map backend model → AlarmKit config |
| `Services/OccurrenceIDGenerator.swift` | Deterministic `{alarmId}_{YYYY-MM-DD}` occurrence IDs |
| `Services/SnoozeEventStore.swift` | File-backed JSON persistence for snooze events |
| `Services/SnoozeEventQueue.swift` | Offline retry queue with exponential backoff |
| `Intents/SnoozeAlarmIntent.swift` | `LiveActivityIntent` — records snooze + queues penalty |
| `Intents/StopAlarmIntent.swift` | `LiveActivityIntent` — processes remaining queue on dismiss |
| `Models/SloozlyAlarmMetadata.swift` | `AlarmMetadata` struct carrying backend alarm ID + label |
| `SloozlyWidgetExtension/SloozlyAlarmLiveActivity.swift` | Live Activity for countdown UI |

### Occurrence ID Design

Each alarm firing generates an occurrence ID: `{backendAlarmId}_{YYYY-MM-DD}`.

- Deterministic: same alarm + same calendar day = same ID
- The backend uses `(occurrenceId, snoozeNumber)` as the idempotency key
- If the app crashes and restarts mid-snooze-session, the same occurrence ID
  is regenerated and duplicate API calls are safe

### Offline Resilience

1. Snooze events are written to `SnoozeEventStore` (JSON file) immediately
2. `SnoozeEventQueue` attempts to send each event to the backend
3. On network failure: event stays `.pending`, retried with exponential backoff
4. On 401: Firebase token is refreshed, then retried
5. On 4xx (validation/not-found): event is marked `.failed` (permanent)
6. On app launch: all pending events are reprocessed

### Firebase Token Refresh

`APIService` now automatically retries requests on 401:
1. Catches 401 response
2. Calls `AuthService.shared.refreshToken()` (Firebase `getIDToken(forcingRefresh: true)`)
3. Retries the original request once with the fresh token
4. If refresh itself fails, throws `APIError.tokenRefreshFailed`

---

## Info.plist Keys

| Key | Value | Required By |
|-----|-------|-------------|
| `NSAlarmKitUsageDescription` | "Sloozly needs alarm access to wake you up on time…" | AlarmKit |
| `UIBackgroundModes` | `remote-notification` | Firebase push notifications |

### Entitlements

Both the app and widget extension use:
- `com.apple.security.application-groups` → `group.com.sloozly.app`

---

## What's New vs. v0 (UNUserNotification)

| Feature | v0 | v1 (AlarmKit) |
|---------|-----|---------------|
| Alarm delivery | `UNCalendarNotificationTrigger` | `AlarmManager.schedule()` |
| Silent mode | ❌ Does not ring | ✅ Rings through silent + Focus |
| Lock Screen UI | Banner notification | Live Activity countdown |
| Dynamic Island | None | Compact + expanded views |
| Snooze handling | `UNNotificationAction` | `LiveActivityIntent` + `secondaryButtonBehavior: .countdown` |
| Occurrence IDs | None (snooze count in memory) | Durable `{alarmId}_{date}` on disk |
| Offline resilience | None (penalty lost on crash) | File-backed queue with retry |
| Token refresh | None | Auto-retry on 401 |

---

## Testing on Device

AlarmKit alarms **must be tested on a physical iPhone running iOS 26+**.
The Simulator does not support alarm alerts.

### Manual Test Checklist

- [ ] Grant AlarmKit authorization when prompted
- [ ] Schedule a one-time alarm → verify it fires through silent mode
- [ ] Schedule a repeating alarm → verify it fires on the correct days
- [ ] Tap "Snooze ($5.00)" → verify countdown restarts, penalty is recorded
- [ ] Tap "I'm Up!" → verify alarm stops, pending events are flushed
- [ ] Kill the app during a snooze → relaunch → verify pending events are retried
- [ ] Put device in Airplane Mode → snooze → restore connection → verify retry works
- [ ] Check penalty history shows correct statuses (Processing, Completed, Failed)
- [ ] Verify the Live Activity appears on Lock Screen during countdown
- [ ] Deny AlarmKit authorization → verify the banner explains how to enable
- [ ] Check Settings > Sloozly shows correct authorization state

---

## Troubleshooting

### "Alarms Disabled" banner shows up
Go to iOS Settings → Sloozly → Alarms & Timers → enable.

### Alarm doesn't ring
1. Check `AlarmKitManager.authorizationState` is `.authorized`
2. Verify the alarm is enabled in the backend (`isEnabled: true`)
3. Check Xcode console for "Failed to schedule AlarmKit alarm" errors

### Penalties not sending
1. Check `SnoozeEventQueue.pendingCount` in the debug view
2. Look for network errors in Xcode console
3. Verify the backend is running and reachable
4. Check `snooze_events.json` in the app's Application Support directory
