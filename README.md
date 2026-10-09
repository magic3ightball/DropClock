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

Next
- [ ] Set Team in Signing & Capabilities, add Time Sensitive Notifications capability
- [ ] App icon (1024px) in `Assets.xcassets/AppIcon`
- [ ] StoreKit configuration file for local purchase testing
- [ ] Separate schedules per eye with different start dates (done via one entry per eye for now)
- [ ] PDF report for the eye doctor (History tab, replace CSV)
- [ ] Glaucoma IOP log (Japan)
- [ ] iOS 26+: AlarmKit alarms that break through Silent/Focus
- [ ] Unit tests for ScheduleEngine

## One-time owner tasks in App Store Connect
1. Paid Apps Agreement, bank account, tax form (W-8BEN)
2. Enroll in App Store Small Business Program (15% commission)
3. Create the non-consumable IAP above, price $4.99
