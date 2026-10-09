# DropClock

Eye drop reminder for post-surgery tapers and glaucoma. Personal project (not part of any Academy repo).

## Status (v0.1 skeleton)

Done
- SwiftUI + SwiftData app, iOS 17+, iPhone, portrait
- Tabs: Today / Drops / History / Settings, onboarding, paywall
- `ScheduleEngine`: taper phases, even spacing between first/last drop, 5-min gap between different drops
- `NotificationScheduler`: rolling 60-notification window (iOS cap is 64), time-sensitive, "Mark as taken" and "Snooze 5 min" actions
- `UnlockStore`: StoreKit 2 one-time unlock (`com.magic3ightball.dropclock.unlock`), 1 drop free
- Localization: English, Japanese, Korean (`Localizable.xcstrings`)
- App Store copy draft: `docs/ASO.md`
- App icon 1024px (no alpha)
- "Second eye starts on a different date" (creates one entry per eye; same drug in both eyes shares a time slot)
- A4 PDF report for the eye doctor (current drops, daily adherence, eye pressure), paid feature
- Eye pressure (IOP) log with Swift Charts line chart

Next
- [ ] Set Team in Signing & Capabilities, add Time Sensitive Notifications capability
- [ ] StoreKit configuration file for local purchase testing
- [ ] Test PDF output and notifications on a real device
- [ ] iOS 26+: AlarmKit alarms that break through Silent/Focus
- [ ] Unit tests for ScheduleEngine

## One-time owner tasks in App Store Connect
1. Paid Apps Agreement, bank account, tax form (W-8BEN)
2. Enroll in App Store Small Business Program (15% commission)
3. Create the non-consumable IAP above, price $4.99
