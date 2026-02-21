# Clock In

A Flutter mobile application for tracking daily work attendance. The app sends scheduled notifications on weekdays (excluding public holidays) to remind the user to clock in and out, automatically calculating total hours worked and overtime.

---

## Features

- Scheduled weekday notifications for clock in and clock out
- One-tap clock in / clock out from the home screen
- Automatic calculation of total hours worked and overtime
- Lunch break deducted automatically from total hours
- NSW public holidays pre-loaded (2026–2027)
- Full record editing in case the user missed clocking in or out
- Configurable settings: notification times, standard work hours, lunch break duration

---

## Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter (Dart) |
| Local Database | SQLite via `sqflite` |
| Notifications | `flutter_local_notifications` |
| Date Formatting | `intl` |
| Timezone Support | `timezone` |

---

## Project Structure

```
lib/
├── main.dart
├── database/
│   └── database_helper.dart     # SQLite CRUD operations and initialization
├── models/
│   ├── record.dart              # Work record entity
│   ├── holiday.dart             # Public holiday entity
│   └── setting.dart             # App setting entity
├── screens/
│   ├── home_screen.dart         # Clock in/out UI and daily summary
│   └── records_screen.dart      # Record history and editing (coming soon)
├── services/
│   └── notification_service.dart # Weekday notification scheduling
└── utils/
    └── time_calculator.dart     # Hours and overtime calculation logic
```

---

## Database Schema

### `records`
| Column | Type | Description |
|---|---|---|
| id | INTEGER PK | Auto-incremented identifier |
| date | TEXT | Work date `yyyy-MM-dd` |
| start_time | TEXT | Clock in time `HH:mm` |
| end_time | TEXT | Clock out time `HH:mm` |
| total_hours | REAL | Hours worked after lunch deduction |
| otime_hours | REAL | Overtime hours above standard |
| timestamp | TEXT | ISO 8601 record creation time |

### `holidays`
| Column | Type | Description |
|---|---|---|
| id | INTEGER PK | Auto-incremented identifier |
| name | TEXT | Holiday name |
| date | TEXT | Holiday date `yyyy-MM-dd` |
| timestamp | TEXT | ISO 8601 record creation time |

### `settings`
| Column | Type | Description |
|---|---|---|
| id | INTEGER PK | Auto-incremented identifier |
| key | TEXT UNIQUE | Setting identifier |
| value | TEXT | Setting value |
| timestamp | TEXT | ISO 8601 last updated time |

---

## Default Settings

| Key | Default Value | Description |
|---|---|---|
| `checkin_notification_time` | `08:00` | Morning notification time |
| `checkout_notification_time` | `17:00` | Afternoon notification time |
| `standard_work_hours` | `8` | Hours before overtime kicks in |
| `lunch_break_minutes` | `30` | Lunch break deducted from total |
| `work_days` | `1,2,3,4,5` | Monday to Friday |
| `notifications_enabled` | `true` | Master notification switch |

---

## Hours Calculation Logic

```
raw_hours     = end_time - start_time
total_hours   = raw_hours - (lunch_break_minutes / 60)
otime_hours   = max(0, total_hours - standard_work_hours)
```

Example:
```
start_time          = 08:00
end_time            = 17:00
lunch_break         = 30 min

total_hours         = 9.0 - 0.5  = 8.5h
otime_hours         = 8.5 - 8.0  = 0.5h
```

---

## Android Permissions

The following permissions are required in `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
<uses-permission android:name="android.permission.USE_EXACT_ALARM"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```

The boot receiver ensures scheduled notifications survive device restarts.

---

## Getting Started

### Prerequisites

- Flutter SDK >= 3.0.0
- Android Studio with Android SDK
- A physical device or emulator running Android 8.0+

### Installation

```bash
git clone https://github.com/your-username/clock-in.git
cd clock-in
flutter pub get
flutter run
```

---

## Dependencies

```yaml
sqflite: ^2.3.0
path: ^1.9.0
flutter_local_notifications: ^17.0.0
timezone: ^0.9.0
intl: ^0.19.0
provider: ^6.1.0
```

---

## Roadmap

- [x] Database layer (records, holidays, settings)
- [x] Time calculation utilities
- [x] Notification service with weekday scheduling
- [x] Home screen with clock in/out
- [ ] Records screen with edit capability
- [ ] Settings screen
- [ ] Holidays management screen
- [ ] Reports / summary view

---

## Public Holidays

NSW public holidays for 2026 and 2027 are pre-loaded on first install based on official dates from the [NSW Government website](https://www.nsw.gov.au/about-nsw/public-holidays). Additional holidays can be managed from the holidays screen.

---

## License

This project is for personal use.